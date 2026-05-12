// =====================================================================
// Profile / avatar mini-loader for the story engine (Phase 2).
// =====================================================================
// Smaller and faster than `context.ts:loadCampaignContext` — pulls only
// the fields the AI roles (A, B, C, D) need:
//   • The user's per-role toggles  (profiles.ai_role_*_enabled)
//   • The avatar's narrative flavor (display_name + backstory + tags)
//
// Centralized here so renderNodePayload doesn't grow into the same
// monolith dm-turn became.
// =====================================================================

import type { SupabaseClient } from "./deps.ts";

export interface AiRoleToggles {
  reskinner: boolean;     // Role A
  intentMapper: boolean;  // Role B
  npcVoice: boolean;      // Role C
  rollNarrator: boolean;  // Role D
}

export interface AvatarFlavor {
  display_name: string;
  backstory: string;            // empty string if avatar has none yet
  personality_tags: string[];   // e.g. ["stoic","weary","loyal"]
}

export interface ProfileContext {
  user_id: string;
  toggles: AiRoleToggles;
  avatar: AvatarFlavor | null;  // null when the campaign's character has
                                // no avatar (legacy seeds may lack one)
}

const DEFAULT_TOGGLES: AiRoleToggles = {
  reskinner: false,
  intentMapper: false,
  npcVoice: false,
  rollNarrator: false,
};

/**
 * Resolve the profile + avatar context for a campaign in a single
 * round-trip pair. Defaults are conservative: every toggle reads as
 * `false` when the row is missing (e.g. profile not yet created), so
 * AI roles never accidentally fire for users who haven't opted in.
 */
export async function loadProfileContext(
  sb: SupabaseClient,
  campaignId: string,
): Promise<ProfileContext> {
  // Resolve user_id + character_id off the campaign row.
  const { data: cmp, error: cErr } = await sb
    .from("campaigns")
    .select("user_id, character_id")
    .eq("id", campaignId)
    .single();
  if (cErr || !cmp) {
    throw new Error(`loadProfileContext: campaign not found (${cErr?.message})`);
  }

  // Run profile + character fetches in parallel.
  const [profRes, charRes] = await Promise.all([
    sb.from("profiles")
      .select(
        "ai_role_reskinner_enabled, ai_role_intent_mapper_enabled, ai_role_npc_voice_enabled, ai_role_roll_narrator_enabled",
      )
      .eq("id", cmp.user_id)
      .maybeSingle(),
    sb.from("characters")
      .select("avatar_id")
      .eq("id", cmp.character_id)
      .maybeSingle(),
  ]);

  const toggles: AiRoleToggles = profRes.data
    ? {
        reskinner: !!(profRes.data as Record<string, unknown>).ai_role_reskinner_enabled,
        intentMapper: !!(profRes.data as Record<string, unknown>).ai_role_intent_mapper_enabled,
        npcVoice: !!(profRes.data as Record<string, unknown>).ai_role_npc_voice_enabled,
        rollNarrator: !!(profRes.data as Record<string, unknown>).ai_role_roll_narrator_enabled,
      }
    : { ...DEFAULT_TOGGLES };

  const avatarId = (charRes.data as { avatar_id?: string } | null)?.avatar_id ?? null;

  let avatar: AvatarFlavor | null = null;
  if (avatarId) {
    const { data: av } = await sb
      .from("avatar_templates")
      .select("display_name, backstory, personality_tags")
      .eq("id", avatarId)
      .maybeSingle();
    if (av) {
      const a = av as {
        display_name?: string;
        backstory?: string | null;
        personality_tags?: unknown;
      };
      avatar = {
        display_name: a.display_name ?? "",
        backstory: a.backstory ?? "",
        personality_tags: Array.isArray(a.personality_tags)
          ? (a.personality_tags as unknown[]).map((t) => String(t))
          : [],
      };
    }
  }

  return {
    user_id: cmp.user_id as string,
    toggles,
    avatar,
  };
}
