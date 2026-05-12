// =====================================================================
// Story-graph engine helpers (Phase 1 — no AI, deterministic FSM)
// =====================================================================
// This module is the runtime counterpart of the story_nodes / story_edges
// schema introduced in 20260511000000.
//
// Public surface:
//   loadNodeState(sb, campaignId)        — read campaign_node_state row
//   ensureNodeStateInitialized(sb, ...)  — first-run seeding from template root
//   loadNode(sb, nodeId)                 — fetch a single story_node row
//   loadOutgoingEdges(sb, nodeId)        — fetch all edges leaving a node
//   loadGatingContext(sb, campaignId)    — bundle of class/skills/items/flags/stats/hp
//   checkRequires(predicate, ctx)        — pure JSON predicate evaluator
//   applyActions(sb, campaignId, actions[]) — side-effects (grant/consume/damage/etc)
//   markNodeVisited(sb, campaignId, nodeId) — append to visited_node_ids
//   transitionTo(sb, campaignId, toNodeId)  — set current_node_id
//
// Design notes:
//   • Every helper takes the service-role client. Callers are expected to
//     have already validated ownership upstream (see assertCampaignOwner).
//   • Action types are open-ended via {kind, payload}. Unknown kinds are
//     logged + skipped, never throw, so a forward-compatible authoring
//     change can't brick a live campaign.
//   • Errors propagate to the caller; we don't swallow DB failures.
//   • All state mutation is happen-after-read: no transactions are used
//     because PostgREST doesn't expose them, but each helper completes a
//     single logical change (read + write) before returning.
// =====================================================================

import type { SupabaseClient } from "./deps.ts";
import { rollExpression } from "./dice.ts";
import { loadProfileContext } from "./profile_context.ts";
import { reskinNarration } from "./reskin.ts";
import { extractToneTags, resolveMood, rewriteNpcLine } from "./npc_voice.ts";

// ---------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------

export interface StoryNodeRow {
  id: string;
  template_id: string;
  type: "scene" | "dialog" | "choice" | "combat" | "outcome" | "transition";
  body: string;
  speaker: string | null;
  speaker_profile: Record<string, unknown>;
  tags: string[];
  on_enter_actions: NodeAction[];
  ai_reskin_policy: "always" | "pivotal_only" | "never";
  sort_order: number;
}

export interface StoryEdgeRow {
  id: string;
  from_node_id: string;
  option_id: string;
  option_label: string;
  to_node_id: string;
  requires: RequiresPredicate;
  consumes: NodeAction[];
  sort_order: number;
}

export interface CampaignNodeStateRow {
  campaign_id: string;
  current_node_id: string | null;
  visited_node_ids: string[];
  flags: Record<string, unknown>;
  updated_at: string;
}

/**
 * Authored action descriptor. Both story_nodes.on_enter_actions and
 * story_edges.consumes use this shape.
 */
export interface NodeAction {
  kind: string;
  payload: Record<string, unknown>;
}

/**
 * JSON predicate stored on story_edges.requires. All keys are ANDed;
 * arrays are any-of; empty {} = unconditional.
 */
export interface RequiresPredicate {
  class?: string[];
  skill?: string[];
  stat?: Record<string, string>; // e.g. { STR: ">=14" }
  item?: string[];
  flag?: string[];
  not_flag?: string[];
  hp_pct_above?: number;
  hp_pct_below?: number;
}

export interface GatingContext {
  class: string;                 // single class id, e.g. "warrior"
  skills: Set<string>;           // skill ids the campaign has unlocked
  items: Set<string>;            // inventory names the campaign holds
  stats: Record<string, number>; // STR/DEX/CON/INT/WIS/CHA
  flags: Record<string, unknown>;
  hp: number;
  max_hp: number;
}

// ---------------------------------------------------------------------
// State loaders
// ---------------------------------------------------------------------

export async function loadNodeState(
  sb: SupabaseClient,
  campaignId: string,
): Promise<CampaignNodeStateRow | null> {
  const { data, error } = await sb
    .from("campaign_node_state")
    .select("*")
    .eq("campaign_id", campaignId)
    .maybeSingle();
  if (error) throw new Error(`loadNodeState failed: ${error.message}`);
  return data as CampaignNodeStateRow | null;
}

/**
 * Initialize state from the template's root_node_id if no row exists yet.
 * Idempotent — returns the existing row if already initialized. Returns
 * null if the campaign's template has no root node (legacy template).
 */
export async function ensureNodeStateInitialized(
  sb: SupabaseClient,
  campaignId: string,
): Promise<CampaignNodeStateRow | null> {
  const existing = await loadNodeState(sb, campaignId);
  if (existing && existing.current_node_id) return existing;

  // Lookup root_node_id via campaigns → story_templates
  const { data: cmp, error: cErr } = await sb
    .from("campaigns")
    .select("template_id")
    .eq("id", campaignId)
    .single();
  if (cErr || !cmp) throw new Error(`campaign not found: ${cErr?.message}`);

  const { data: tpl, error: tErr } = await sb
    .from("story_templates")
    .select("root_node_id")
    .eq("id", cmp.template_id)
    .single();
  if (tErr || !tpl) throw new Error(`template not found: ${tErr?.message}`);
  if (!tpl.root_node_id) return null; // legacy template, no graph

  const row: Partial<CampaignNodeStateRow> = {
    campaign_id: campaignId,
    current_node_id: tpl.root_node_id,
    visited_node_ids: [],
    flags: {},
  };
  const { data: inserted, error: iErr } = await sb
    .from("campaign_node_state")
    .upsert(row, { onConflict: "campaign_id" })
    .select("*")
    .single();
  if (iErr) throw new Error(`init node state failed: ${iErr.message}`);
  return inserted as CampaignNodeStateRow;
}

export async function loadNode(
  sb: SupabaseClient,
  nodeId: string,
): Promise<StoryNodeRow | null> {
  const { data, error } = await sb
    .from("story_nodes")
    .select("*")
    .eq("id", nodeId)
    .maybeSingle();
  if (error) throw new Error(`loadNode(${nodeId}) failed: ${error.message}`);
  return data as StoryNodeRow | null;
}

export async function loadOutgoingEdges(
  sb: SupabaseClient,
  nodeId: string,
): Promise<StoryEdgeRow[]> {
  const { data, error } = await sb
    .from("story_edges")
    .select("*")
    .eq("from_node_id", nodeId)
    .order("sort_order", { ascending: true });
  if (error) throw new Error(`loadOutgoingEdges(${nodeId}) failed: ${error.message}`);
  return (data ?? []) as StoryEdgeRow[];
}

// ---------------------------------------------------------------------
// Gating context
// ---------------------------------------------------------------------

export async function loadGatingContext(
  sb: SupabaseClient,
  campaignId: string,
): Promise<GatingContext> {
  // Class comes from characters via campaigns.character_id
  const { data: cmp, error: cErr } = await sb
    .from("campaigns")
    .select("character_id")
    .eq("id", campaignId)
    .single();
  if (cErr || !cmp) throw new Error(`campaign not found: ${cErr?.message}`);

  const { data: chr, error: chErr } = await sb
    .from("characters")
    .select("class")
    .eq("id", cmp.character_id)
    .single();
  if (chErr || !chr) throw new Error(`character not found: ${chErr?.message}`);

  // Per-campaign character snapshot (HP, stats)
  const { data: ccr, error: ccErr } = await sb
    .from("campaign_characters")
    .select("hp, max_hp, current_stats")
    .eq("campaign_id", campaignId)
    .single();
  if (ccErr || !ccr) throw new Error(`campaign_character not found: ${ccErr?.message}`);

  // Skills the campaign has learned
  const { data: skillRows, error: skErr } = await sb
    .from("campaign_skills")
    .select("skill_id")
    .eq("campaign_id", campaignId);
  if (skErr) throw new Error(`campaign_skills load failed: ${skErr.message}`);

  // Inventory names
  const { data: invRows, error: invErr } = await sb
    .from("campaign_inventory")
    .select("name, qty")
    .eq("campaign_id", campaignId)
    .gt("qty", 0);
  if (invErr) throw new Error(`campaign_inventory load failed: ${invErr.message}`);

  // Flags
  const state = await loadNodeState(sb, campaignId);

  return {
    class: chr.class as string,
    skills: new Set(
      (skillRows ?? []).map((row: { skill_id: string }) => row.skill_id),
    ),
    items: new Set(
      (invRows ?? []).map((row: { name: string }) => row.name),
    ),
    stats: (ccr.current_stats ?? {}) as Record<string, number>,
    flags: (state?.flags ?? {}) as Record<string, unknown>,
    hp: ccr.hp as number,
    max_hp: ccr.max_hp as number,
  };
}

// ---------------------------------------------------------------------
// Predicate evaluator
// ---------------------------------------------------------------------

/**
 * Evaluate a single requires-predicate against a context. All keys ANDed.
 * Empty / null predicate = unconditional (returns true).
 */
export function checkRequires(
  predicate: RequiresPredicate | null | undefined,
  ctx: GatingContext,
): boolean {
  if (!predicate) return true;

  if (predicate.class && predicate.class.length > 0) {
    if (!predicate.class.includes(ctx.class)) return false;
  }
  if (predicate.skill && predicate.skill.length > 0) {
    if (!predicate.skill.some((s) => ctx.skills.has(s))) return false;
  }
  if (predicate.item && predicate.item.length > 0) {
    if (!predicate.item.some((i) => ctx.items.has(i))) return false;
  }
  if (predicate.flag && predicate.flag.length > 0) {
    for (const f of predicate.flag) {
      if (!isTruthyFlag(ctx.flags[f])) return false;
    }
  }
  if (predicate.not_flag && predicate.not_flag.length > 0) {
    for (const f of predicate.not_flag) {
      if (isTruthyFlag(ctx.flags[f])) return false;
    }
  }
  if (predicate.stat) {
    for (const [statKey, expr] of Object.entries(predicate.stat)) {
      const actual = ctx.stats[statKey];
      if (actual === undefined || !checkStatExpr(actual, expr)) return false;
    }
  }
  if (predicate.hp_pct_above !== undefined) {
    if (ctx.max_hp <= 0) return false;
    if (ctx.hp / ctx.max_hp <= predicate.hp_pct_above) return false;
  }
  if (predicate.hp_pct_below !== undefined) {
    if (ctx.max_hp <= 0) return false;
    if (ctx.hp / ctx.max_hp >= predicate.hp_pct_below) return false;
  }
  return true;
}

function isTruthyFlag(v: unknown): boolean {
  if (v === undefined || v === null) return false;
  if (v === false || v === 0 || v === "") return false;
  return true;
}

/**
 * Stat expression: one of ">=N", ">N", "<=N", "<N", "==N", "!=N", or a
 * bare integer string treated as ">=".
 */
function checkStatExpr(actual: number, expr: string): boolean {
  const m = expr.trim().match(/^(>=|<=|==|!=|>|<)?\s*(-?\d+)$/);
  if (!m) return false;
  const op = m[1] ?? ">=";
  const n = parseInt(m[2], 10);
  switch (op) {
    case ">":  return actual >  n;
    case ">=": return actual >= n;
    case "<":  return actual <  n;
    case "<=": return actual <= n;
    case "==": return actual === n;
    case "!=": return actual !== n;
  }
  return false;
}

// ---------------------------------------------------------------------
// Action applier
// ---------------------------------------------------------------------

export interface ApplyActionsResult {
  damageDealt: number;
  healed: number;
  itemsGranted: string[];
  itemsConsumed: string[];
  flagsSet: Record<string, unknown>;
  startedCombatId: string | null;
  endedCampaign: { outcome: "success" | "failure"; summary_seed: string } | null;
  characterDied: boolean;
  unknownKinds: string[];
}

const EMPTY_RESULT: () => ApplyActionsResult = () => ({
  damageDealt: 0,
  healed: 0,
  itemsGranted: [],
  itemsConsumed: [],
  flagsSet: {},
  startedCombatId: null,
  endedCampaign: null,
  characterDied: false,
  unknownKinds: [],
});

/**
 * Apply a list of actions to a campaign in order. Each action mutates
 * exactly the rows its kind implies; aggregate effects (damage totals,
 * level up, etc.) are reported in the result for the caller to surface
 * to the player.
 */
export async function applyActions(
  sb: SupabaseClient,
  campaignId: string,
  actions: NodeAction[],
): Promise<ApplyActionsResult> {
  const result = EMPTY_RESULT();
  if (!actions || actions.length === 0) return result;

  for (const action of actions) {
    try {
      switch (action.kind) {
        case "grant_item":     await actGrantItem(sb, campaignId, action.payload, result); break;
        case "grant_skill":    await actGrantSkill(sb, campaignId, action.payload); break;
        case "set_flag":       await actSetFlag(sb, campaignId, action.payload, result); break;
        case "consume_item":   await actConsumeItem(sb, campaignId, action.payload, result); break;
        case "cost_resource":  await actCostResource(sb, campaignId, action.payload); break;
        case "damage_player":  await actDamage(sb, campaignId, action.payload, result); break;
        case "heal_player":    await actHeal(sb, campaignId, action.payload, result); break;
        case "change_phase":   await actChangePhase(sb, campaignId, action.payload); break;
        case "start_combat":   await actStartCombat(sb, campaignId, action.payload, result); break;
        case "end_campaign":   await actEndCampaign(sb, campaignId, action.payload, result); break;
        default:
          result.unknownKinds.push(action.kind);
      }
    } catch (e) {
      // Don't let a single bad action abort the whole list — log and continue.
      console.error(`applyAction(${action.kind}) failed:`, e);
    }
  }
  return result;
}

// --- individual action handlers ---

async function actGrantItem(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  const itemId = String(p.item_id ?? "");
  const qty = Number(p.qty ?? 1);
  if (!itemId || qty <= 0) return;
  await sb.from("campaign_inventory").insert({
    campaign_id: campaignId,
    name: itemId,
    qty,
    description: "",
    element: "neutral",
    item_type: "misc",
    metadata: {},
  });
  r.itemsGranted.push(itemId);
}

async function actGrantSkill(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>,
) {
  const skillId = String(p.skill_id ?? "");
  if (!skillId) return;
  // upsert via insert + ignore duplicate
  await sb.from("campaign_skills")
    .upsert(
      { campaign_id: campaignId, skill_id: skillId, learned_at_turn: 0 },
      { onConflict: "campaign_id,skill_id", ignoreDuplicates: true },
    );
}

async function actSetFlag(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  const key = String(p.key ?? "");
  if (!key) return;
  const value = p.value;

  const state = await loadNodeState(sb, campaignId);
  const current = state?.flags ?? {};
  const next = { ...current, [key]: value };
  await sb.from("campaign_node_state")
    .update({ flags: next, updated_at: new Date().toISOString() })
    .eq("campaign_id", campaignId);
  r.flagsSet[key] = value;
}

async function actConsumeItem(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  const itemId = String(p.item_id ?? "");
  const qty = Number(p.qty ?? 1);
  if (!itemId || qty <= 0) return;
  const { data } = await sb
    .from("campaign_inventory")
    .select("id, qty")
    .eq("campaign_id", campaignId)
    .eq("name", itemId)
    .order("qty", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data) return;
  const newQty = (data.qty as number) - qty;
  if (newQty <= 0) {
    await sb.from("campaign_inventory").delete().eq("id", data.id);
  } else {
    await sb.from("campaign_inventory").update({ qty: newQty }).eq("id", data.id);
  }
  r.itemsConsumed.push(itemId);
}

async function actCostResource(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>,
) {
  const amount = Number(p.amount ?? 0);
  if (amount <= 0) return;
  const { data } = await sb
    .from("campaign_characters")
    .select("resource_current")
    .eq("campaign_id", campaignId)
    .single();
  if (!data) return;
  const next = Math.max(0, (data.resource_current as number) - amount);
  await sb.from("campaign_characters")
    .update({ resource_current: next })
    .eq("campaign_id", campaignId);
}

async function actDamage(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  const dice = String(p.dice ?? "d4");
  const amount = rollExpression(dice);
  const { data } = await sb
    .from("campaign_characters")
    .select("hp, max_hp")
    .eq("campaign_id", campaignId)
    .single();
  if (!data) return;
  const next = Math.max(0, (data.hp as number) - amount);
  await sb.from("campaign_characters").update({ hp: next }).eq("campaign_id", campaignId);
  r.damageDealt += amount;
  if (next === 0) r.characterDied = true;
}

async function actHeal(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  const dice = String(p.dice ?? "d4");
  const amount = rollExpression(dice);
  const { data } = await sb
    .from("campaign_characters")
    .select("hp, max_hp")
    .eq("campaign_id", campaignId)
    .single();
  if (!data) return;
  const next = Math.min(data.max_hp as number, (data.hp as number) + amount);
  await sb.from("campaign_characters").update({ hp: next }).eq("campaign_id", campaignId);
  r.healed += amount;
}

async function actChangePhase(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>,
) {
  const toPhase = String(p.to_phase ?? "");
  if (!toPhase) return;
  await sb.from("campaigns").update({ phase: toPhase }).eq("id", campaignId);
}

async function actStartCombat(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  // Resolve the logical enemy set key — either enemy_set_id (minion groups)
  // or boss_id (single boss, stored as a story_enemy_sets row keyed by name).
  const enemySetKey = String(p.enemy_set_id ?? p.boss_id ?? "");

  // Look up enemy definitions from story_enemy_sets.
  let enemyDefs: Array<Record<string, unknown>> = [];
  if (enemySetKey) {
    const { data: setRow } = await sb
      .from("story_enemy_sets")
      .select("enemies")
      .eq("id", enemySetKey)
      .maybeSingle();
    if (setRow?.enemies) {
      enemyDefs = setRow.enemies as Array<Record<string, unknown>>;
    } else {
      console.warn(`actStartCombat: no story_enemy_sets row for key="${enemySetKey}"`);
    }
  }

  const encounterMeta = {
    boss_id: p.boss_id ?? null,
    enemy_set_id: p.enemy_set_id ?? null,
    started_by_story_engine: true,
  };

  const { data, error } = await sb
    .from("combat_encounters")
    .insert({
      campaign_id: campaignId,
      status: "active",
      turn_order: [],
      current_actor_index: 0,
    })
    .select("id")
    .single();
  if (error || !data) {
    console.error("actStartCombat insert failed", error);
    return;
  }
  r.startedCombatId = data.id as string;

  // Insert enemies so combat-action has actual opponents to fight.
  if (enemyDefs.length > 0) {
    const enemyRows = enemyDefs.map((e) => ({
      encounter_id: data.id as string,
      name: String(e.name ?? "Unknown"),
      archetype: String(e.archetype ?? "aggressive"),
      element: String(e.element ?? "neutral"),
      hp: Number(e.hp ?? 10),
      max_hp: Number(e.hp ?? 10),
      ac: Number(e.ac ?? 12),
      base_damage: Number(e.base_damage ?? 4),
      attack_dice: String(e.attack_dice ?? "d6"),
      is_boss: Boolean(e.is_boss ?? false),
    }));
    const { error: enemyErr } = await sb.from("combat_enemies").insert(enemyRows);
    if (enemyErr) {
      console.error("actStartCombat: combat_enemies insert failed", enemyErr.message);
    }
  }

  // Single batch update: set pending flags + clear stale combat-outcome flags
  // from any previous encounter so new combat nodes don't inherit old results.
  const state = await loadNodeState(sb, campaignId);
  const current = state?.flags ?? {};
  const mergedFlags = {
    ...current,
    pending_combat_id: data.id,
    pending_combat_meta: encounterMeta,
    combat_outcome: null,
    combat_won: false,
    combat_fled: false,
    combat_lost: false,
  };
  await sb.from("campaign_node_state")
    .update({ flags: mergedFlags, updated_at: new Date().toISOString() })
    .eq("campaign_id", campaignId);
  r.flagsSet["pending_combat_id"] = data.id;
  r.flagsSet["pending_combat_meta"] = encounterMeta;
}

async function actEndCampaign(
  sb: SupabaseClient, campaignId: string, p: Record<string, unknown>, r: ApplyActionsResult,
) {
  const outcome = (p.outcome === "failure" ? "failed" : "completed") as "completed" | "failed";
  const summarySeed = String(p.summary_seed ?? "");
  await sb.from("campaigns").update({ status: outcome }).eq("id", campaignId);
  r.endedCampaign = {
    outcome: outcome === "completed" ? "success" : "failure",
    summary_seed: summarySeed,
  };
}

// ---------------------------------------------------------------------
// Cursor helpers
// ---------------------------------------------------------------------

export async function markNodeVisited(
  sb: SupabaseClient, campaignId: string, nodeId: string,
): Promise<void> {
  const state = await loadNodeState(sb, campaignId);
  if (!state) return;
  if (state.visited_node_ids.includes(nodeId)) return;
  await sb.from("campaign_node_state")
    .update({
      visited_node_ids: [...state.visited_node_ids, nodeId],
      updated_at: new Date().toISOString(),
    })
    .eq("campaign_id", campaignId);
}

export async function transitionTo(
  sb: SupabaseClient, campaignId: string, toNodeId: string,
): Promise<void> {
  await sb.from("campaign_node_state")
    .update({ current_node_id: toNodeId, updated_at: new Date().toISOString() })
    .eq("campaign_id", campaignId);
}

// ---------------------------------------------------------------------
// High-level render
// ---------------------------------------------------------------------

export interface RenderedOption {
  id: string;             // story_edges.option_id
  label: string;
  locked: boolean;        // requires failed
  lock_reason?: string;   // human-readable hint when locked
}

export interface RenderedNodePayload {
  node_id: string;
  node_type: StoryNodeRow["type"];
  body: string;           // dry text from DB (Phase 2 will optionally reskin via Role A)
  speaker: string | null;
  tags: string[];
  options: RenderedOption[];
  /** Side-effects observed this render (for client toasts: "took d6 damage", etc.) */
  on_enter_result: ApplyActionsResult | null;
  /** True iff this was the first time the node was visited this campaign. */
  was_first_visit: boolean;
  /** True iff actStartCombat was fired in on_enter; client should route to combat. */
  pending_combat_id: string | null;
  /** Set when end_campaign action fired; client should show outcome screen. */
  ended_campaign:
    | { outcome: "success" | "failure"; summary_seed: string }
    | null;
  /** Phase 2: which AI role (if any) rewrote `body` from its authored
   *  form. `null` means body is the dry, deterministic prose from the DB.
   *  UI may show a small badge for transparency. */
  ai_role_used: "reskinner" | "npc_voice" | null;
}

/**
 * Pure FSM render — Phase 1, no AI. Call this from both story-turn
 * (read-only render of the current node) and player-action (after
 * transitioning to a new node). Idempotent for the SAME visit-state:
 * re-rendering the same already-visited node won't re-fire actions.
 */
export async function renderNodePayload(
  sb: SupabaseClient, campaignId: string,
): Promise<RenderedNodePayload> {
  const state = await ensureNodeStateInitialized(sb, campaignId);
  if (!state || !state.current_node_id) {
    throw new Error("campaign has no current node and template has no root_node_id");
  }
  const nodeId = state.current_node_id;
  const node = await loadNode(sb, nodeId);
  if (!node) throw new Error(`current node ${nodeId} not found in story_nodes`);

  // Determine first-visit before mutating visited list.
  const replayActions = (node.tags ?? []).includes("replayable_actions");
  const firstVisit = !state.visited_node_ids.includes(nodeId);

  let actionResult: ApplyActionsResult | null = null;
  if ((firstVisit || replayActions) && (node.on_enter_actions ?? []).length > 0) {
    actionResult = await applyActions(sb, campaignId, node.on_enter_actions);
  }
  if (firstVisit) {
    await markNodeVisited(sb, campaignId, nodeId);
  }

  // Gather context AFTER actions so newly-granted items/flags are visible
  // when filtering options.
  const ctx = await loadGatingContext(sb, campaignId);
  const edges = await loadOutgoingEdges(sb, nodeId);

  const showLocked = (node.tags ?? []).includes("show_locked");
  const options: RenderedOption[] = [];
  for (const e of edges) {
    const ok = checkRequires(e.requires, ctx);
    if (!ok && !showLocked) continue;
    options.push({
      id: e.option_id,
      label: e.option_label,
      locked: !ok,
      lock_reason: !ok ? describeRequires(e.requires) : undefined,
    });
  }

  // ----- Phase 2: optional AI rewrites of the authored body -----
  // Order:
  //   1. NPC voice (Role C) — only for dialog nodes with a speaker
  //   2. Reskinner  (Role A) — for non-dialog nodes whose
  //      ai_reskin_policy permits, OR for dialog nodes when no NPC
  //      voice toggle is on (so dialogs at least get reskinned)
  // Both helpers return null on failure; we always fall back to
  // the dry authored body.
  let body = node.body ?? "";
  let aiRoleUsed: "reskinner" | "npc_voice" | null = null;

  // Skip AI rewrites entirely for ending nodes — those are carefully
  // crafted prose with a specific cadence; rewriting risks losing the
  // intended punch and is the largest single chunk of text in the
  // template (high token cost, low gain).
  const skipAi = (node.tags ?? []).includes("ending");

  if (!skipAi) {
    const profile = await loadProfileContext(sb, campaignId);
    const speaker = node.speaker ?? null;
    const isDialog = node.type === "dialog" && !!speaker;

    // Role C — NPC voice
    if (isDialog && profile.toggles.npcVoice) {
      const tone = extractToneTags(node.speaker_profile ?? {});
      const mood = resolveMood(node.speaker_profile ?? {}, node.tags ?? []);
      const rewritten = await rewriteNpcLine(
        {
          npc_name: speaker as string,
          npc_tone: tone,
          npc_mood: mood,
          raw_line: body,
          player_voice_tags: profile.avatar?.personality_tags ?? [],
        },
        profile.avatar,
      );
      if (rewritten) {
        body = rewritten;
        aiRoleUsed = "npc_voice";
      }
    }

    // Role A — reskinner (skipped if NPC voice already rewrote the body)
    if (aiRoleUsed === null && profile.toggles.reskinner) {
      const policy = node.ai_reskin_policy ?? "pivotal_only";
      const isPivotal = (node.tags ?? []).includes("pivotal");
      const policyAllows =
        policy === "always" ||
        (policy === "pivotal_only" && isPivotal);
      if (policyAllows) {
        const rewritten = await reskinNarration(
          {
            node_body: body,
            scene_type: node.type,
            voice_tags: profile.avatar?.personality_tags ?? [],
            avatar_origin: profile.avatar?.backstory ?? "",
          },
          profile.avatar,
        );
        if (rewritten) {
          body = rewritten;
          aiRoleUsed = "reskinner";
        }
      }
    }
  }

  return {
    node_id: node.id,
    node_type: node.type,
    body,
    speaker: node.speaker,
    tags: node.tags ?? [],
    options,
    on_enter_result: actionResult,
    was_first_visit: firstVisit,
    pending_combat_id: actionResult?.startedCombatId ?? null,
    ended_campaign: actionResult?.endedCampaign ?? null,
    ai_role_used: aiRoleUsed,
  };
}

/** Compact one-line description of the unmet predicate for UX hints. */
function describeRequires(p: RequiresPredicate | null | undefined): string {
  if (!p) return "";
  const parts: string[] = [];
  if (p.class && p.class.length) parts.push(`class: ${p.class.join(" or ")}`);
  if (p.skill && p.skill.length) parts.push(`skill: ${p.skill.join(" or ")}`);
  if (p.item && p.item.length) parts.push(`item: ${p.item.join(" or ")}`);
  if (p.flag && p.flag.length) parts.push(`needs: ${p.flag.join(", ")}`);
  if (p.not_flag && p.not_flag.length) parts.push(`blocked by: ${p.not_flag.join(", ")}`);
  if (p.stat) {
    for (const [k, v] of Object.entries(p.stat)) parts.push(`${k} ${v}`);
  }
  if (p.hp_pct_above !== undefined) parts.push(`hp > ${(p.hp_pct_above * 100) | 0}%`);
  if (p.hp_pct_below !== undefined) parts.push(`hp < ${(p.hp_pct_below * 100) | 0}%`);
  return parts.join(" · ");
}

/**
 * Take an option from the current node — validate, apply consumes,
 * transition cursor, render the new node. Returns the new render.
 */
export async function takeOption(
  sb: SupabaseClient, campaignId: string, optionId: string,
): Promise<RenderedNodePayload> {
  const state = await loadNodeState(sb, campaignId);
  if (!state || !state.current_node_id) {
    throw new Error("campaign_node_state not initialized");
  }
  const { data: edge, error } = await sb
    .from("story_edges")
    .select("*")
    .eq("from_node_id", state.current_node_id)
    .eq("option_id", optionId)
    .maybeSingle();
  if (error) throw new Error(`takeOption load edge failed: ${error.message}`);
  if (!edge) throw new Error(`option ${optionId} not valid for node ${state.current_node_id}`);

  // Re-validate gating defensively (client may have stale data).
  const ctx = await loadGatingContext(sb, campaignId);
  if (!checkRequires((edge as StoryEdgeRow).requires, ctx)) {
    throw new Error(`option ${optionId} requirements not met`);
  }

  // Apply edge consumes BEFORE the transition, so new flags are visible
  // to the entered node's on_enter logic.
  await applyActions(sb, campaignId, (edge as StoryEdgeRow).consumes ?? []);
  await transitionTo(sb, campaignId, (edge as StoryEdgeRow).to_node_id);

  return renderNodePayload(sb, campaignId);
}
