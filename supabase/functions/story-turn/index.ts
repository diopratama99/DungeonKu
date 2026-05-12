// =====================================================================
// story-turn — render the campaign's current node + options.
// =====================================================================
// Phase 1 deterministic FSM endpoint. Replaces dm-turn for graph-enabled
// campaigns. Legacy campaigns (campaigns.is_legacy = true) continue to
// hit dm-turn.
//
// Request:
//   { campaign_id: string }
//
// Response (200):
//   {
//     node_id, node_type, body, speaker, tags,
//     options:[{id,label,locked,lock_reason?}],
//     on_enter_result, was_first_visit,
//     pending_combat_id, ended_campaign
//   }
//
// Errors:
//   401 unauthorized      — bad / missing token
//   404 campaign_not_found — caller does not own this campaign
//   409 legacy_campaign   — campaign is locked to legacy DM endpoint
//   409 campaign_not_active — campaign is completed/failed
//   500 engine_error      — anything else
// =====================================================================

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import { renderNodePayload } from "../_shared/story_engine.ts";

const RequestSchema = z.object({
  campaign_id: z.string().uuid(),
});

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;

  const log = newLogger("story-turn");

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

  try {
    const payload = await renderNodePayload(sb, body.campaign_id);
    log.info("rendered", {
      campaign_id: body.campaign_id,
      node_id: payload.node_id,
      node_type: payload.node_type,
      first_visit: payload.was_first_visit,
      options_offered: payload.options.length,
      pending_combat: !!payload.pending_combat_id,
      ended: !!payload.ended_campaign,
    });
    return jsonResponse(payload);
  } catch (err) {
    log.error("engine_error", { err: (err as Error).message });
    return errorResponse(500, "engine_error", (err as Error).message);
  }
});
