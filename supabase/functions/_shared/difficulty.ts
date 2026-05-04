// "Very Hard" baseline. The LLM can only suggest DCs and damage values; the server clamps
// them to these ranges before applying anything. This is the load-bearing constant file
// for tuning the game.

export const DIFFICULTY = {
  // Min/max DC the server accepts from an LLM-suggested roll. LLM outputs outside the band
  // get clamped (and we log the disagreement for tuning).
  dc: { min: 12, max: 22 },

  // Player-relative max damage the server will let an LLM-driven enemy attack do, scaled
  // by player level. Used as a safety net only — combat-action's deterministic AI uses
  // its own damage formulas and ignores this clamp.
  enemyDamageMaxByLevel: [
    /* lvl 1 */ 14,
    /* lvl 2 */ 18,
    /* lvl 3 */ 22,
    /* lvl 4 */ 26,
    /* lvl 5 */ 30,
    /* lvl 6 */ 34,
    /* lvl 7 */ 38,
    /* lvl 8 */ 42,
    /* lvl 9 */ 46,
    /* lvl 10 */ 50,
  ],

  // XP curve. Index = level the player is currently at. Value = XP needed to reach next.
  xpToNext: [
    /* placeholder for index 0 */ 0,
    /* lvl 1 → 2  */ 100,
    /* lvl 2 → 3  */ 250,
    /* lvl 3 → 4  */ 500,
    /* lvl 4 → 5  */ 900,
    /* lvl 5 → 6  */ 1400,
    /* lvl 6 → 7  */ 2000,
    /* lvl 7 → 8  */ 2700,
    /* lvl 8 → 9  */ 3500,
    /* lvl 9 → 10 */ 4400,
  ],

  hpGainPerLevel: 5,
  maxLevel: 10,

  // Anti-stall: if no boss state change and no significant location/NPC change for this
  // many turns, the dm-turn function injects an URGENT PACING block forcing the DM to
  // escalate.
  antiStallThresholdTurns: 4,

  // Adaptive token budget per turn (situation classifier picks one of these).
  maxTokensBySituation: {
    dialog: 120,
    exploration: 180,
    combat: 220,
    transition: 300,
  },

  // Death narration token cap.
  deathNarrationMaxTokens: 150,

  // Summarisation: summarize older messages every N turns, keeping the last K in context.
  summarizeEvery: 12,
  recentMessageWindow: 8,
} as const;

export function clampDC(dc: number): number {
  return Math.max(DIFFICULTY.dc.min, Math.min(DIFFICULTY.dc.max, Math.round(dc)));
}

export function xpRequiredForNext(level: number): number {
  if (level >= DIFFICULTY.maxLevel) return Number.POSITIVE_INFINITY;
  return DIFFICULTY.xpToNext[level] ?? Number.POSITIVE_INFINITY;
}
