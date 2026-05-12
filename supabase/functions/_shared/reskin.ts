// =====================================================================
// Role A — Flavor Reskinner
// =====================================================================
// Rewrites a node's authored body into 2-3 sentences in the avatar's
// voice. Preserves every named entity and fact — the deterministic
// gameplay underneath is unchanged.
//
// Called from `story_engine.ts:renderNodePayload` when:
//   1. profiles.ai_role_reskinner_enabled = true, AND
//   2. node.ai_reskin_policy === 'always', OR
//   3. node.ai_reskin_policy === 'pivotal_only' AND node.tags includes 'pivotal'
//
// Token budget per call: ~150 in, ~80 out.  Model: gpt-4o-mini.
//
// Failure mode: if the LLM call throws OR returns malformed JSON, we
// log + return `null` so the caller falls back to the dry authored
// body. AI roles must never be load-bearing — they're decoration.
// =====================================================================

import { callStructured } from "./openai.ts";
import { ENV } from "./env.ts";
import type { AvatarFlavor } from "./profile_context.ts";

export interface ReskinInput {
  node_body: string;
  scene_type: "scene" | "dialog" | "choice" | "combat" | "outcome" | "transition";
  voice_tags: string[];     // typically avatar.personality_tags
  avatar_origin: string;    // typically avatar.backstory (1-2 sentences)
}

const SYSTEM_PROMPT =
  "You are a prose stylist for a retro pixel-art TTRPG. " +
  "You will receive a dry narration paragraph and rewrite it in 2-3 sentences, " +
  "preserving every fact and named entity exactly. " +
  "Do NOT add new facts, NPCs, or plot beats. " +
  "Keep the tone consistent with the supplied voice tags. " +
  "If the original mentions a character, item, or place by name, the rewrite must use the same name. " +
  "Output ONLY the rewritten prose inside the JSON shape — no commentary.";

const SCHEMA = {
  name: "reskin_output",
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["rewritten"],
    properties: {
      rewritten: { type: "string", minLength: 1, maxLength: 800 },
    },
  },
  strict: true,
};

/**
 * Returns the reskinned body, or `null` if the call fails or the input
 * is too short to be worth rewriting (under ~30 chars). Callers must
 * fall back to the original body on null.
 */
export async function reskinNarration(
  input: ReskinInput,
  avatar: AvatarFlavor | null,
): Promise<string | null> {
  // Cheap heuristic: very short bodies (one-liners, transitions) don't
  // benefit from reskinning and waste tokens. Skip them.
  if (!input.node_body || input.node_body.trim().length < 30) return null;

  const userPayload = {
    node_body: input.node_body,
    scene_type: input.scene_type,
    voice_tags: input.voice_tags.length > 0
      ? input.voice_tags
      : (avatar?.personality_tags ?? []),
    avatar_origin: input.avatar_origin || (avatar?.backstory ?? ""),
  };

  try {
    const res = await callStructured<{ rewritten: string }>({
      model: ENV.OPENAI_MODEL_SUMMARY(),
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: "user", content: JSON.stringify(userPayload) }],
      jsonSchema: SCHEMA,
      maxTokens: 220,
      temperature: 0.85,
    });
    const out = (res.parsed?.rewritten ?? "").trim();
    if (!out) return null;
    return out;
  } catch (err) {
    console.error("reskinNarration failed:", (err as Error).message);
    return null;
  }
}
