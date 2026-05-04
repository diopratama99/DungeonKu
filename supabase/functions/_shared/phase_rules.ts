// Phase advance validation. The LLM can *suggest* an advance via story_progress; the
// server only honors it if the hard rules below are met. If the LLM disagrees, we log the
// disagreement (useful debug data for prompt tuning).

export type Phase = "intro" | "rising" | "climax" | "resolution";

export interface BossSummary {
  tier: "small" | "medium" | "big";
  status: "unencountered" | "encountered" | "defeated";
}

export interface PhaseDecisionInput {
  current: Phase;
  llmSuggestAdvance: boolean;
  turnsInCurrentPhase: number;
  bosses: BossSummary[];
}

export interface PhaseDecision {
  next: Phase;
  changed: boolean;
  reason: string;
  /** True if the LLM suggested a transition we refused. */
  llmDisagreement: boolean;
}

function ratio(arr: BossSummary[], pred: (b: BossSummary) => boolean): number {
  if (arr.length === 0) return 0;
  return arr.filter(pred).length / arr.length;
}

export function decideNextPhase(input: PhaseDecisionInput): PhaseDecision {
  const { current, llmSuggestAdvance, turnsInCurrentPhase, bosses } = input;
  const smalls = bosses.filter((b) => b.tier === "small");
  const mediums = bosses.filter((b) => b.tier === "medium");
  const bigs = bosses.filter((b) => b.tier === "big");

  const smallsDefeated = ratio(smalls, (b) => b.status === "defeated");
  const mediumsDefeated = ratio(mediums, (b) => b.status === "defeated");
  const bigDefeated = bigs.length === 0
    ? false
    : bigs.every((b) => b.status === "defeated");

  switch (current) {
    case "intro": {
      const eligible = turnsInCurrentPhase >= 3 || llmSuggestAdvance;
      if (eligible) {
        return {
          next: "rising",
          changed: true,
          reason: turnsInCurrentPhase >= 3 ? "intro turn quota met" : "LLM-driven early advance",
          llmDisagreement: false,
        };
      }
      return {
        next: "intro",
        changed: false,
        reason: "still establishing world",
        llmDisagreement: llmSuggestAdvance,
      };
    }
    case "rising": {
      const eligible = smallsDefeated >= 0.6 && mediumsDefeated >= 0.5;
      if (llmSuggestAdvance && eligible) {
        return {
          next: "climax",
          changed: true,
          reason: `bosses cleared (${(smallsDefeated * 100).toFixed(0)}% small, ${(mediumsDefeated * 100).toFixed(0)}% medium)`,
          llmDisagreement: false,
        };
      }
      return {
        next: "rising",
        changed: false,
        reason: "boss progress threshold not met",
        llmDisagreement: llmSuggestAdvance && !eligible,
      };
    }
    case "climax": {
      const eligible = bigDefeated;
      if (eligible) {
        return {
          next: "resolution",
          changed: true,
          reason: "big boss defeated",
          llmDisagreement: false,
        };
      }
      return {
        next: "climax",
        changed: false,
        reason: "big boss still standing",
        llmDisagreement: llmSuggestAdvance && !eligible,
      };
    }
    case "resolution": {
      // resolution → completed is handled in dm-turn (mark campaign completed after 1–2 turns)
      return {
        next: "resolution",
        changed: false,
        reason: "already in resolution",
        llmDisagreement: false,
      };
    }
  }
}

export function phaseGuidance(phase: Phase): string {
  switch (phase) {
    case "intro":
      return "Establish the world, the character's place in it, and a clear hook. Show, don't lecture. Aim to wrap intro within 3-5 turns.";
    case "rising":
      return "Escalate. The player should encounter conflict and small or medium threats. Do not let the player rest in safe locations for more than 1 turn. Move the story toward bigger confrontations.";
    case "climax":
      return "High stakes. The big boss is the focus. Every scene should feed into that confrontation. No new side threads.";
    case "resolution":
      return "Wrap up. Narrate consequences, brief farewells, the world after. 1-2 turns max, then mark the campaign complete.";
  }
}

export const URGENT_PACING_BLOCK = `URGENT PACING: The player has been stalling for several turns. In your next narration, force a story event: a new threat appears, an NPC arrives with urgent news, or the environment changes dramatically. Do not let the player continue the current loop.`;
