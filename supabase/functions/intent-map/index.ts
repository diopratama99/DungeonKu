// =====================================================================
// intent-map — Phase 3 endpoint, Role B
// =====================================================================
// Accepts a free-text player action and returns either:
//   • { option_id, reason, remaining }   — successfully mapped
//   • { option_id: null, reason, remaining } — couldn't map; client
//     should keep showing the scripted options
//
// The client then calls /player-action with the returned option_id to
// actually transition. We deliberately don't transition here so the
// player still sees an explicit "you chose X" beat in the UI.
//
// Rate limit: 5 mapped (or attempted) calls per campaign session,
// stored in campaign_node_state.flags.intent_map_count. Re-bootstrapping
// resets the counter on a fresh campaign because the flags map starts
// empty.
//
// Request:
//   { campaign_id: string, free_text: string }
//
// Response (200):
//   {
//     option_id: string | null,
//     reason: string,
//     remaining: number          // calls left this session, after this one
//   }
//
// Errors:
//   401 unauthorized
//   404 campaign_not_found
//   409 legacy_campaign
//   409 campaign_not_active
//   409 intent_map_disabled       — user has the toggle off
//   429 rate_limit_exceeded       — 5/5 used this campaign
//   500 engine_error
// =====================================================================

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import { loadProfileContext } from "../_shared/profile_context.ts";
import { mapIntent } from "../_shared/intent_mapper.ts";
import {
  loadNodeState,
  loadNode,
  loadOutgoingEdges,
  loadGatingContext,
  checkRequires,
} from "../_shared/story_engine.ts";

const RequestSchema = z.object({
  campaign_id: z.string().uuid(),
  free_text: z.string().min(1).max(400),
});

const MAX_PER_SESSION = 5;

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  const log = newLogger("intent-map");

  if (req.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Use POST");
  }

  const user = await getAuthenticatedUser(req);
  if (!user) {
    return errorResponse(401, "unauthorized", "Missing or invalid Bearer token");
  }

  let body: z.infer<typeof RequestSchema>;
  try {
    body = RequestSchema.parse(await req.json());
  } catch (err) {
    return errorResponse(400, "bad_body", (err as Error).message);
  }

  const sb = getServiceClient();

  // Verify ownership + status + non-legacy
  const { data: cmp } = await sb
    .from("campaigns")
    .select("user_id, status, is_legacy")
    .eq("id", body.campaign_id)
    .maybeSingle();
  if (!cmp || cmp.user_id !== user.id) {
    return errorResponse(404, "campaign_not_found", "Campaign not found");
  }
  if (cmp.is_legacy === true) {
    return errorResponse(409, "legacy_campaign",
      "Free-text intent mapping is only available on graph campaigns.");
  }
  if (cmp.status !== "active") {
    return errorResponse(409, "campaign_not_active", `Campaign is ${cmp.status}`);
  }

  // Verify the user has Role B enabled — we don't want to silently
  // burn tokens for a user who didn't opt in.
  const profile = await loadProfileContext(sb, body.campaign_id);
  if (!profile.toggles.intentMapper) {
    return errorResponse(409, "intent_map_disabled",
      "Intent mapper is disabled in your AI roles settings.");
  }

  // Load current node + filtered options.
  const state = await loadNodeState(sb, body.campaign_id);
  if (!state || !state.current_node_id) {
    return errorResponse(409, "no_current_node",
      "Campaign has no current node — call /story-turn first.");
  }

  // Rate limit check — pre-increment so even failed maps count
  // (prevents abuse via crafted-to-fail prompts).
  const flags = (state.flags ?? {}) as Record<string, unknown>;
  const used = Number(flags.intent_map_count ?? 0);
  if (used >= MAX_PER_SESSION) {
    return errorResponse(429, "rate_limit_exceeded",
      `Free-text limit reached for this campaign (${used}/${MAX_PER_SESSION}).`);
  }

  const node = await loadNode(sb, state.current_node_id);
  if (!node) {
    return errorResponse(500, "node_missing",
      `Current node ${state.current_node_id} no longer exists.`);
  }

  // Filter to only the options the player can actually take right now.
  // The mapper must not pick a locked edge.
  const ctx = await loadGatingContext(sb, body.campaign_id);
  const edges = await loadOutgoingEdges(sb, state.current_node_id);
  const open = edges
    .filter((e) => checkRequires(e.requires, ctx))
    .map((e) => ({ id: e.option_id, label: e.option_label }));

  if (open.length === 0) {
    return jsonResponse({
      option_id: null,
      reason: "Nothing you can do here right now.",
      remaining: MAX_PER_SESSION - used,
    });
  }

  // Build a one-line scene summary for the prompt context.
  const sceneSummary = (node.body ?? "").trim().slice(0, 240);

  let mapped;
  try {
    mapped = await mapIntent({
      free_text: body.free_text,
      scene_summary: sceneSummary,
      options: open,
    });
  } catch (err) {
    log.error("mapIntent_threw", { err: (err as Error).message });
    return errorResponse(500, "engine_error", (err as Error).message);
  }

  // Increment the counter regardless of mapping success — a player
  // burning the budget on garbage prompts is on them.
  const newCount = used + 1;
  await sb.from("campaign_node_state")
    .update({
      flags: { ...flags, intent_map_count: newCount },
      updated_at: new Date().toISOString(),
    })
    .eq("campaign_id", body.campaign_id);

  log.info("mapped", {
    campaign_id: body.campaign_id,
    node_id: state.current_node_id,
    open_options: open.length,
    matched: mapped.option_id !== null,
    used: newCount,
  });

  return jsonResponse({
    option_id: mapped.option_id,
    reason: mapped.reason,
    remaining: MAX_PER_SESSION - newCount,
  });
});
