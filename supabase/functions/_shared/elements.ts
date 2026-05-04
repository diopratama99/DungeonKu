// Element multiplier table. Server-side only. The LLM never sees the math — it only gets
// a plain-language description of the result ("super effective", "resisted", "normal").

export type Element =
  | "fire" | "water" | "wind" | "earth" | "lightning"
  | "light" | "dark" | "neutral";

export const ELEMENTS: Element[] = [
  "fire", "water", "wind", "earth", "lightning", "light", "dark", "neutral",
];

// Rock-paper-scissors for the 6 base elements. Numbers are multipliers applied to base damage.
const RPS_DOUBLE: Record<Element, Element> = {
  fire: "wind",        // fire beats wind
  wind: "earth",       // wind beats earth
  earth: "lightning",  // earth beats lightning
  lightning: "water",  // lightning beats water
  water: "fire",       // water beats fire
  // light/dark/neutral don't participate in the RPS triangle
  light: "neutral",
  dark: "neutral",
  neutral: "neutral",
};

const RPS_HALF: Record<Element, Element> = {
  fire: "water",
  wind: "fire",
  earth: "wind",
  lightning: "earth",
  water: "lightning",
  light: "neutral",
  dark: "neutral",
  neutral: "neutral",
};

export function elementMultiplier(attacker: Element, defender: Element): number {
  // Same element penalty for the 6 base elements (fire/fire, water/water, etc).
  const sixBase: Element[] = ["fire", "water", "wind", "earth", "lightning"];
  if (attacker === defender && sixBase.includes(attacker)) return 0.5;

  // Light vs Dark special.
  if (attacker === "light" && defender === "dark") return 1.5;
  if (attacker === "dark" && defender === "light") return 1.5;

  // Light has a slight penalty against Neutral (anti-corruption themed).
  if (attacker === "light" && defender === "neutral") return 0.85;

  // Light/Dark vs other non-counterpart: 1.0
  if (attacker === "light" || attacker === "dark") return 1.0;
  if (defender === "light" || defender === "dark") return 1.0;

  // Neutral attackers and defenders: 1.0 (after the Light/Neutral special above).
  if (attacker === "neutral" || defender === "neutral") return 1.0;

  // RPS triangle for the 5 base elements (fire/water/wind/earth/lightning).
  if (RPS_DOUBLE[attacker] === defender) return 2.0;
  if (RPS_HALF[attacker] === defender) return 0.5;

  return 1.0;
}

/**
 * Produce a plain-language description of an element multiplier. This is what we splice
 * into the LLM call #2 prompt — never the multiplier number itself.
 */
export function describeMultiplier(mul: number): string {
  if (mul >= 2.0) return "super effective";
  if (mul >= 1.5) return "very effective";
  if (mul >= 1.05) return "slightly effective";
  if (mul >= 0.95) return "normal";
  if (mul >= 0.7)  return "slightly resisted";
  if (mul >= 0.4)  return "resisted";
  return "barely effective";
}

export function isValidElement(s: string): s is Element {
  return (ELEMENTS as string[]).includes(s);
}
