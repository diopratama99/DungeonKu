// Environment variables. Always read through these helpers — never directly via Deno.env —
// so missing keys fail loudly at function start rather than mysteriously mid-request.

function required(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

function optional(name: string, fallback: string): string {
  return Deno.env.get(name) ?? fallback;
}

export const ENV = {
  // Provided automatically by the Supabase Functions runtime.
  SUPABASE_URL: () => required("SUPABASE_URL"),
  SUPABASE_ANON_KEY: () => required("SUPABASE_ANON_KEY"),
  SUPABASE_SERVICE_ROLE_KEY: () => required("SUPABASE_SERVICE_ROLE_KEY"),

  // App secrets.
  OPENAI_API_KEY: () => required("OPENAI_API_KEY"),
  OPENAI_BASE_URL: () => optional("OPENAI_BASE_URL", ""),
  // Support both naming conventions: OPENAI_CHAT_MODEL (your .env) and OPENAI_MODEL (legacy)
  OPENAI_MODEL: () =>
    Deno.env.get("OPENAI_CHAT_MODEL") ??
    Deno.env.get("OPENAI_MODEL") ??
    "gpt-4o",
  // For lighter tasks (intent mapping, narration, reskin). Falls back to chat model if not set.
  OPENAI_MODEL_SUMMARY: () =>
    Deno.env.get("OPENAI_MODEL_SUMMARY") ??
    Deno.env.get("OPENAI_CHAT_MODEL") ??
    Deno.env.get("OPENAI_MODEL") ??
    "gpt-4o-mini",
};
