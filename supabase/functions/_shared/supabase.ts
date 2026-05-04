// Two flavours of Supabase client:
//   1. Service-role client — bypasses RLS, used to mutate game state.
//   2. User client — scoped via the caller's JWT, used to verify auth + ownership.
//
// We deliberately do NOT mutate game state through the user client; that would re-enable
// RLS-based authorization mistakes. Instead, the user client is only used to resolve the
// authenticated user, then the service-role client takes over.

import { createClient } from "./deps.ts";
import type { SupabaseClient, User } from "./deps.ts";
import { ENV } from "./env.ts";

let cachedService: SupabaseClient | null = null;

export function getServiceClient(): SupabaseClient {
  if (cachedService) return cachedService;
  cachedService = createClient(ENV.SUPABASE_URL(), ENV.SUPABASE_SERVICE_ROLE_KEY(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cachedService;
}

export async function getAuthenticatedUser(req: Request): Promise<User | null> {
  const authHeader = req.headers.get("authorization");
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;

  const userClient = createClient(ENV.SUPABASE_URL(), ENV.SUPABASE_ANON_KEY(), {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data, error } = await userClient.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

/**
 * Confirm the user owns the given campaign. Done via the service client because we trust
 * `getAuthenticatedUser` to have already validated the JWT.
 */
export async function assertCampaignOwner(campaignId: string, userId: string): Promise<boolean> {
  const sb = getServiceClient();
  const { data, error } = await sb
    .from("campaigns")
    .select("id, user_id")
    .eq("id", campaignId)
    .maybeSingle();
  if (error || !data) return false;
  return data.user_id === userId;
}
