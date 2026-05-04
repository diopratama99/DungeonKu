// OpenAI client wrapper. Centralised so we can swap models or add retry/backoff in one
// place. We use OpenAI's structured outputs feature (response_format with a JSON schema)
// rather than asking the model to "respond as JSON" — the latter is fragile, the former is
// guaranteed by the API.

import { OpenAI } from "./deps.ts";
import { ENV } from "./env.ts";

let cached: OpenAI | null = null;

export function getOpenAI(): OpenAI {
  if (cached) return cached;
  cached = new OpenAI({ apiKey: ENV.OPENAI_API_KEY() });
  return cached;
}

export interface StructuredCallParams {
  model?: string;
  systemPrompt: string;
  messages: Array<{ role: "user" | "assistant" | "system"; content: string }>;
  jsonSchema: {
    name: string;
    schema: Record<string, unknown>;
    strict?: boolean;
  };
  maxTokens: number;
  temperature?: number;
}

export interface StructuredCallResult<T> {
  parsed: T;
  rawText: string;
  promptTokens: number;
  completionTokens: number;
  model: string;
}

/**
 * Call gpt-4o (or whatever OPENAI_MODEL points to) with a strict JSON schema and parse
 * the result. We deliberately throw if the parse fails — the schema is supposed to make
 * that impossible; if it happens we want the function to error loudly so we notice.
 */
export async function callStructured<T>(params: StructuredCallParams): Promise<StructuredCallResult<T>> {
  const client = getOpenAI();
  const model = params.model ?? ENV.OPENAI_MODEL();
  const messages = [
    { role: "system" as const, content: params.systemPrompt },
    ...params.messages,
  ];

  const completion = await client.chat.completions.create({
    model,
    messages,
    max_tokens: params.maxTokens,
    temperature: params.temperature ?? 0.7,
    response_format: {
      type: "json_schema",
      json_schema: {
        name: params.jsonSchema.name,
        schema: params.jsonSchema.schema,
        strict: params.jsonSchema.strict ?? true,
      },
    },
  });

  const choice = completion.choices[0];
  const rawText = choice?.message?.content ?? "";
  if (!rawText) throw new Error("OpenAI returned empty content");

  let parsed: T;
  try {
    parsed = JSON.parse(rawText) as T;
  } catch (err) {
    throw new Error(`Failed to parse structured-output JSON: ${(err as Error).message}; raw=${rawText.slice(0, 200)}`);
  }

  return {
    parsed,
    rawText,
    promptTokens: completion.usage?.prompt_tokens ?? 0,
    completionTokens: completion.usage?.completion_tokens ?? 0,
    model,
  };
}

/**
 * Plain text completion. Used by summarize-campaign and death narration where we don't need
 * structured output.
 */
export async function callPlain(params: {
  model?: string;
  systemPrompt: string;
  userPrompt: string;
  maxTokens: number;
  temperature?: number;
}): Promise<{ text: string; promptTokens: number; completionTokens: number; model: string }> {
  const client = getOpenAI();
  const model = params.model ?? ENV.OPENAI_MODEL();
  const completion = await client.chat.completions.create({
    model,
    messages: [
      { role: "system", content: params.systemPrompt },
      { role: "user", content: params.userPrompt },
    ],
    max_tokens: params.maxTokens,
    temperature: params.temperature ?? 0.7,
  });
  return {
    text: completion.choices[0]?.message?.content ?? "",
    promptTokens: completion.usage?.prompt_tokens ?? 0,
    completionTokens: completion.usage?.completion_tokens ?? 0,
    model,
  };
}
