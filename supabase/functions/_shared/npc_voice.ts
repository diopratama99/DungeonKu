// =====================================================================
// Role C — NPC Voice Rewriter
// =====================================================================
// Rewrites an NPC's authored line into 1-2 sentences that better match
// their voice + current mood. Preserves the information content
// exactly — promises, numbers, names, refusals all carry through.
//
// Called from `story_engine.ts:renderNodePayload` when:
//   1. profiles.ai_role_npc_voice_enabled = true, AND
//   2. node.type === 'dialog' AND node.speaker is non-null, AND
//   3. node.speaker_profile contains usable tone tags
//      (any node.speaker_profile.tone array; fallback to "neutral")
//
// Mood derivation: if `node.speaker_profile.default_mood` exists we use
// that; otherwise we infer from node.tags (e.g. "alarm_uncertain" tag
// nudges toward "tense", "ending" + outcome 'success' tag nudges
// toward "wistful"). Phase 2 keeps this lightweight; richer flag-based
// mood logic can come later.
//
// Token budget per call: ~100 in, ~50 out.  Model: gpt-4o-mini.
// =====================================================================

import { callStructured } from "./openai.ts";
import { ENV } from "./env.ts";
import type { AvatarFlavor } from "./profile_context.ts";

export interface NpcVoiceInput {
  npc_name: string;
  npc_tone: string[];               // from node.speaker_profile.tone
  npc_mood: string;                 // resolved by caller
  raw_line: string;                 // node.body verbatim
  player_voice_tags: string[];      // avatar.personality_tags
}

const SYSTEM_PROMPT =
  "Rewrite the NPC's line to fit their voice and current mood. " +
  "Preserve the information content exactly — names, numbers, refusals, promises, " +
  "and any concrete plot facts must carry through. " +
  "Output 1-2 sentences max. Do NOT add new facts or characters. " +
  "Do NOT prefix with the speaker's name; just give the line.";

const SCHEMA = {
  name: "npc_voice_output",
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["rewritten"],
    properties: {
      rewritten: { type: "string", minLength: 1, maxLength: 400 },
    },
  },
  strict: true,
};

/**
 * Resolve the speaker's tone array out of the speaker_profile JSONB.
 * Tolerates either ["a","b"] or {tone:["a","b"]}. Returns [] if none.
 */
export function extractToneTags(
  speakerProfile: Record<string, unknown> | null | undefined,
): string[] {
  if (!speakerProfile) return [];
  const t = speakerProfile.tone;
  if (Array.isArray(t)) return t.map((x) => String(x));
  return [];
}

/**
 * Resolve the mood. Order:
 *   1. speaker_profile.default_mood (string)
 *   2. cheap tag-based heuristic
 *   3. "neutral"
 */
export function resolveMood(
  speakerProfile: Record<string, unknown> | null | undefined,
  nodeTags: string[],
): string {
  if (speakerProfile && typeof speakerProfile.default_mood === "string") {
    return speakerProfile.default_mood as string;
  }
  if (nodeTags.includes("ending")) return "wistful";
  if (nodeTags.includes("combat")) return "tense";
  if (nodeTags.includes("pivotal")) return "weighted";
  return "neutral";
}

/**
 * Returns the rewritten line, or `null` on failure / pre-check skip.
 * Callers must fall back to the original body on null. Pre-checks
 * mirror reskin.ts: very short lines aren't worth rewriting.
 */
export async function rewriteNpcLine(
  input: NpcVoiceInput,
  avatar: AvatarFlavor | null,
): Promise<string | null> {
  if (!input.raw_line || input.raw_line.trim().length < 10) return null;
  if (!input.npc_name) return null;

  const userPayload = {
    npc_name: input.npc_name,
    npc_tone: input.npc_tone.length > 0 ? input.npc_tone : ["plain"],
    npc_mood: input.npc_mood || "neutral",
    raw_line: input.raw_line,
    player_voice_tags: input.player_voice_tags.length > 0
      ? input.player_voice_tags
      : (avatar?.personality_tags ?? []),
  };

  try {
    const res = await callStructured<{ rewritten: string }>({
      model: ENV.OPENAI_MODEL_SUMMARY(),
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: "user", content: JSON.stringify(userPayload) }],
      jsonSchema: SCHEMA,
      maxTokens: 140,
      temperature: 0.9,
    });
    const out = (res.parsed?.rewritten ?? "").trim();
    if (!out) return null;
    return out;
  } catch (err) {
    console.error("rewriteNpcLine failed:", (err as Error).message);
    return null;
  }
}
