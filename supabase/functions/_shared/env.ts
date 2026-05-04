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
  OPENAI_MODEL: () => optional("OPENAI_MODEL", "gpt-4o"),
  OPENAI_MODEL_SUMMARY: () => optional("OPENAI_MODEL_SUMMARY", "gpt-4o-mini"),
};
