// =====================================================================
// Role B — Free-Text Intent Mapper
// =====================================================================
// Maps a player's free-text action ("aku coba menyuap penjaga dengan
// sepotong emas") to ONE of the currently-available scripted options.
// Returns null + a brief reason when no option fits — never invents new
// options, never changes the underlying graph.
//
// Rate-limited at the endpoint layer to 5 calls per campaign session
// via campaign_node_state.flags.intent_map_count. The helper itself is
// stateless.
//
// Token budget per call: ~200 in, ~30 out.  Model: gpt-4o-mini.
// =====================================================================

import { callStructured } from "./openai.ts";
import { ENV } from "./env.ts";

export interface IntentOption {
  id: string;        // story_edges.option_id
  label: string;     // visible button text
}

export interface IntentInput {
  free_text: string;
  scene_summary: string;        // ~1 sentence — usually the first 240 chars of node.body
  options: IntentOption[];
}

export interface IntentResult {
  option_id: string | null;
  reason: string;
}

const SYSTEM_PROMPT =
  "The player typed a free-text action in a tabletop RPG. " +
  "Map it to ONE of the listed valid options that best matches the player's intent. " +
  "If the player's text fits an option's spirit even with different words, pick that option. " +
  "If none of the options reasonably fit, return null for option_id and explain in one short sentence why. " +
  "Do NOT invent new options. Do NOT pick an option just because the player named a noun in it. " +
  "The reason must be concise (one sentence) and player-facing.";

const SCHEMA = {
  name: "intent_map_output",
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["option_id", "reason"],
    properties: {
      option_id: { type: ["string", "null"] },
      reason: { type: "string", maxLength: 240 },
    },
  },
  strict: true,
};

/**
 * Resolve the player's free-text intent to one of `input.options`.
 * On any error or malformed return, returns
 * `{ option_id: null, reason: "..." }` so callers always get a usable
 * shape — no exceptions propagate to the endpoint.
 */
export async function mapIntent(input: IntentInput): Promise<IntentResult> {
  const trimmed = input.free_text.trim();
  if (!trimmed) {
    return { option_id: null, reason: "I didn't catch what you wanted to do." };
  }
  if (trimmed.length > 400) {
    return {
      option_id: null,
      reason: "That's too long — try again with a shorter sentence.",
    };
  }
  if (input.options.length === 0) {
    return {
      option_id: null,
      reason: "There's nothing reasonable you can do here right now.",
    };
  }

  const userPayload = {
    free_text: trimmed,
    current_scene: input.scene_summary,
    options: input.options.map((o) => ({ id: o.id, label: o.label })),
  };

  try {
    const res = await callStructured<IntentResult>({
      model: ENV.OPENAI_MODEL_SUMMARY(),
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: "user", content: JSON.stringify(userPayload) }],
      jsonSchema: SCHEMA,
      maxTokens: 120,
      temperature: 0.2,
    });

    const optionId = res.parsed?.option_id ?? null;
    const reason = (res.parsed?.reason ?? "").trim();

    // Defensive: model occasionally returns an option_id that isn't in
    // our list. Reject those — never let a hallucinated id reach
    // /player-action where it would 400.
    if (optionId !== null) {
      const exists = input.options.some((o) => o.id === optionId);
      if (!exists) {
        return {
          option_id: null,
          reason: reason || "I couldn't match that to anything you can do here.",
        };
      }
    }
    return {
      option_id: optionId,
      reason: reason || (optionId
        ? "Mapped your action to the closest option."
        : "That doesn't fit any of the options available here."),
    };
  } catch (err) {
    console.error("mapIntent failed:", (err as Error).message);
    return {
      option_id: null,
      reason: "I couldn't process that action — try one of the listed options.",
    };
  }
}
