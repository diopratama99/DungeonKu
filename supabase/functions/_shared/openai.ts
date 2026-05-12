// OpenAI client wrapper. Centralised so we can swap models or add retry/backoff in one
// place.
//
// IMPORTANT: we use response_format: { type: "json_object" } (basic JSON mode) rather
// than the stricter { type: "json_schema" } (Structured Outputs). Reason: many
// OpenAI-compatible providers — GitHub Models, LiteLLM proxies, OpenRouter, Groq, local
// servers — don't implement json_schema and reject the request with 400 "Invalid
// response_format provided". json_object is the universally supported lowest common
// denominator. To compensate for the looser guarantee we (a) inject the schema into the
// system prompt as instructions and (b) re-validate the parsed JSON against zod schemas
// in the calling functions — belt and suspenders.

import { OpenAI } from "./deps.ts";
import { ENV } from "./env.ts";

/**
 * Run an OpenAI call with one retry on transient upstream failures.
 * We surface the actual HTTP status / provider message so docker logs
 * make it obvious whether we hit a rate limit, quota cap, or just a 5xx.
 */
async function callWithRetry<T>(
  label: string,
  fn: () => Promise<T>,
): Promise<T> {
  try {
    return await fn();
  } catch (err) {
    const e = err as { status?: number; message?: string; code?: string };
    const status = e?.status ?? 0;
    const transient = status === 502 || status === 503 || status === 504 || status === 408 || status === 429;
    console.error(JSON.stringify({
      level: "error",
      where: `openai.${label}`,
      attempt: 1,
      status,
      code: e?.code ?? null,
      message: (e?.message ?? String(err)).slice(0, 500),
      will_retry: transient,
    }));
    if (!transient) throw err;
    // Backoff. 429 deserves a longer wait so we don't hammer the limit.
    const delayMs = status === 429 ? 1500 : 600;
    await new Promise((r) => setTimeout(r, delayMs));
    try {
      return await fn();
    } catch (err2) {
      const e2 = err2 as { status?: number; message?: string; code?: string };
      console.error(JSON.stringify({
        level: "error",
        where: `openai.${label}`,
        attempt: 2,
        status: e2?.status ?? 0,
        code: e2?.code ?? null,
        message: (e2?.message ?? String(err2)).slice(0, 500),
        will_retry: false,
      }));
      throw err2;
    }
  }
}

let cached: OpenAI | null = null;

export function getOpenAI(): OpenAI {
  if (cached) return cached;
  const baseURL = ENV.OPENAI_BASE_URL();
  cached = new OpenAI({
    apiKey: ENV.OPENAI_API_KEY(),
    ...(baseURL ? { baseURL } : {}),
  });
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

  // Inject the schema into the system prompt so the model knows the exact
  // shape we want, then ask for json_object response_format (universally
  // supported). Zod re-validation in callers catches malformed output.
  const schemaJson = JSON.stringify(params.jsonSchema.schema, null, 2);
  const schemaInstruction =
    `\n\nYou MUST respond with a valid JSON object matching exactly this JSON Schema ` +
    `(schema name: "${params.jsonSchema.name}"):\n\n${schemaJson}\n\n` +
    `Return ONLY the raw JSON object — no markdown fences, no preamble, no commentary. ` +
    `Every property listed under "required" must be present. Use null for unknowns ` +
    `where the schema allows; otherwise omit only optional fields.`;

  const augmentedMessages = [
    { role: "system" as const, content: params.systemPrompt + schemaInstruction },
    ...params.messages,
  ];

  type ChatCompletion = OpenAI.Chat.Completions.ChatCompletion;
  
  // Some providers (Gemini via routers) don't support response_format.
  // Only include it for models that are known to support it.
  const supportsJsonMode = model.startsWith("gpt-") || model.includes("openai");
  
  const completion = await callWithRetry<ChatCompletion>("callStructured", () =>
    client.chat.completions.create({
      model,
      messages: augmentedMessages,
      max_tokens: params.maxTokens,
      temperature: params.temperature ?? 0.7,
      ...(supportsJsonMode ? { response_format: { type: "json_object" } } : {}),
    }) as Promise<ChatCompletion>
  );

  const choice = completion.choices[0];
  const rawText = choice?.message?.content ?? "";
  const finishReason = choice?.finish_reason ?? "unknown";
  if (!rawText) throw new Error("OpenAI returned empty content");

  let parsed: T;
  try {
    parsed = JSON.parse(rawText) as T;
  } catch (err) {
    // finish_reason === "length" means the model hit max_tokens mid-output.
    // Surface that distinctly so we can act on it (bump the budget) instead
    // of chasing prompt issues.
    const truncated = finishReason === "length";
    const usage = completion.usage;
    console.error(JSON.stringify({
      level: "error",
      where: "openai.callStructured.parse",
      finish_reason: finishReason,
      truncated,
      prompt_tokens: usage?.prompt_tokens ?? null,
      completion_tokens: usage?.completion_tokens ?? null,
      raw_tail: rawText.slice(-120),
    }));
    const hint = truncated
      ? " (LLM hit max_tokens — bump maxTokensBySituation)"
      : "";
    throw new Error(
      `Failed to parse structured-output JSON${hint}: ${(err as Error).message}; raw=${rawText.slice(0, 200)}`,
    );
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
  type ChatCompletion = OpenAI.Chat.Completions.ChatCompletion;
  const completion = await callWithRetry<ChatCompletion>("callPlain", () =>
    client.chat.completions.create({
      model,
      messages: [
        { role: "system", content: params.systemPrompt },
        { role: "user", content: params.userPrompt },
      ],
      max_tokens: params.maxTokens,
      temperature: params.temperature ?? 0.7,
    }) as Promise<ChatCompletion>
  );
  return {
    text: completion.choices[0]?.message?.content ?? "",
    promptTokens: completion.usage?.prompt_tokens ?? 0,
    completionTokens: completion.usage?.completion_tokens ?? 0,
    model,
  };
}
