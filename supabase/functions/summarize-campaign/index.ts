// summarize-campaign — periodic compression of older messages into world_memory.summary.
//
// Triggered fire-and-forget by dm-turn every DIFFICULTY.summarizeEvery turns. Uses
// gpt-4o-mini (cheaper). The summary preserves: NPCs met, locations visited, items
// gained/lost, bosses encountered, unresolved threads.

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import { getServiceClient } from "../_shared/supabase.ts";
import { SummarizeRequestSchema } from "../_shared/schemas.ts";
import { callPlain } from "../_shared/openai.ts";
import { ENV } from "../_shared/env.ts";
import { DIFFICULTY } from "../_shared/difficulty.ts";

const SYSTEM_PROMPT = `You are a campaign archivist. You compress past play into a brief, factual world memory that the Dungeon Master will re-read each turn. Preserve:
- Key NPCs met and what they wanted
- Locations visited
- Items gained or lost
- Bosses encountered or defeated
- Unresolved threads or promises the player made

Write 4-8 dense bullet points. No flavor prose, no chapter summaries — just facts. Past tense. Third person.`;

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse(405, "method_not_allowed", "Use POST");

  const log = newLogger("summarize-campaign");

  // This function is invoked from dm-turn with the service-role key (server-to-server).
  // We don't run user auth here — but we DO require a service-role bearer to avoid
  // anonymous callers spamming summary work.
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.includes(ENV.SUPABASE_SERVICE_ROLE_KEY())) {
    return errorResponse(401, "unauthorized", "Service-role authorization required");
  }

  let body: z.infer<typeof SummarizeRequestSchema>;
  try {
    body = SummarizeRequestSchema.parse(await req.json());
  } catch (err) {
    return errorResponse(400, "bad_body", (err as Error).message);
  }

  const sb = getServiceClient();

  // Pull all messages older than the last `recentMessageWindow` turns. We summarise
  // everything before that window so the dm-turn function only loads the most recent N
  // messages plus the rolling summary.
  const { data: allMessages } = await sb
    .from("messages")
    .select("role, content, created_at")
    .eq("campaign_id", body.campaign_id)
    .order("created_at", { ascending: true });

  if (!allMessages || allMessages.length <= DIFFICULTY.recentMessageWindow) {
    log.info("nothing_to_summarise", { messages: allMessages?.length ?? 0 });
    return jsonResponse({ kind: "noop", reason: "not enough messages" });
  }

  const olderMessages = allMessages.slice(0, allMessages.length - DIFFICULTY.recentMessageWindow);
  const transcript = olderMessages
    .map((m: { role: string; content: string }) => `${m.role.toUpperCase()}: ${m.content}`)
    .join("\n");

  // Read existing memory to fold into the new summary.
  const { data: existing } = await sb
    .from("world_memory")
    .select("summary, covers_message_count")
    .eq("campaign_id", body.campaign_id)
    .maybeSingle();

  const userPrompt = [
    existing?.summary ? `EXISTING SUMMARY (preserve and extend):\n${existing.summary}\n` : "",
    `TRANSCRIPT TO COMPRESS (older portion of the campaign):`,
    transcript,
    "",
    "Produce the updated world memory now.",
  ].join("\n");

  let summary = "";
  try {
    const llm = await callPlain({
      model: ENV.OPENAI_MODEL_SUMMARY(),
      systemPrompt: SYSTEM_PROMPT,
      userPrompt,
      maxTokens: 400,
      temperature: 0.3,
    });
    summary = llm.text.trim();
    log.info("summarised", {
      prompt_tokens: llm.promptTokens,
      completion_tokens: llm.completionTokens,
      covers: olderMessages.length,
    });
  } catch (err) {
    log.error("llm_call_failed", { err: (err as Error).message });
    return errorResponse(502, "llm_call_failed", (err as Error).message);
  }

  // Upsert into world_memory.
  await sb.from("world_memory")
    .upsert(
      {
        campaign_id: body.campaign_id,
        summary,
        covers_message_count: olderMessages.length,
      },
      { onConflict: "campaign_id" },
    );

  return jsonResponse({ kind: "ok", covers_message_count: olderMessages.length });
});
