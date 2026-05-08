// System-prompt builder.
//
// Token economy note: we re-inject template world_setting + dm_guidance every turn so we
// don't have to keep long message history. The LLM never has to "remember" what world it's
// in; the system prompt re-asserts it. This trades a constant ~500 prompt tokens for an
// otherwise-unbounded conversation history.

import type { CampaignContext } from "./context.ts";
import { phaseGuidance, URGENT_PACING_BLOCK } from "./phase_rules.ts";
import type { SituationType } from "./classifier.ts";
import { TEMPLATE_COMMON_ACTIONS } from "./classifier.ts";
import { DIFFICULTY } from "./difficulty.ts";

export interface BuildPromptOptions {
  ctx: CampaignContext;
  situation: SituationType;
  injectAntiStall: boolean;
  /** Optional extra block appended right before the OUTPUT RULES (used by resolve-roll). */
  extraBlock?: string | null;
}

const OUTPUT_RULES = `OUTPUT RULES:
- Respond in 1-3 short paragraphs MAX. Never longer.
- No meta-commentary, no recap of what the player said, no "as a Dungeon Master, I...".
- Every sentence must advance the story or describe what the player perceives.
- Do not list options for the player in your narration; the system handles options separately.
- When relevant, weave the character's stats and inventory into your narration (e.g. "Your STR 16 lets you shove the door open").
- For dice rolls: only request a roll when uncertainty is meaningful. Don't request rolls for trivial actions.
- For combat: do NOT decide turn order, damage numbers, or whether enemies attack. Only narrate.
- For side quests: when the player's action obviously matches a side quest hook (helping an NPC, retrieving a specific item), set side_quest_intent.
- Phase suggestions: only suggest advancing if the story has earned it.`;

export function buildSystemPrompt(opts: BuildPromptOptions): string {
  const { ctx, situation, injectAntiStall, extraBlock } = opts;

  const bossLines = ctx.bosses
    .map((b) => `  - ${b.name} (${b.tier}) [${b.status}] id=${b.template_boss_id}`)
    .join("\n");

  const inventoryLines = ctx.inventory.length === 0
    ? "  (empty)"
    : ctx.inventory
        .map((i) => `  - ${i.name} x${i.qty} [${i.item_type}, ${i.element}]${i.description ? ` — ${i.description}` : ""}`)
        .join("\n");

  const skillLines = ctx.skills.length === 0
    ? "  (none)"
    : ctx.skills.map((s) => {
        const cost = s.cost_type === "free" ? "free" : `${s.cost_amount} ${s.cost_type}`;
        const affordable = s.cost_type === "free" || ctx.characterSheet.resource_current >= s.cost_amount;
        return `  - ${s.name} [${s.element}, cost=${cost}, ${affordable ? "available" : "OUT_OF_RESOURCE"}] — ${s.description}`;
      }).join("\n");

  const sideMissionLines = ctx.sideMissions.length === 0
    ? "  (none active)"
    : ctx.sideMissions
        .filter((m) => m.status === "active")
        .map((m) => `  - ${m.title} (step ${m.current_step})`)
        .join("\n");

  const statusEffectLines = ctx.characterSheet.status_effects.length === 0
    ? "  (none)"
    : ctx.characterSheet.status_effects
        .map((s) => `  - ${s.label} (${s.key}) for ${s.expires_in_turns} turns`)
        .join("\n");

  const stats = ctx.characterSheet.current_stats;
  const statBlock = `STR ${stats.STR}, DEX ${stats.DEX}, CON ${stats.CON}, INT ${stats.INT}, WIS ${stats.WIS}, CHA ${stats.CHA}`;

  const phaseBlock = `CURRENT PHASE: ${ctx.campaign.phase} (turns in phase: ${ctx.campaign.turns_in_current_phase})
PHASE GUIDANCE: ${phaseGuidance(ctx.campaign.phase)}`;

  const templateCommonsBlock = TEMPLATE_COMMON_ACTIONS[situation]
    .map((a) => `  - ${a.label}`)
    .join("\n");

  const tokenBudget = DIFFICULTY.maxTokensBySituation[situation];

  const memorySection = ctx.worldMemory
    ? `WORLD MEMORY (compressed history; treat as established fact):\n${ctx.worldMemory}`
    : "WORLD MEMORY: (none yet — this is early in the campaign)";

  const combatNote = ctx.activeCombat
    ? `\nACTIVE COMBAT: yes (round ${ctx.activeCombat.round_number}). Combat resolution is server-side; you only narrate.\n`
    : "";

  return [
    `You are the Dungeon Master for "${ctx.template.title}" (${ctx.template.genre}).`,
    `WORLD SETTING:\n${ctx.template.world_setting}`,
    `DM GUIDANCE FOR THIS TEMPLATE:\n${ctx.template.dm_guidance}`,
    "",
    phaseBlock,
    `BOSSES (template milestones):\n${bossLines || "  (none defined)"}`,
    `ACTIVE SIDE MISSIONS:\n${sideMissionLines}`,
    "",
    `CHARACTER:`,
    `  Name: ${ctx.characterSheet.name}`,
    `  Class: ${ctx.characterSheet.class}`,
    `  Base element: ${ctx.characterSheet.base_element}`,
    `  Level ${ctx.characterSheet.level} (${ctx.characterSheet.xp} XP)`,
    `  HP ${ctx.characterSheet.hp}/${ctx.characterSheet.max_hp}, AC ${ctx.characterSheet.ac}`,
    `  ${ctx.characterSheet.resource_type.toUpperCase()} ${ctx.characterSheet.resource_current}/${ctx.characterSheet.resource_max}`,
    `  Stats: ${statBlock}`,
    `  Status effects:\n${statusEffectLines}`,
    `  Inventory:\n${inventoryLines}`,
    `  Skills:\n${skillLines}`,
    "",
    memorySection,
    combatNote,
    `SITUATION TYPE (server classified): ${situation}`,
    `Token budget for narration: ${tokenBudget}`,
    `Template-common options the player will already see for this situation:\n${templateCommonsBlock}`,
    "",
    `OPTIONS POLICY (HARD REQUIREMENT \u2014 do not skip):`,
    `- ALWAYS return AT LEAST 2 SITUATIONAL options (kind="situational"), ideally 3. They must reference concrete things in THIS scene: an NPC by role, an object, a sound, a path, etc. Generic verbs like "look around" or "move on" are forbidden \u2014 those are template-common and the system will fill them only if you under-deliver.`,
    `- Each situational option label must be 2-7 words and start with a verb. Examples: "Pry open the rusted grate", "Whistle to the drunkard at the bar", "Step onto the half-frozen pond", "Listen at the boiler door".`,
    `- For pivotal moments (shocking reveals, hard moral choices, major confrontations): set pivotal_moment=true AND return 3-5 options, all kind="pivotal". Pivotal options should fork the story meaningfully.`,
    `- For combat: situational options should reference the specific enemy, terrain, or your skills (e.g. "Bait the brute toward the gantry", "Ignite the lamp oil at his feet").`,
    `- For dialog: at least one situational option must engage with what the NPC just said.`,
    `- IDs must be unique strings within this turn (e.g., "opt_charge", "opt_negotiate"). Prefer short, descriptive IDs.`,
    "",
    injectAntiStall ? URGENT_PACING_BLOCK + "\n" : "",
    extraBlock ?? "",
    OUTPUT_RULES,
  ].filter(Boolean).join("\n");
}

/**
 * Convert recent messages into the OpenAI chat history format. We keep player + dm only;
 * system messages from past turns are omitted because their context is re-injected.
 */
export function recentMessagesToChatHistory(
  recent: CampaignContext["recentMessages"],
): Array<{ role: "user" | "assistant"; content: string }> {
  return recent
    .filter((m) => m.role === "player" || m.role === "dm")
    .map((m) => ({
      role: m.role === "player" ? "user" : "assistant",
      content: m.content,
    } as const));
}
