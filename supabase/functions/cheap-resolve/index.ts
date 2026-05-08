// cheap-resolve — handle a player tapping a template_common option without an LLM call.
//
// Triggered by the Flutter client when the user taps an option whose kind is
// "template_common" (and there's no active dice roll, no active combat). The server
// applies a deterministic outcome from a small rules table and returns a static-pool
// narration. Saves the LLM call entirely.
//
// Important: this function trusts the client to only call it for template_common options.
// We re-validate by checking that the option_id is in the canonical TEMPLATE_COMMON_ACTIONS
// table.

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import { CheapResolveRequestSchema } from "../_shared/schemas.ts";
import { TEMPLATE_COMMON_ACTIONS } from "../_shared/classifier.ts";
import { narrate } from "../_shared/narration_pools.ts";

// Map option_id → narration_pool key + (optional) state_changes to apply.
const RULES: Record<string, { situation: "exploration" | "dialog" | "combat"; narrationKey: Parameters<typeof narrate>[0]; defendBuff?: boolean; restBrief?: boolean }> = {
  // Exploration
  tc_look:    { situation: "exploration", narrationKey: "exploration_look_around" },
  tc_search:  { situation: "exploration", narrationKey: "exploration_search_clues" },
  tc_move:    { situation: "exploration", narrationKey: "exploration_move_on" },
  tc_rest:    { situation: "exploration", narrationKey: "exploration_rest_briefly", restBrief: true },

  // Dialog
  tc_ask:     { situation: "dialog", narrationKey: "dialog_ask_question" },
  tc_agree:   { situation: "dialog", narrationKey: "dialog_agree" },
  tc_refuse:  { situation: "dialog", narrationKey: "dialog_refuse" },

  // Combat: defending applies +2 AC for the next player turn (handled in combat-action;
  // for cheap-resolve outside combat we still narrate but don't apply the buff).
  tc_defend:  { situation: "combat", narrationKey: "combat_defend", defendBuff: true },
};

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse(405, "method_not_allowed", "Use POST");

  const log = newLogger("cheap-resolve");
  const user = await getAuthenticatedUser(req);
  if (!user) return errorResponse(401, "unauthorized", "Missing or invalid Bearer token");

  let body: z.infer<typeof CheapResolveRequestSchema>;
  try {
    body = CheapResolveRequestSchema.parse(await req.json());
  } catch (err) {
    return errorResponse(400, "bad_body", (err as Error).message);
  }

  const sb = getServiceClient();

  const { data: campaign } = await sb
    .from("campaigns")
    .select("id, user_id, status, phase, turns_in_current_phase, turns_since_last_progress, total_turns")
    .eq("id", body.campaign_id)
    .maybeSingle();
  if (!campaign || campaign.user_id !== user.id) {
    return errorResponse(404, "campaign_not_found", "Campaign not found");
  }
  if (campaign.status !== "active") {
    return errorResponse(409, "campaign_not_active", `Campaign is ${campaign.status}`);
  }

  // Validate option_id is a known template_common option.
  const knownIds = new Set<string>();
  for (const list of Object.values(TEMPLATE_COMMON_ACTIONS)) {
    for (const a of list) knownIds.add(a.id);
  }
  if (!knownIds.has(body.option_id)) {
    return errorResponse(400, "unknown_option", `option_id ${body.option_id} is not a template_common action`);
  }

  const rule = RULES[body.option_id];
  if (!rule) {
    return errorResponse(400, "no_rule", `no cheap-resolve rule for option ${body.option_id}`);
  }

  // Find the LABEL for this option to use as the player's message content.
  const optionLabel = Object.values(TEMPLATE_COMMON_ACTIONS)
    .flat()
    .find((a) => a.id === body.option_id)?.label ?? body.option_id;

  // Persist player message.
  const { data: playerMsg, error: pErr } = await sb.from("messages").insert({
    campaign_id: campaign.id,
    role: "player",
    content: optionLabel,
    selected_option_id: body.option_id,
    was_cheap_resolve: true,
  }).select("id").single();
  if (pErr || !playerMsg) {
    return errorResponse(500, "player_message_persist_failed", pErr?.message ?? "");
  }

  // Apply minimal state changes.
  const stateApplied: Array<Record<string, unknown>> = [];
  if (rule.restBrief) {
    // 50% restore, deterministic.
    const { data: cc } = await sb.from("campaign_characters")
      .select("id, hp, max_hp, resource_current, resource_max")
      .eq("campaign_id", campaign.id)
      .single();
    if (cc) {
      const hp = Math.min(cc.hp + Math.floor(cc.max_hp / 2), cc.max_hp);
      const rc = Math.min(cc.resource_current + Math.floor(cc.resource_max / 2), cc.resource_max);
      await sb.from("campaign_characters").update({ hp, resource_current: rc }).eq("id", cc.id);
      stateApplied.push({ type: "rest", sub_type: "brief_rest", safe: true });
    }
  }
  if (rule.defendBuff) {
    // Defending gives +2 AC for the duration of the next player turn. We persist this as
    // a status_effect; combat-action reads it when computing AC.
    const { data: cc } = await sb.from("campaign_characters")
      .select("id, status_effects")
      .eq("campaign_id", campaign.id)
      .single();
    if (cc) {
      const cur = (cc.status_effects as Array<{ key: string }>) ?? [];
      const next = [
        ...cur.filter((s) => s.key !== "defending"),
        { key: "defending", label: "Defending", expires_in_turns: 1, magnitude: 2 },
      ];
      await sb.from("campaign_characters").update({ status_effects: next }).eq("id", cc.id);
      stateApplied.push({ type: "status_add", key: "defending", label: "Defending", duration: 1, magnitude: 2 });
    }
  }

  // Static narration.
  const narration = narrate(rule.narrationKey);

  // Build next-turn options from the template_common pool (shuffled so
  // the player doesn't see the exact same order every time).
  const pool = TEMPLATE_COMMON_ACTIONS[rule.situation].slice();
  for (let i = pool.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  const nextOptions = pool.slice(0, 3).map((a) => ({
    id: a.id,
    label: a.label,
    kind: "template_common" as const,
    icon: a.icon,
  }));

  // DM message.
  const { data: dmMsg, error: dErr } = await sb.from("messages").insert({
    campaign_id: campaign.id,
    role: "dm",
    content: narration,
    situation_type: rule.situation,
    options: nextOptions,
    was_cheap_resolve: true,
    state_changes_applied: stateApplied,
    prompt_tokens: 0,
    completion_tokens: 0,
  }).select("id").single();
  if (dErr || !dmMsg) {
    return errorResponse(500, "dm_message_persist_failed", dErr?.message ?? "");
  }

  // Bump turn counters. Cheap-resolves count as turns but rarely as significant progress.
  await sb.from("campaigns").update({
    turns_in_current_phase: campaign.turns_in_current_phase + 1,
    turns_since_last_progress: campaign.turns_since_last_progress + 1,
    total_turns: campaign.total_turns + 1,
    last_played_at: new Date().toISOString(),
  }).eq("id", campaign.id);

  log.info("cheap_resolved", { option_id: body.option_id, narration_key: rule.narrationKey });

  return jsonResponse({
    kind: "cheap_resolved",
    narration,
    situation_type: rule.situation,
    state_changes_applied: stateApplied,
    message_id: dmMsg.id,
  });
});
