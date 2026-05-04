// Server-side, CSPRNG-backed dice. Never trust the client to roll — the dice animation in
// the Flutter app is purely visual and lands on the face the server has already chosen.

export type DiceKind = "d20" | "d6" | "d100";

export type RollOutcome = "critical_success" | "success" | "fail" | "critical_fail";

export interface RollResult {
  dice: DiceKind;
  raw: number;        // raw face value (1..max)
  modifier: number;
  total: number;      // raw + modifier
  dc: number;
  outcome: RollOutcome;
}

/**
 * Cryptographically secure integer in [1, max]. Uses a rejection sampling loop to avoid
 * modulo bias with values like d100 that don't divide 2^32 evenly.
 */
function secureD(max: number): number {
  if (max < 1 || !Number.isInteger(max)) throw new Error(`bad die: ${max}`);
  const buf = new Uint32Array(1);
  // Largest multiple of `max` that fits in 2^32; we reject above that to keep the distribution flat.
  const limit = Math.floor(0x1_0000_0000 / max) * max;
  // eslint-disable-next-line no-constant-condition
  while (true) {
    crypto.getRandomValues(buf);
    if (buf[0] < limit) return (buf[0] % max) + 1;
  }
}

export function rollDie(dice: DiceKind): number {
  switch (dice) {
    case "d20": return secureD(20);
    case "d6":  return secureD(6);
    case "d100": return secureD(100);
  }
}

/**
 * Parse simple dice strings like "2d6", "d8", "3d4" into { count, sides }.
 * Used by skills.dice in seed data.
 */
export function parseDiceExpression(expr: string): { count: number; sides: number } {
  const m = expr.trim().match(/^(\d*)d(\d+)$/i);
  if (!m) throw new Error(`bad dice expression: ${expr}`);
  return {
    count: m[1] ? parseInt(m[1], 10) : 1,
    sides: parseInt(m[2], 10),
  };
}

/**
 * Roll an arbitrary "NdS" expression for damage etc. Uses the same CSPRNG as rollDie.
 * For sides outside {6,20,100} we just sample uniformly with rejection.
 */
export function rollExpression(expr: string): number {
  const { count, sides } = parseDiceExpression(expr);
  let total = 0;
  for (let i = 0; i < count; i++) total += secureD(sides);
  return total;
}

/**
 * d20-flavoured roll for skill checks and attacks: critical on natural 20, critical fail on
 * natural 1, otherwise compare total vs DC. d6 and d100 don't get crit semantics.
 */
export function resolveRoll(dice: DiceKind, modifier: number, dc: number): RollResult {
  const raw = rollDie(dice);
  const total = raw + modifier;
  let outcome: RollOutcome;
  if (dice === "d20") {
    if (raw === 20) outcome = "critical_success";
    else if (raw === 1) outcome = "critical_fail";
    else outcome = total >= dc ? "success" : "fail";
  } else {
    outcome = total >= dc ? "success" : "fail";
  }
  return { dice, raw, modifier, total, dc, outcome };
}

/** D&D-style modifier from a stat value: floor((stat - 10) / 2). */
export function modifierFromStat(stat: number): number {
  return Math.floor((stat - 10) / 2);
}
