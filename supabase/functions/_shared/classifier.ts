// Situation classifier. Pure heuristics, no LLM call. Runs before we build the prompt so
// we can pick the right max_tokens budget and the right common-action template.

import { DIFFICULTY } from "./difficulty.ts";

export type SituationType = "dialog" | "exploration" | "combat" | "transition";

export interface ClassifyContext {
  /** True if the previous turn ended with a phase change OR a boss state change. */
  recentTransition: boolean;
  /** True if there is an active combat encounter. */
  inCombat: boolean;
  /** True if the previous turn included a dice roll. */
  recentDiceRoll: boolean;
}

const DIALOG_TRIGGERS = [
  /^["'„«]/,                                              // starts with a quote
  /\b(?:say|ask|tell|reply|answer|whisper|shout|greet)\b/i,
];

export function classify(playerMessage: string, ctx: ClassifyContext): SituationType {
  // 1. Combat takes priority: dice roll just resolved while a boss is engaged, or open combat.
  if (ctx.inCombat) return "combat";
  if (ctx.recentDiceRoll && ctx.recentTransition) return "combat";

  // 2. Transitions (phase change, boss defeated) get the largest budget.
  if (ctx.recentTransition) return "transition";

  // 3. Dialog detection by surface form of the player's message.
  if (DIALOG_TRIGGERS.some((re) => re.test(playerMessage.trim()))) return "dialog";

  // 4. Default to exploration.
  return "exploration";
}

export function maxTokensFor(s: SituationType): number {
  return DIFFICULTY.maxTokensBySituation[s];
}

/**
 * The "template common" actions for each situation. Most turns merge these with the LLM's
 * situational suggestions; some turns (cheap-resolve) pick from these alone.
 */
export const TEMPLATE_COMMON_ACTIONS: Record<SituationType, Array<{ id: string; label: string; icon: string }>> = {
  combat: [
    { id: "tc_attack",  label: "Attack with weapon",   icon: "sword" },
    { id: "tc_skill",   label: "Use a skill",          icon: "sparkle" },
    { id: "tc_defend",  label: "Defend",               icon: "shield" },
    { id: "tc_flee",    label: "Try to flee",          icon: "running" },
  ],
  dialog: [
    { id: "tc_ask",     label: "Ask a question",       icon: "speech" },
    { id: "tc_agree",   label: "Agree",                icon: "check" },
    { id: "tc_refuse",  label: "Refuse",               icon: "cross" },
    { id: "tc_persuade",label: "Try to persuade",      icon: "speech" },
  ],
  exploration: [
    { id: "tc_look",    label: "Look around",          icon: "eye" },
    { id: "tc_search",  label: "Search for clues",     icon: "magnify" },
    { id: "tc_move",    label: "Move on",              icon: "footstep" },
    { id: "tc_rest",    label: "Rest briefly",         icon: "fire" },
  ],
  transition: [
    { id: "tc_continue",label: "Continue",             icon: "arrow" },
    { id: "tc_reflect", label: "Reflect a moment",     icon: "sparkle" },
  ],
};
