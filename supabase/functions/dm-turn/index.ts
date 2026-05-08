// dm-turn — main per-turn pipeline.
//
// Flow:
//   1. Auth + body validation
//   2. Load campaign context (template, character, recent messages, bosses, side missions, ...)
//   3. Persist player message
//   4. Classify situation type → adaptive max_tokens
//   5. Decide whether to inject the URGENT PACING block (anti-stall)
//   6. Build system prompt + chat history
//   7. Call gpt-4o with strict JSON schema (structured outputs)
//   8. Re-validate output with zod
//   9. Branch:
//      - requires_roll set: clamp DC, persist pending_rolls + DM message, return roll request
//      - else: apply state_changes, match side quest intent, validate phase advance,
//              update campaign counters, persist DM message
//  10. Periodic summarisation kick-off if total_turns % 12 === 0
//
// The entire dance is one HTTP request from Flutter's perspective. We never wait on the
// summariser (fire-and-forget).

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import {
  DmTurnOutputSchema,
  DmTurnRequestSchema,
  DM_TURN_JSON_SCHEMA,
} from "../_shared/schemas.ts";
import type { DmTurnOutput } from "../_shared/schemas.ts";
import { loadCampaignContext } from "../_shared/context.ts";
import { classify, maxTokensFor, TEMPLATE_COMMON_ACTIONS } from "../_shared/classifier.ts";
import type { SituationType } from "../_shared/classifier.ts";
import { buildSystemPrompt, recentMessagesToChatHistory } from "../_shared/prompts.ts";
import { decideNextPhase } from "../_shared/phase_rules.ts";
import { DIFFICULTY, clampDC } from "../_shared/difficulty.ts";
import { callStructured } from "../_shared/openai.ts";
import { applyStateChanges, tryStartSideMissionFromIntent } from "../_shared/state_changes.ts";
import { ENV } from "../_shared/env.ts";

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  const log = newLogger("dm-turn");
  const startedAt = Date.now();

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Use POST");
  }

  // ------------------------------ Auth + body ------------------------------
  const user = await getAuthenticatedUser(req);
  if (!user) {
    log.warn("auth_failed");
    return errorResponse(401, "unauthorized", "Missing or invalid Bearer token");
  }

  let body: z.infer<typeof DmTurnRequestSchema>;
  try {
    body = DmTurnRequestSchema.parse(await req.json());
  } catch (err) {
    log.warn("bad_body", { err: (err as Error).message });
    return errorResponse(400, "bad_body", (err as Error).message);
  }

  const sb = getServiceClient();

  // Verify ownership.
  const { data: campaignOwnerRow } = await sb
    .from("campaigns")
    .select("user_id, status")
    .eq("id", body.campaign_id)
    .maybeSingle();
  if (!campaignOwnerRow || campaignOwnerRow.user_id !== user.id) {
    log.warn("campaign_not_owned", { campaign_id: body.campaign_id, user_id: user.id });
    return errorResponse(404, "campaign_not_found", "Campaign not found");
  }
  if (campaignOwnerRow.status !== "active") {
    return errorResponse(409, "campaign_not_active", `Campaign is ${campaignOwnerRow.status}`);
  }

  // ------------------------------ Context ------------------------------
  const ctx = await loadCampaignContext(sb, body.campaign_id);
  log.info("context_loaded", {
    campaign_id: body.campaign_id,
    phase: ctx.campaign.phase,
    total_turns: ctx.campaign.total_turns,
    bosses_defeated: ctx.bosses.filter((b) => b.status === "defeated").length,
    bosses_total: ctx.bosses.length,
  });

  // Persist player message immediately. Even if the LLM call fails, we want a record.
  const { data: playerMsgRow, error: playerMsgErr } = await sb
    .from("messages")
    .insert({
      campaign_id: body.campaign_id,
      role: "player",
      content: body.player_message,
      selected_option_id: body.selected_option_id ?? null,
      was_cheap_resolve: false,
    })
    .select("id")
    .single();
  if (playerMsgErr || !playerMsgRow) {
    log.error("player_msg_insert_failed", { err: playerMsgErr?.message });
    return errorResponse(500, "player_message_persist_failed", playerMsgErr?.message ?? "");
  }

  // ------------------------------ Classify + budget ------------------------------
  const lastMsg = ctx.recentMessages[ctx.recentMessages.length - 1];
  const recentTransition = lastMsg ? false : false; // initial baseline; refined below
  const phaseChangedRecently = ctx.campaign.turns_in_current_phase <= 1;
  const lastDmMsg = [...ctx.recentMessages].reverse().find((m) => m.role === "dm");
  const recentDiceRoll = lastDmMsg ? lastDmMsg.requires_roll != null : false;
  const inCombat = ctx.activeCombat !== null;

  const situation: SituationType = classify(body.player_message, {
    recentTransition: recentTransition || phaseChangedRecently,
    recentDiceRoll,
    inCombat,
  });
  const maxTokens = maxTokensFor(situation);

  // Anti-stall: inject URGENT PACING if we've gone too long without progress.
  const injectAntiStall = ctx.campaign.turns_since_last_progress >= DIFFICULTY.antiStallThresholdTurns;

  // ------------------------------ Prompt + LLM call ------------------------------
  const systemPrompt = buildSystemPrompt({
    ctx,
    situation,
    injectAntiStall,
  });

  const chatHistory = recentMessagesToChatHistory(ctx.recentMessages);
  // Tag the player's current message at the end of chat history.
  chatHistory.push({ role: "user", content: body.player_message });

  log.info("calling_llm", { situation, max_tokens: maxTokens, anti_stall: injectAntiStall, history_len: chatHistory.length });

  let llm: Awaited<ReturnType<typeof callStructured<DmTurnOutput>>>;
  try {
    llm = await callStructured<DmTurnOutput>({
      model: ENV.OPENAI_MODEL(),
      systemPrompt,
      messages: chatHistory,
      maxTokens: situation === "transition" || ctx.campaign.turns_since_last_progress >= DIFFICULTY.antiStallThresholdTurns
        ? DIFFICULTY.maxTokensBySituation.transition
        : maxTokens,
      jsonSchema: { name: "DmTurn", schema: DM_TURN_JSON_SCHEMA, strict: true },
      temperature: 0.7,
    });
  } catch (err) {
    log.error("llm_call_failed", { err: (err as Error).message });
    return errorResponse(502, "llm_call_failed", (err as Error).message);
  }

  // Re-validate even though structured outputs should guarantee shape.
  let dm: DmTurnOutput;
  try {
    dm = DmTurnOutputSchema.parse(llm.parsed);
  } catch (err) {
    log.error("llm_output_invalid", { err: (err as Error).message, raw: llm.rawText.slice(0, 500) });
    return errorResponse(502, "llm_output_invalid", (err as Error).message);
  }

  log.info("llm_call_ok", {
    prompt_tokens: llm.promptTokens,
    completion_tokens: llm.completionTokens,
    pivotal: dm.pivotal_moment,
    requires_roll: dm.requires_roll != null,
    state_changes: dm.state_changes.length,
    options: dm.options.length,
  });

  // ------------------------------ Branch: requires_roll ------------------------------
  if (dm.requires_roll) {
    const clampedDC = clampDC(dm.requires_roll.dc);
    if (clampedDC !== dm.requires_roll.dc) {
      log.info("dc_clamped", { from: dm.requires_roll.dc, to: clampedDC });
      dm.requires_roll = { ...dm.requires_roll, dc: clampedDC };
    }

    // Build options preview (we still send options so the UI knows the *intent*, even
    // though the dice overlay locks input until resolved).
    const finalOptions = mergeOptions(dm, situation);

    // Persist DM message. State_changes are NOT applied yet — they happen in resolve-roll
    // after the player taps the dice (the outcome may invalidate them).
    const { data: dmMsgRow, error: dmMsgErr } = await sb
      .from("messages")
      .insert({
        campaign_id: body.campaign_id,
        role: "dm",
        content: dm.narration,
        situation_type: situation,
        options: finalOptions,
        was_cheap_resolve: false,
        requires_roll: dm.requires_roll,
        state_changes_applied: [],
        prompt_tokens: llm.promptTokens,
        completion_tokens: llm.completionTokens,
        pivotal_moment: dm.pivotal_moment,
      })
      .select("id")
      .single();
    if (dmMsgErr || !dmMsgRow) {
      log.error("dm_msg_insert_failed", { err: dmMsgErr?.message });
      return errorResponse(500, "dm_message_persist_failed", dmMsgErr?.message ?? "");
    }

    // Persist pending_roll with the LLM's full response so resolve-roll can re-use
    // state_changes after we know if the roll succeeded.
    const { data: pendingRow, error: pendingErr } = await sb
      .from("pending_rolls")
      .insert({
        campaign_id: body.campaign_id,
        message_id: dmMsgRow.id,
        dice: dm.requires_roll.dice,
        purpose: dm.requires_roll.purpose,
        dc: dm.requires_roll.dc,
        modifier_stat: dm.requires_roll.modifier_stat,
        llm_call_1_response: dm,
      })
      .select("id")
      .single();
    if (pendingErr || !pendingRow) {
      log.error("pending_roll_insert_failed", { err: pendingErr?.message });
      return errorResponse(500, "pending_roll_persist_failed", pendingErr?.message ?? "");
    }

    // Bump campaign turn counters even on roll-pending turns; the player did make a move.
    await bumpTurnCounters(sb, body.campaign_id, ctx, /*progress*/ false);

    log.info("turn_completed_with_roll", {
      pending_roll_id: pendingRow.id,
      latency_ms: Date.now() - startedAt,
    });

    return jsonResponse({
      kind: "requires_roll",
      narration: dm.narration,
      situation_type: situation,
      options: finalOptions,
      pivotal_moment: dm.pivotal_moment,
      requires_roll: dm.requires_roll,
      pending_roll_id: pendingRow.id,
      message_id: dmMsgRow.id,
    });
  }

  // ------------------------------ Apply state_changes ------------------------------
  const apply = await applyStateChanges(sb, body.campaign_id, dm.state_changes, log);

  // Side quest intent: see if the LLM detected one and we can start it.
  let startedSideMission: { id: string; title: string } | null = null;
  if (dm.side_quest_intent && dm.side_quest_intent.trigger) {
    const r = await tryStartSideMissionFromIntent(
      sb,
      body.campaign_id,
      dm.side_quest_intent.trigger,
      ctx.campaign.phase,
      log,
    );
    if (r.started && r.mission) startedSideMission = r.mission;
  }

  // Phase decision (server-side hard rules).
  // Re-read bosses to get the post-state-change picture.
  const { data: freshBossRows } = await sb
    .from("campaign_bosses")
    .select("status, template_bosses(tier)")
    .eq("campaign_id", body.campaign_id);
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
  if (phaseDecision.llmDisagreement) {
    log.info("phase_disagreement", {
      current: ctx.campaign.phase,
      llm_suggested: dm.story_progress.suggest_phase_advance,
      llm_reason: dm.story_progress.reason,
      server_reason: phaseDecision.reason,
    });
  }

  const significantProgress = phaseDecision.changed
    || apply.applied.some((c) => c.type === "boss_status_change" || c.type === "combat_start")
    || startedSideMission !== null;

  // Bump turn counters AFTER deciding phase so the new turns_in_current_phase resets
  // correctly when phase advances.
  await bumpTurnCounters(
    sb,
    body.campaign_id,
    ctx,
    significantProgress,
    phaseDecision.changed ? phaseDecision.next : null,
  );

  // Auto-mark the campaign completed after a couple of resolution turns.
  let campaignStatus: "active" | "completed" | "failed" = "active";
  if (apply.characterDied) {
    campaignStatus = "failed";
    await sb.from("campaigns").update({ status: "failed" }).eq("id", body.campaign_id);
  } else if (
    (phaseDecision.changed && phaseDecision.next === "resolution")
    || (ctx.campaign.phase === "resolution" && ctx.campaign.turns_in_current_phase >= 1)
  ) {
    if (ctx.campaign.phase === "resolution" && ctx.campaign.turns_in_current_phase >= 1) {
      campaignStatus = "completed";
      await sb.from("campaigns").update({ status: "completed" }).eq("id", body.campaign_id);
    }
  }

  // Final options.
  const finalOptions = mergeOptions(dm, situation);

  // Persist DM message.
  const { data: dmMsgRow, error: dmMsgErr } = await sb
    .from("messages")
    .insert({
      campaign_id: body.campaign_id,
      role: "dm",
      content: dm.narration,
      situation_type: situation,
      options: finalOptions,
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
    log.error("dm_msg_insert_failed", { err: dmMsgErr?.message });
    return errorResponse(500, "dm_message_persist_failed", dmMsgErr?.message ?? "");
  }

  // Fire-and-forget summariser if we crossed the threshold. Do not await.
  const newTotalTurns = ctx.campaign.total_turns + 1;
  if (newTotalTurns % DIFFICULTY.summarizeEvery === 0) {
    triggerSummarise(body.campaign_id).catch((err) =>
      log.warn("summarise_kick_failed", { err: (err as Error).message })
    );
  }

  log.info("turn_completed", {
    latency_ms: Date.now() - startedAt,
    phase_changed: phaseDecision.changed,
    new_phase: phaseDecision.next,
    state_changes_applied: apply.applied.length,
    state_changes_rejected: apply.rejected.length,
    leveled_up_to: apply.leveledUpTo,
    character_died: apply.characterDied,
    side_mission_started: startedSideMission?.id ?? null,
    campaign_status: campaignStatus,
  });

  return jsonResponse({
    kind: "narration",
    narration: dm.narration,
    situation_type: situation,
    options: finalOptions,
    pivotal_moment: dm.pivotal_moment,
    requires_roll: null,
    state_changes_applied: apply.applied,
    state_changes_rejected: apply.rejected,
    new_phase: phaseDecision.changed ? phaseDecision.next : null,
    side_mission_started: startedSideMission,
    leveled_up_to: apply.leveledUpTo,
    character_died: apply.characterDied,
    campaign_status: campaignStatus,
    message_id: dmMsgRow.id,
  });
});

// ----------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------

/**
 * Merge LLM-provided situational/pivotal options with template_common ones from the
 * classifier table. Cap at 5 if pivotal, otherwise 3. Each entry gets a stable id and an
 * icon string. Pivotal moments get only LLM options (no template_common mixed in).
 */
function mergeOptions(dm: DmTurnOutput, situation: SituationType): DmTurnOutput["options"] {
  const llmOptions = dm.options.slice();
  if (dm.pivotal_moment) {
    return llmOptions.slice(0, 5).map((o: DmTurnOutput["options"][number], i: number) => ({ ...o, id: o.id || `pivotal_${i}`, kind: "pivotal" as const }));
  }
  const cap = 3;
  if (llmOptions.length >= cap) {
    return llmOptions.slice(0, cap);
  }
  // Fill with template_common. Shuffle the pool so when the LLM consistently
  // under-delivers, the player isn't stuck staring at the SAME three generic
  // actions every turn. The pool itself is small (4 entries per situation),
  // so shuffling rotates the visible trio nicely.
  const need = cap - llmOptions.length;
  const pool = TEMPLATE_COMMON_ACTIONS[situation].slice();
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  const fillers = pool
    .slice(0, need)
    .map((a) => ({ id: a.id, label: a.label, kind: "template_common" as const, icon: a.icon }));
  return [...llmOptions, ...fillers].slice(0, cap);
}

/**
 * Update campaigns.* counters. If phase changed, reset turns_in_current_phase to 0.
 * If significant progress occurred, reset turns_since_last_progress to 0; else increment.
 */
async function bumpTurnCounters(
  sb: ReturnType<typeof getServiceClient>,
  campaignId: string,
  ctx: Awaited<ReturnType<typeof loadCampaignContext>>,
  significantProgress: boolean,
  newPhase: string | null = null,
): Promise<void> {
  await sb.from("campaigns").update({
    phase: newPhase ?? ctx.campaign.phase,
    turns_in_current_phase: newPhase ? 0 : ctx.campaign.turns_in_current_phase + 1,
    turns_since_last_progress: significantProgress ? 0 : ctx.campaign.turns_since_last_progress + 1,
    total_turns: ctx.campaign.total_turns + 1,
    last_played_at: new Date().toISOString(),
  }).eq("id", campaignId);
}

/**
 * Fire-and-forget call to summarize-campaign. Uses fetch instead of supabase-js.functions.invoke
 * so we don't pay for the round-trip on the user's request.
 */
async function triggerSummarise(campaignId: string): Promise<void> {
  const url = `${ENV.SUPABASE_URL()}/functions/v1/summarize-campaign`;
  await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "authorization": `Bearer ${ENV.SUPABASE_SERVICE_ROLE_KEY()}`,
    },
    body: JSON.stringify({ campaign_id: campaignId }),
  }).catch(() => { /* swallow */ });
}
