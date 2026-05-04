// resolve-roll — player tapped the dice → server rolls → LLM call #2 narrates the outcome.
//
// Two-call orchestration on a dice-required turn (the part of the spec we most want to
// get right):
//
//   Turn N step 1 (dm-turn): LLM emits requires_roll → pending_rolls row created.
//   Turn N step 2 (this function): server rolls + LLM narrates outcome.
//
// We call the LLM once with the ROLL RESULT baked into the system prompt as plain language,
// and we constrain its output schema so requires_roll MUST be null (no recursive rolls).

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import {
  ResolveRollOutputSchema,
  ResolveRollRequestSchema,
  RESOLVE_ROLL_JSON_SCHEMA,
} from "../_shared/schemas.ts";
import type { ResolveRollOutput } from "../_shared/schemas.ts";
import { loadCampaignContext } from "../_shared/context.ts";
import { classify, maxTokensFor } from "../_shared/classifier.ts";
import type { SituationType } from "../_shared/classifier.ts";
import { buildSystemPrompt } from "../_shared/prompts.ts";
import { resolveRoll, modifierFromStat } from "../_shared/dice.ts";
import type { DiceKind } from "../_shared/dice.ts";
import { decideNextPhase } from "../_shared/phase_rules.ts";
import { applyStateChanges } from "../_shared/state_changes.ts";
import { callStructured } from "../_shared/openai.ts";
import { ENV } from "../_shared/env.ts";

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse(405, "method_not_allowed", "Use POST");

  const log = newLogger("resolve-roll");
  const startedAt = Date.now();

  const user = await getAuthenticatedUser(req);
  if (!user) return errorResponse(401, "unauthorized", "Missing or invalid Bearer token");

  let body: z.infer<typeof ResolveRollRequestSchema>;
  try {
    body = ResolveRollRequestSchema.parse(await req.json());
  } catch (err) {
    return errorResponse(400, "bad_body", (err as Error).message);
  }

  const sb = getServiceClient();

  // Load pending roll + verify ownership.
  const { data: pending, error: pendingErr } = await sb
    .from("pending_rolls")
    .select("*, campaigns(id, user_id, status)")
    .eq("id", body.pending_roll_id)
    .maybeSingle();
  if (pendingErr || !pending) {
    return errorResponse(404, "pending_roll_not_found", pendingErr?.message ?? "Not found");
  }
  if (pending.resolved_at) {
    return errorResponse(409, "pending_roll_already_resolved", "This roll was already resolved");
  }
  const campaign = pending.campaigns as { id: string; user_id: string; status: string } | null;
  if (!campaign || campaign.user_id !== user.id) {
    return errorResponse(404, "pending_roll_not_found", "Not found");
  }
  if (campaign.status !== "active") {
    return errorResponse(409, "campaign_not_active", `Campaign is ${campaign.status}`);
  }

  // Load full context.
  const ctx = await loadCampaignContext(sb, campaign.id);

  // ------------------------------ Roll ------------------------------
  const dice = pending.dice as DiceKind;
  const dc = pending.dc as number;
  const modifierStat = pending.modifier_stat as keyof typeof ctx.characterSheet.current_stats | null;
  const modifier = modifierStat ? modifierFromStat(ctx.characterSheet.current_stats[modifierStat] ?? 10) : 0;
  const roll = resolveRoll(dice, modifier, dc);

  log.info("rolled", {
    pending_roll_id: body.pending_roll_id,
    dice, raw: roll.raw, modifier, total: roll.total, dc, outcome: roll.outcome,
  });

  // Persist the dice_rolls row immediately so the result is logged even if the LLM call fails.
  await sb.from("dice_rolls").insert({
    campaign_id: campaign.id,
    dice,
    raw_result: roll.raw,
    modifier,
    total: roll.total,
    dc,
    outcome: roll.outcome,
    purpose: pending.purpose as string,
  });

  // ------------------------------ Build LLM call #2 ------------------------------
  const outcomeWord = {
    critical_success: "CRITICAL SUCCESS",
    success: "SUCCESS",
    fail: "FAILURE",
    critical_fail: "CRITICAL FAILURE",
  }[roll.outcome];

  const purpose = pending.purpose as string;
  const rollBlock = `ROLL RESULT (computed by server, narrate this outcome — do not change the numbers):
- Purpose: ${purpose}
- Dice: ${dice}
- Raw: ${roll.raw}${modifierStat ? ` (+${modifier} from ${modifierStat})` : ""}
- Total: ${roll.total} vs DC ${dc}
- Outcome: ${outcomeWord}

Narrate the outcome in 1-2 sentences. Do NOT request another roll. Set requires_roll to null.`;

  // Use the same situation classifier; the player's "message" for classification purposes
  // is the purpose of the roll.
  const situation: SituationType = classify(purpose, {
    recentTransition: false,
    recentDiceRoll: true,
    inCombat: ctx.activeCombat !== null,
  });
  const maxTokens = maxTokensFor(situation);

  const systemPrompt = buildSystemPrompt({
    ctx,
    situation,
    injectAntiStall: false,
    extraBlock: rollBlock,
  });

  // We pass the original LLM-call-1 narration as the latest assistant message so the model
  // has the immediate context for "what was being rolled".
  const callOneNarration = (pending.llm_call_1_response as { narration?: string } | null)?.narration ?? "";
  const messages: Array<{ role: "user" | "assistant"; content: string }> = [
    ...(callOneNarration ? [{ role: "assistant" as const, content: callOneNarration }] : []),
    { role: "user", content: `Resolve the roll above and continue the scene.` },
  ];

  let llm;
  try {
    llm = await callStructured<ResolveRollOutput>({
      model: ENV.OPENAI_MODEL(),
      systemPrompt,
      messages,
      maxTokens,
      jsonSchema: { name: "ResolveRoll", schema: RESOLVE_ROLL_JSON_SCHEMA, strict: true },
      temperature: 0.7,
    });
  } catch (err) {
    log.error("llm_call_failed", { err: (err as Error).message });
    return errorResponse(502, "llm_call_failed", (err as Error).message);
  }

  let dm: ResolveRollOutput;
  try {
    dm = ResolveRollOutputSchema.parse(llm.parsed);
  } catch (err) {
    log.error("llm_output_invalid", { err: (err as Error).message });
    return errorResponse(502, "llm_output_invalid", (err as Error).message);
  }

  // ------------------------------ Apply state_changes ------------------------------
  const apply = await applyStateChanges(sb, campaign.id, dm.state_changes, log);

  // Phase decision (post state-changes).
  const { data: freshBossRows } = await sb
    .from("campaign_bosses")
    .select("status, template_bosses(tier)")
    .eq("campaign_id", campaign.id);
  const freshBosses = (freshBossRows ?? []).map((r: Record<string, unknown>) => ({
    tier: ((r.template_bosses as { tier?: string } | null)?.tier ?? "small") as "small" | "medium" | "big",
    status: r.status as "unencountered" | "encountered" | "defeated",
  }));

  const phaseDecision = decideNextPhase({
    current: ctx.campaign.phase,
    llmSuggestAdvance: dm.story_progress.suggest_phase_advance,
    turnsInCurrentPhase: ctx.campaign.turns_in_current_phase,
    bosses: freshBosses,
  });

  const significantProgress = phaseDecision.changed
    || apply.applied.some((c) => c.type === "boss_status_change" || c.type === "combat_start");

  await sb.from("campaigns").update({
    phase: phaseDecision.changed ? phaseDecision.next : ctx.campaign.phase,
    turns_in_current_phase: phaseDecision.changed ? 0 : ctx.campaign.turns_in_current_phase + 1,
    turns_since_last_progress: significantProgress ? 0 : ctx.campaign.turns_since_last_progress + 1,
    total_turns: ctx.campaign.total_turns + 1,
    last_played_at: new Date().toISOString(),
  }).eq("id", campaign.id);

  let campaignStatus: "active" | "completed" | "failed" = "active";
  if (apply.characterDied) {
    campaignStatus = "failed";
    await sb.from("campaigns").update({ status: "failed" }).eq("id", campaign.id);
  }

  // Persist DM message for the outcome narration.
  const { data: dmMsgRow, error: dmMsgErr } = await sb
    .from("messages")
    .insert({
      campaign_id: campaign.id,
      role: "dm",
      content: dm.narration,
      situation_type: situation,
      options: dm.options,
      was_cheap_resolve: false,
      requires_roll: null,
      state_changes_applied: apply.applied,
      prompt_tokens: llm.promptTokens,
      completion_tokens: llm.completionTokens,
      pivotal_moment: dm.pivotal_moment,
    })
    .select("id")
    .single();
  if (dmMsgErr || !dmMsgRow) {
    return errorResponse(500, "dm_message_persist_failed", dmMsgErr?.message ?? "");
  }

  // Mark pending_roll resolved.
  await sb.from("pending_rolls").update({ resolved_at: new Date().toISOString() }).eq("id", body.pending_roll_id);

  log.info("resolved", {
    latency_ms: Date.now() - startedAt,
    outcome: roll.outcome,
    state_changes_applied: apply.applied.length,
    state_changes_rejected: apply.rejected.length,
    phase_changed: phaseDecision.changed,
  });

  return jsonResponse({
    kind: "resolved_roll",
    roll: {
      dice, raw: roll.raw, modifier, total: roll.total, dc, outcome: roll.outcome,
      modifier_stat: modifierStat,
    },
    narration: dm.narration,
    options: dm.options,
    pivotal_moment: dm.pivotal_moment,
    state_changes_applied: apply.applied,
    state_changes_rejected: apply.rejected,
    new_phase: phaseDecision.changed ? phaseDecision.next : null,
    leveled_up_to: apply.leveledUpTo,
    character_died: apply.characterDied,
    campaign_status: campaignStatus,
    message_id: dmMsgRow.id,
  });
});
