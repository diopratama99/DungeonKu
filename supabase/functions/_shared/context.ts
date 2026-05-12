// Per-turn context loader. Reads everything the dm-turn / resolve-roll / combat-action
// functions need from a single campaign in one batched query, so the round-trip cost is
// dominated by the LLM call, not by N queries to Postgres.

import type { SupabaseClient } from "./deps.ts";
import { DIFFICULTY } from "./difficulty.ts";
import type { Phase } from "./phase_rules.ts";

export interface CampaignContext {
  campaign: {
    id: string;
    user_id: string;
    character_id: string;
    template_id: string;
    name: string;
    status: "active" | "completed" | "failed";
    phase: Phase;
    turns_in_current_phase: number;
    turns_since_last_progress: number;
    total_turns: number;
  };
  template: {
    id: string;
    title: string;
    short_description: string;
    genre: string;
    world_setting: string;
    opening_scene: string;
    dm_guidance: string;
  };
  characterSheet: {
    id: string;
    name: string;
    class: string;
    base_element: string;
    avatar_id: string;
    level: number;
    xp: number;
    hp: number;
    max_hp: number;
    resource_type: "mp" | "stamina";
    resource_current: number;
    resource_max: number;
    ac: number;
    current_stats: Record<string, number>;
    status_effects: Array<{ key: string; label: string; expires_in_turns: number; magnitude: number }>;
  };
  inventory: Array<{ id: string; name: string; qty: number; element: string; item_type: string; description: string }>;
  skills: Array<{
    id: string;
    name: string;
    description: string;
    element: string;
    cost_type: "mp" | "stamina" | "free";
    cost_amount: number;
    dice: string | null;
    modifier_stat: string | null;
    is_basic_attack: boolean;
  }>;
  bosses: Array<{
    id: string;
    name: string;
    tier: "small" | "medium" | "big";
    status: "unencountered" | "encountered" | "defeated";
    template_boss_id: string;
  }>;
  sideMissions: Array<{
    id: string;
    template_side_mission_id: string;
    title: string;
    status: "active" | "completed" | "failed";
    current_step: number;
  }>;
  recentMessages: Array<{
    role: "player" | "dm" | "system";
    content: string;
    created_at: string;
    requires_roll: unknown;
  }>;
  worldMemory: string;
  activeCombat: {
    id: string;
    status: string;
    round_number: number;
    current_actor_index: number;
    turn_order: unknown;
  } | null;
  /**
   * Narrative flavor pulled from the chosen avatar_template. Used by the
   * DM prompt as voice cues + optional story hooks. Nullable for legacy
   * rows that pre-date migration 20260510 (no lore wired).
   */
  avatarFlavor: {
    display_name: string;
    backstory: string | null;
    personality_tags: string[];
    story_hooks: string[];
    signature_skill: { name: string; description: string } | null;
  } | null;
}

export async function loadCampaignContext(
  sb: SupabaseClient,
  campaignId: string,
): Promise<CampaignContext> {
  // Pull everything in parallel — these queries don't depend on each other.
  const [
    campaignRes,
    campaignCharRes,
    inventoryRes,
    campaignSkillsRes,
    bossesRes,
    sideMissionsRes,
    messagesRes,
    worldMemoryRes,
    combatRes,
  ] = await Promise.all([
    sb.from("campaigns").select("*").eq("id", campaignId).maybeSingle(),
    sb.from("campaign_characters").select("*, characters(name, class, avatar_id)").eq("campaign_id", campaignId).maybeSingle(),
    sb.from("campaign_inventory").select("*").eq("campaign_id", campaignId),
    sb.from("campaign_skills").select("skill_id").eq("campaign_id", campaignId),
    sb.from("campaign_bosses").select("*, template_bosses(name, tier, hp, base_damage, ac, element)").eq("campaign_id", campaignId),
    sb.from("campaign_side_missions").select("*, template_side_missions(title)").eq("campaign_id", campaignId),
    sb.from("messages")
      .select("role, content, created_at, requires_roll")
      .eq("campaign_id", campaignId)
      .order("created_at", { ascending: false })
      .limit(DIFFICULTY.recentMessageWindow),
    sb.from("world_memory").select("summary").eq("campaign_id", campaignId).maybeSingle(),
    sb.from("combat_encounters").select("*").eq("campaign_id", campaignId).eq("status", "active").maybeSingle(),
  ]);

  if (campaignRes.error || !campaignRes.data) {
    throw new Error(`Campaign not found: ${campaignRes.error?.message ?? "no row"}`);
  }
  if (campaignCharRes.error || !campaignCharRes.data) {
    throw new Error(`campaign_characters missing: ${campaignCharRes.error?.message ?? "no row"}`);
  }

  const campaign = campaignRes.data;
  const camChar = campaignCharRes.data;
  const avatarId = (camChar.characters as { avatar_id?: string } | null)?.avatar_id ?? null;

  // Fetch template + skills catalog + avatar flavor in parallel — they
  // all depend on already-loaded data but not on each other.
  const skillIds = (campaignSkillsRes.data ?? []).map((r: { skill_id: string }) => r.skill_id);
  const [templateRes, skillsRes, avatarRes] = await Promise.all([
    sb.from("story_templates").select("*").eq("id", campaign.template_id).maybeSingle(),
    skillIds.length === 0
      ? Promise.resolve({ data: [] as Array<Record<string, unknown>>, error: null })
      : sb.from("skills").select("*").in("id", skillIds),
    avatarId === null
      ? Promise.resolve({ data: null, error: null })
      : sb
          .from("avatar_templates")
          .select(
            "id, display_name, backstory, personality_tags, story_hooks, signature_skill_id, skills:signature_skill_id(name, description)",
          )
          .eq("id", avatarId)
          .maybeSingle(),
  ]);

  if (templateRes.error || !templateRes.data) {
    throw new Error(`story_template missing: ${templateRes.error?.message ?? "no row"}`);
  }

  const template = templateRes.data;

  // Reverse messages so they're in chronological order for the LLM.
  const recentMessages = [...(messagesRes.data ?? [])].reverse();

  // Shape avatar flavor (nullable cascade: row → fields → signature).
  const avatarRow = avatarRes.data as
    | {
        display_name?: string;
        backstory?: string | null;
        personality_tags?: unknown;
        story_hooks?: unknown;
        skills?: { name?: string; description?: string } | null;
      }
    | null;
  const avatarFlavor = avatarRow
    ? {
        display_name: avatarRow.display_name ?? "",
        backstory: avatarRow.backstory ?? null,
        personality_tags: Array.isArray(avatarRow.personality_tags)
          ? (avatarRow.personality_tags as unknown[]).map((t) => String(t))
          : [],
        story_hooks: Array.isArray(avatarRow.story_hooks)
          ? (avatarRow.story_hooks as unknown[]).map((t) => String(t))
          : [],
        signature_skill: avatarRow.skills && avatarRow.skills.name
          ? {
              name: avatarRow.skills.name,
              description: avatarRow.skills.description ?? "",
            }
          : null,
      }
    : null;

  return {
    campaign: {
      id: campaign.id,
      user_id: campaign.user_id,
      character_id: campaign.character_id,
      template_id: campaign.template_id,
      name: campaign.name,
      status: campaign.status,
      phase: campaign.phase as Phase,
      turns_in_current_phase: campaign.turns_in_current_phase,
      turns_since_last_progress: campaign.turns_since_last_progress,
      total_turns: campaign.total_turns,
    },
    template: {
      id: template.id,
      title: template.title,
      short_description: template.short_description,
      genre: template.genre,
      world_setting: template.world_setting,
      opening_scene: template.opening_scene,
      dm_guidance: template.dm_guidance,
    },
    characterSheet: {
      id: camChar.character_id,
      name: (camChar.characters as { name?: string } | null)?.name ?? "Adventurer",
      class: (camChar.characters as { class?: string } | null)?.class ?? "warrior",
      base_element: camChar.base_element,
      avatar_id: (camChar.characters as { avatar_id?: string } | null)?.avatar_id ?? "warrior_01",
      level: camChar.level,
      xp: camChar.xp,
      hp: camChar.hp,
      max_hp: camChar.max_hp,
      resource_type: camChar.resource_type,
      resource_current: camChar.resource_current,
      resource_max: camChar.resource_max,
      ac: camChar.ac,
      current_stats: camChar.current_stats,
      status_effects: camChar.status_effects ?? [],
    },
    inventory: (inventoryRes.data ?? []).map((r: Record<string, unknown>) => ({
      id: r.id as string,
      name: r.name as string,
      qty: r.qty as number,
      element: r.element as string,
      item_type: r.item_type as string,
      description: r.description as string,
    })),
    skills: (skillsRes.data ?? []).map((r: Record<string, unknown>) => ({
      id: r.id as string,
      name: r.name as string,
      description: r.description as string,
      element: r.element as string,
      cost_type: r.cost_type as "mp" | "stamina" | "free",
      cost_amount: r.cost_amount as number,
      dice: r.dice as string | null,
      modifier_stat: r.modifier_stat as string | null,
      is_basic_attack: r.is_basic_attack as boolean,
    })),
    bosses: (bossesRes.data ?? []).map((r: Record<string, unknown>) => ({
      id: r.id as string,
      name: (r.template_bosses as { name?: string } | null)?.name ?? "Unknown",
      tier: ((r.template_bosses as { tier?: string } | null)?.tier ?? "small") as "small" | "medium" | "big",
      status: r.status as "unencountered" | "encountered" | "defeated",
      template_boss_id: r.template_boss_id as string,
    })),
    sideMissions: (sideMissionsRes.data ?? []).map((r: Record<string, unknown>) => ({
      id: r.id as string,
      template_side_mission_id: r.template_side_mission_id as string,
      title: (r.template_side_missions as { title?: string } | null)?.title ?? "Side mission",
      status: r.status as "active" | "completed" | "failed",
      current_step: r.current_step as number,
    })),
    recentMessages: recentMessages.map((r: Record<string, unknown>) => ({
      role: r.role as "player" | "dm" | "system",
      content: r.content as string,
      created_at: r.created_at as string,
      requires_roll: r.requires_roll,
    })),
    worldMemory: worldMemoryRes.data?.summary ?? "",
    activeCombat: combatRes.data
      ? {
          id: combatRes.data.id,
          status: combatRes.data.status,
          round_number: combatRes.data.round_number,
          current_actor_index: combatRes.data.current_actor_index,
          turn_order: combatRes.data.turn_order,
        }
      : null,
    avatarFlavor,
  };
}
