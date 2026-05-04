// Two layers of schema definition:
//   1. The OpenAI **JSON schema** sent to the model via response_format (structured outputs).
//      OpenAI requires standard JSON Schema (Draft-07-ish, strict mode), not a zod schema,
//      so we hand-write it.
//   2. A matching **zod schema** that we use to re-validate after parsing. This is belt-and-
//      suspenders: structured outputs should make the JSON schema-conformant, but defending
//      against "the model returned an empty narration" is still our job.
//
// Keep these two in lockstep when you change one.

import { z } from "./deps.ts";

// ---------------------- Shared atoms ----------------------
export const SituationTypeSchema = z.enum(["dialog", "exploration", "combat", "transition"]);
export const PhaseSchema = z.enum(["intro", "rising", "climax", "resolution"]);
export const DiceKindSchema = z.enum(["d20", "d6", "d100"]);
export const ModifierStatSchema = z.enum(["STR", "DEX", "CON", "INT", "WIS", "CHA"]);
export const ElementSchema = z.enum([
  "fire", "water", "wind", "earth", "lightning", "light", "dark", "neutral",
]);

// ---------------------- state_changes ----------------------
// We accept a discriminated union of supported state-change types. Anything else is
// rejected at validation time so the LLM can't invent new categories.
export const StateChangeSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("inventory_add"),
    name: z.string(),
    qty: z.number().int().positive(),
    description: z.string().default(""),
    element: ElementSchema.default("neutral"),
    item_type: z.enum(["weapon", "armor", "consumable", "misc"]).default("misc"),
  }),
  z.object({
    type: z.literal("inventory_remove"),
    name: z.string(),
    qty: z.number().int().positive(),
  }),
  z.object({
    type: z.literal("hp_delta"),
    amount: z.number().int(),               // negative = damage, positive = heal
    reason: z.string().default(""),
  }),
  z.object({
    type: z.literal("resource_delta"),
    amount: z.number().int(),               // mp/stamina change
    reason: z.string().default(""),
  }),
  z.object({
    type: z.literal("xp_add"),
    amount: z.number().int().nonnegative(),
    reason: z.string().default(""),
  }),
  z.object({
    type: z.literal("status_add"),
    key: z.string(),
    label: z.string(),
    duration: z.number().int().positive(),
    magnitude: z.number().int().default(0),
  }),
  z.object({
    type: z.literal("status_remove"),
    key: z.string(),
  }),
  z.object({
    type: z.literal("boss_status_change"),
    template_boss_id: z.string(),           // matches a campaign_bosses.template_boss_id
    next_status: z.enum(["encountered", "defeated"]),
  }),
  z.object({
    type: z.literal("rest"),
    sub_type: z.enum(["night_sleep", "brief_rest"]),
    safe: z.boolean().default(true),
  }),
  z.object({
    type: z.literal("combat_start"),
    enemies: z.array(z.object({
      name: z.string(),
      archetype: z.enum(["aggressive", "tactical", "boss"]),
      element: ElementSchema.default("neutral"),
      hp: z.number().int().positive(),
      ac: z.number().int().positive(),
      base_damage: z.number().int().nonnegative(),
      attack_dice: z.string().default("d6"),
      is_boss: z.boolean().default(false),
      template_boss_id: z.string().nullable().default(null),
    })).min(1),
  }),
  z.object({
    type: z.literal("side_quest_progress"),
    template_side_mission_id: z.string(),
    event: z.enum(["progress_step", "complete", "fail"]),
  }),
]);

export type StateChange = z.infer<typeof StateChangeSchema>;

// ---------------------- requires_roll ----------------------
export const RequiresRollSchema = z.object({
  dice: DiceKindSchema,
  purpose: z.string(),
  dc: z.number().int(),
  modifier_stat: ModifierStatSchema.nullable(),
}).nullable();

// ---------------------- options ----------------------
export const OptionSchema = z.object({
  id: z.string(),
  label: z.string(),
  kind: z.enum(["template_common", "situational", "pivotal"]),
  icon: z.string().default("sparkle"),
});

// ---------------------- side_quest_intent ----------------------
export const SideQuestIntentSchema = z.object({
  trigger: z.string(),
  confidence: z.enum(["low", "medium", "high"]).default("medium"),
}).nullable();

// ---------------------- story_progress ----------------------
export const StoryProgressSchema = z.object({
  current_phase: PhaseSchema,
  suggest_phase_advance: z.boolean(),
  reason: z.string().default(""),
});

// ---------------------- dm-turn output ----------------------
export const DmTurnOutputSchema = z.object({
  narration: z.string().min(1),
  state_changes: z.array(StateChangeSchema),
  requires_roll: RequiresRollSchema,
  story_progress: StoryProgressSchema,
  options: z.array(OptionSchema).max(5),
  pivotal_moment: z.boolean(),
  side_quest_intent: SideQuestIntentSchema,
});
export type DmTurnOutput = z.infer<typeof DmTurnOutputSchema>;

// ---------------------- resolve-roll output ----------------------
// Identical to dm-turn except requires_roll MUST be null.
export const ResolveRollOutputSchema = DmTurnOutputSchema.extend({
  requires_roll: z.null(),
});
export type ResolveRollOutput = z.infer<typeof ResolveRollOutputSchema>;

// ---------------------- HTTP request bodies ----------------------
export const DmTurnRequestSchema = z.object({
  campaign_id: z.string().uuid(),
  player_message: z.string().min(1).max(2000),
  selected_option_id: z.string().nullable().optional(),
});

export const ResolveRollRequestSchema = z.object({
  pending_roll_id: z.string().uuid(),
});

export const CheapResolveRequestSchema = z.object({
  campaign_id: z.string().uuid(),
  option_id: z.string(),
});

export const CombatActionRequestSchema = z.object({
  campaign_id: z.string().uuid(),
  action: z.discriminatedUnion("kind", [
    z.object({ kind: z.literal("attack") }),
    z.object({ kind: z.literal("skill"), skill_id: z.string() }),
    z.object({ kind: z.literal("defend") }),
    z.object({ kind: z.literal("use_item"), item_id: z.string() }),
    z.object({ kind: z.literal("flee") }),
  ]),
});

export const SummarizeRequestSchema = z.object({
  campaign_id: z.string().uuid(),
});

// ---------------------- Plain JSON schemas for OpenAI structured outputs ----------------------
// OpenAI strict mode requires:
//   - additionalProperties: false on every object
//   - every property listed in `required`
//   - no defaults
//
// We use anyOf + const for the discriminated state_change.

const stateChangeSchema = {
  anyOf: [
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["inventory_add"] },
        name: { type: "string" }, qty: { type: "integer", minimum: 1 },
        description: { type: "string" },
        element: { type: "string", enum: ["fire","water","wind","earth","lightning","light","dark","neutral"] },
        item_type: { type: "string", enum: ["weapon","armor","consumable","misc"] },
      },
      required: ["type", "name", "qty", "description", "element", "item_type"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["inventory_remove"] },
        name: { type: "string" }, qty: { type: "integer", minimum: 1 },
      },
      required: ["type", "name", "qty"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["hp_delta"] },
        amount: { type: "integer" }, reason: { type: "string" },
      },
      required: ["type", "amount", "reason"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["resource_delta"] },
        amount: { type: "integer" }, reason: { type: "string" },
      },
      required: ["type", "amount", "reason"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["xp_add"] },
        amount: { type: "integer", minimum: 0 }, reason: { type: "string" },
      },
      required: ["type", "amount", "reason"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["status_add"] },
        key: { type: "string" }, label: { type: "string" },
        duration: { type: "integer", minimum: 1 }, magnitude: { type: "integer" },
      },
      required: ["type", "key", "label", "duration", "magnitude"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["status_remove"] },
        key: { type: "string" },
      },
      required: ["type", "key"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["boss_status_change"] },
        template_boss_id: { type: "string" },
        next_status: { type: "string", enum: ["encountered", "defeated"] },
      },
      required: ["type", "template_boss_id", "next_status"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["rest"] },
        sub_type: { type: "string", enum: ["night_sleep", "brief_rest"] },
        safe: { type: "boolean" },
      },
      required: ["type", "sub_type", "safe"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["combat_start"] },
        enemies: {
          type: "array",
          minItems: 1,
          items: {
            type: "object", additionalProperties: false,
            properties: {
              name: { type: "string" },
              archetype: { type: "string", enum: ["aggressive", "tactical", "boss"] },
              element: { type: "string", enum: ["fire","water","wind","earth","lightning","light","dark","neutral"] },
              hp: { type: "integer", minimum: 1 },
              ac: { type: "integer", minimum: 1 },
              base_damage: { type: "integer", minimum: 0 },
              attack_dice: { type: "string" },
              is_boss: { type: "boolean" },
              template_boss_id: { type: ["string", "null"] },
            },
            required: ["name", "archetype", "element", "hp", "ac", "base_damage", "attack_dice", "is_boss", "template_boss_id"],
          },
        },
      },
      required: ["type", "enemies"],
    },
    {
      type: "object", additionalProperties: false,
      properties: {
        type: { type: "string", enum: ["side_quest_progress"] },
        template_side_mission_id: { type: "string" },
        event: { type: "string", enum: ["progress_step", "complete", "fail"] },
      },
      required: ["type", "template_side_mission_id", "event"],
    },
  ],
};

const requiresRollSchema = {
  anyOf: [
    { type: "null" },
    {
      type: "object", additionalProperties: false,
      properties: {
        dice: { type: "string", enum: ["d20", "d6", "d100"] },
        purpose: { type: "string" },
        dc: { type: "integer" },
        modifier_stat: {
          anyOf: [
            { type: "string", enum: ["STR", "DEX", "CON", "INT", "WIS", "CHA"] },
            { type: "null" },
          ],
        },
      },
      required: ["dice", "purpose", "dc", "modifier_stat"],
    },
  ],
};

const sideQuestIntentSchema = {
  anyOf: [
    { type: "null" },
    {
      type: "object", additionalProperties: false,
      properties: {
        trigger: { type: "string" },
        confidence: { type: "string", enum: ["low", "medium", "high"] },
      },
      required: ["trigger", "confidence"],
    },
  ],
};

export const DM_TURN_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    narration: { type: "string" },
    state_changes: { type: "array", items: stateChangeSchema },
    requires_roll: requiresRollSchema,
    story_progress: {
      type: "object",
      additionalProperties: false,
      properties: {
        current_phase: { type: "string", enum: ["intro", "rising", "climax", "resolution"] },
        suggest_phase_advance: { type: "boolean" },
        reason: { type: "string" },
      },
      required: ["current_phase", "suggest_phase_advance", "reason"],
    },
    options: {
      type: "array",
      maxItems: 5,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          id: { type: "string" },
          label: { type: "string" },
          kind: { type: "string", enum: ["template_common", "situational", "pivotal"] },
          icon: { type: "string" },
        },
        required: ["id", "label", "kind", "icon"],
      },
    },
    pivotal_moment: { type: "boolean" },
    side_quest_intent: sideQuestIntentSchema,
  },
  required: [
    "narration", "state_changes", "requires_roll", "story_progress",
    "options", "pivotal_moment", "side_quest_intent",
  ],
} as const;

// resolve-roll: same shape, but requires_roll must be null.
export const RESOLVE_ROLL_JSON_SCHEMA = {
  ...DM_TURN_JSON_SCHEMA,
  properties: {
    ...DM_TURN_JSON_SCHEMA.properties,
    requires_roll: { type: "null" },
  },
} as const;
