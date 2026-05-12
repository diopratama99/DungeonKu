// =====================================================================
// player-action — take an option from the current story node
// =====================================================================
// Phase 1 endpoint. Validates the option_id is a real outgoing edge of
// the campaign's current node, re-checks gating server-side, applies
// the edge's `consumes` actions, transitions the cursor, then renders
// the new node (which itself fires on_enter_actions on first visit).
//
// Request:
//   {
//     campaign_id: string,
//     option_id:   string   // matches story_edges.option_id under the
//                           // current_node_id
//   }
//
// Response (200): same shape as story-turn.
//
// Errors:
//   401 unauthorized
//   404 campaign_not_found
//   409 legacy_campaign
//   409 campaign_not_active
//   400 bad_option         — option_id not a valid outgoing edge
//   403 requires_unmet     — gating failed (defence in depth)
//   500 engine_error
//
// Persists a row in `messages` (role='player', content=option_label) so
// the existing chat UI keeps a coherent log.
// =====================================================================

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import { takeOption, loadNodeState } from "../_shared/story_engine.ts";

const RequestSchema = z.object({
  campaign_id: z.string().uuid(),
  option_id:   z.string().min(1).max(80),
});

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  const log = newLogger("player-action");

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
      "This campaign uses the legacy DM endpoint. Use /dm-turn instead.");
  }
  if (cmp.status !== "active") {
    return errorResponse(409, "campaign_not_active", `Campaign is ${cmp.status}`);
  }

  // Look up the edge label for the message log BEFORE transitioning.
  // (Cursor moves inside takeOption; afterwards from_node_id wouldn't
  // resolve the same edge.)
  const state = await loadNodeState(sb, body.campaign_id);
  let optionLabel = body.option_id;
  if (state?.current_node_id) {
    const { data: edgeRow } = await sb
      .from("story_edges")
      .select("option_label")
      .eq("from_node_id", state.current_node_id)
      .eq("option_id", body.option_id)
      .maybeSingle();
    if (edgeRow?.option_label) optionLabel = edgeRow.option_label as string;
  }

  // Persist player turn into messages so the chat UI keeps a log.
  await sb.from("messages").insert({
    campaign_id: body.campaign_id,
    role: "player",
    content: optionLabel,
    selected_option_id: body.option_id,
  });

  try {
    const payload = await takeOption(sb, body.campaign_id, body.option_id);

    // Persist DM-side narration too, so the chat history shows it.
    await sb.from("messages").insert({
      campaign_id: body.campaign_id,
      role: "dm",
      content: payload.body,
    });

    // Bump campaign turn counter (still useful for analytics + summarizer).
    await sb.rpc("increment_campaign_turn", { p_campaign_id: body.campaign_id })
      .then(() => {})
      .catch(() => { /* RPC optional — ignore if not present */ });

    log.info("transitioned", {
      campaign_id: body.campaign_id,
      option_id: body.option_id,
      to_node: payload.node_id,
      first_visit: payload.was_first_visit,
      ended: !!payload.ended_campaign,
    });
    return jsonResponse(payload);
  } catch (err) {
    const msg = (err as Error).message;
    log.warn("take_option_failed", { err: msg, option_id: body.option_id });
    if (msg.includes("not valid")) {
      return errorResponse(400, "bad_option", msg);
    }
    if (msg.includes("requirements not met")) {
      return errorResponse(403, "requires_unmet", msg);
    }
    return errorResponse(500, "engine_error", msg);
  }
});
