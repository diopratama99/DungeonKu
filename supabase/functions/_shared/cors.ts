// CORS for browser-hosted Flutter web. For native iOS/Android the headers are harmless.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function handlePreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return null;
}

export function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

export function errorResponse(status: number, code: string, message: string, extra: Record<string, unknown> = {}): Response {
  return jsonResponse({ error: { code, message, ...extra } }, { status });
}
