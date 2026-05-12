// =====================================================================
// Role D — Roll-Result Narrator
// =====================================================================
// Narrates dice roll outcomes in 1-2 vivid sentences for moments that
// deserve flavour: natural 1, natural 20, or a margin >= 10 from DC.
// Routine rolls cost nothing — the deterministic outcome text is shown.
//
// Called from `resolve-roll/index.ts` AFTER the full structured LLM
// call. On trigger, this replaces dm.narration with a more vivid version;
// all other fields (options, state_changes, story_progress) remain from
// the main call.
//
// Token budget per call: ~100 in, ~80 out.  Model: gpt-4o-mini.
//
// Failure mode: any error returns `null` → caller keeps the main LLM
// narration. Role D is always decorative, never load-bearing.
// =====================================================================

import { callStructured } from "./openai.ts";
import { ENV } from "./env.ts";

export interface RollNarratorInput {
  scene: string;          // one-line scene summary fed from the node body or purpose
  skill_or_check: string; // e.g. "Persuasion", "d20 attack vs AC 14"
  rolled: number;         // raw d20 value (before modifier)
  total: number;          // raw + modifier
  dc: number;
  margin: number;         // total - dc (negative = failed)
  is_crit: boolean;       // rolled === 20
  is_fumble: boolean;     // rolled === 1
}

const SYSTEM_PROMPT =
  "You are a combat narrator for a retro pixel-art TTRPG. " +
  "A dice roll just happened. Narrate the outcome in 1-2 short sentences. " +
  "Critical fail (fumble) → vivid mishap or narrowly-avoided disaster. " +
  "Critical success → brief triumphant moment. " +
  "Big margin success → confident execution. " +
  "Big margin failure → embarrassing or costly stumble. " +
  "Do NOT change the facts or the success/failure outcome provided. " +
  "No meta-commentary, no listing options. Output only the narration JSON.";

const SCHEMA = {
  name: "roll_narrator_output",
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["narration"],
    properties: {
      narration: { type: "string", minLength: 1, maxLength: 400 },
    },
  },
  strict: true,
};

/**
 * Returns a 1-2 sentence vivid narration for crit/fumble/big-margin rolls,
 * or `null` on any failure. Callers must keep their existing narration on null.
 */
export async function narrateRoll(input: RollNarratorInput): Promise<string | null> {
  try {
    const res = await callStructured<{ narration: string }>({
      model: ENV.OPENAI_MODEL_SUMMARY(),
      systemPrompt: SYSTEM_PROMPT,
      messages: [{ role: "user", content: JSON.stringify(input) }],
      jsonSchema: SCHEMA,
      maxTokens: 130,
      temperature: 0.85,
    });
    const out = (res.parsed?.narration ?? "").trim();
    return out || null;
  } catch (err) {
    console.error("narrateRoll failed:", (err as Error).message);
    return null;
  }
}
