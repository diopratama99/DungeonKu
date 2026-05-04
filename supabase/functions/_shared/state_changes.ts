// Server-side state-change applier. Every state_changes[] item from an LLM response goes
// through this. Validation happens here, NOT in the prompt — the LLM is trusted to suggest
// changes but never to compute final numbers (HP clamps, resource clamps, level thresholds).

import type { SupabaseClient } from "./deps.ts";
import type { StateChange } from "./schemas.ts";
import { DIFFICULTY, xpRequiredForNext } from "./difficulty.ts";
import type { Logger } from "./logging.ts";

export interface ApplyResult {
  applied: StateChange[];
  rejected: Array<{ change: StateChange; reason: string }>;
  /** Set when xp_add caused a level up. UI can show a level-up modal. */
  leveledUpTo: number | null;
  /** Set when hp_delta dropped HP to 0. dm-turn caller is expected to handle game over. */
  characterDied: boolean;
  /** Set when rest with sub_type=night_sleep at unsafe location triggered an ambush. */
  ambushed: boolean;
  /** Set when combat_start created an encounter; downstream callers may want the id. */
  combatEncounterId: string | null;
}

interface DbCharSnapshot {
  id: string;
  campaign_id: string;
  hp: number;
  max_hp: number;
  resource_current: number;
  resource_max: number;
  level: number;
  xp: number;
  current_stats: Record<string, number>;
  status_effects: Array<{ key: string; label: string; expires_in_turns: number; magnitude: number }>;
  base_element: string;
}

async function loadCharSnapshot(sb: SupabaseClient, campaignId: string): Promise<DbCharSnapshot> {
  const { data, error } = await sb
    .from("campaign_characters")
    .select("id, campaign_id, hp, max_hp, resource_current, resource_max, level, xp, current_stats, status_effects, base_element")
    .eq("campaign_id", campaignId)
    .single();
  if (error || !data) throw new Error(`failed to load campaign_characters: ${error?.message}`);
  return data as DbCharSnapshot;
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

/** d20 with no modifier — used internally only for ambush rolls. */
function dRng(max: number): number {
  const buf = new Uint32Array(1);
  const limit = Math.floor(0x1_0000_0000 / max) * max;
  while (true) {
    crypto.getRandomValues(buf);
    if (buf[0] < limit) return (buf[0] % max) + 1;
  }
}

export async function applyStateChanges(
  sb: SupabaseClient,
  campaignId: string,
  changes: StateChange[],
  log: Logger,
): Promise<ApplyResult> {
  const result: ApplyResult = {
    applied: [],
    rejected: [],
    leveledUpTo: null,
    characterDied: false,
    ambushed: false,
    combatEncounterId: null,
  };
  if (changes.length === 0) return result;

  // Pull the character snapshot once and update it in-memory; we write back at the end.
  let snap = await loadCharSnapshot(sb, campaignId);
  let snapDirty = false;

  for (const change of changes) {
    try {
      switch (change.type) {
        case "inventory_add": {
          // Upsert by (campaign_id, name) so re-stacking of identical items works.
          const { data: existing } = await sb
            .from("campaign_inventory")
            .select("id, qty")
            .eq("campaign_id", campaignId)
            .eq("name", change.name)
            .maybeSingle();
          if (existing) {
            await sb.from("campaign_inventory")
              .update({ qty: (existing.qty as number) + change.qty })
              .eq("id", existing.id as string);
          } else {
            await sb.from("campaign_inventory").insert({
              campaign_id: campaignId,
              name: change.name,
              qty: change.qty,
              description: change.description,
              element: change.element,
              item_type: change.item_type,
            });
          }
          result.applied.push(change);
          break;
        }

        case "inventory_remove": {
          const { data: existing } = await sb
            .from("campaign_inventory")
            .select("id, qty")
            .eq("campaign_id", campaignId)
            .eq("name", change.name)
            .maybeSingle();
          if (!existing) {
            result.rejected.push({ change, reason: "item not found" });
            break;
          }
          const newQty = (existing.qty as number) - change.qty;
          if (newQty <= 0) {
            await sb.from("campaign_inventory").delete().eq("id", existing.id as string);
          } else {
            await sb.from("campaign_inventory").update({ qty: newQty }).eq("id", existing.id as string);
          }
          result.applied.push(change);
          break;
        }

        case "hp_delta": {
          const next = clamp(snap.hp + change.amount, 0, snap.max_hp);
          if (next !== snap.hp) {
            snap.hp = next;
            snapDirty = true;
          }
          if (snap.hp <= 0) result.characterDied = true;
          result.applied.push(change);
          break;
        }

        case "resource_delta": {
          const next = clamp(snap.resource_current + change.amount, 0, snap.resource_max);
          if (next !== snap.resource_current) {
            snap.resource_current = next;
            snapDirty = true;
          }
          result.applied.push(change);
          break;
        }

        case "xp_add": {
          if (snap.level >= DIFFICULTY.maxLevel) {
            result.rejected.push({ change, reason: "max level reached" });
            break;
          }
          snap.xp += change.amount;
          snapDirty = true;
          // Possible cascade of level-ups (rare but possible from a big XP grant).
          while (snap.level < DIFFICULTY.maxLevel && snap.xp >= xpRequiredForNext(snap.level)) {
            snap.xp -= xpRequiredForNext(snap.level);
            snap.level += 1;
            snap.max_hp += DIFFICULTY.hpGainPerLevel;
            snap.hp = Math.min(snap.hp + DIFFICULTY.hpGainPerLevel, snap.max_hp);
            // Stat-point allocation is a UI step (player-driven via a level-up modal); we just
            // mark the level here. The Flutter app reads campaign_characters.level and prompts.
            result.leveledUpTo = snap.level;
          }
          result.applied.push(change);
          break;
        }

        case "status_add": {
          // Replace if same key already present (re-applying refreshes duration).
          const filtered = snap.status_effects.filter((s) => s.key !== change.key);
          filtered.push({
            key: change.key,
            label: change.label,
            expires_in_turns: change.duration,
            magnitude: change.magnitude,
          });
          snap.status_effects = filtered;
          snapDirty = true;
          result.applied.push(change);
          break;
        }

        case "status_remove": {
          const before = snap.status_effects.length;
          snap.status_effects = snap.status_effects.filter((s) => s.key !== change.key);
          if (snap.status_effects.length !== before) snapDirty = true;
          result.applied.push(change);
          break;
        }

        case "boss_status_change": {
          const { data: row } = await sb
            .from("campaign_bosses")
            .select("id, status")
            .eq("campaign_id", campaignId)
            .eq("template_boss_id", change.template_boss_id)
            .maybeSingle();
          if (!row) {
            result.rejected.push({ change, reason: "boss row not found" });
            break;
          }
          // Don't allow demoting from defeated -> encountered.
          if (row.status === "defeated") {
            result.rejected.push({ change, reason: "boss already defeated, no demotion allowed" });
            break;
          }
          await sb.from("campaign_bosses").update({
            status: change.next_status,
            defeated_at: change.next_status === "defeated" ? new Date().toISOString() : null,
          }).eq("id", row.id as string);
          result.applied.push(change);
          break;
        }

        case "rest": {
          if (change.sub_type === "night_sleep") {
            if (!change.safe) {
              // Roll for ambush. 35% chance for a dungeon location.
              const rolled = dRng(100);
              if (rolled <= 35) {
                result.ambushed = true;
                // Apply a chip of damage to represent the surprise; full ambush is handled
                // by combat-action being triggered separately.
                snap.hp = clamp(snap.hp - 4, 0, snap.max_hp);
                snapDirty = true;
                log.info("rest_ambush_triggered", { rolled });
                result.applied.push(change);
                break;
              }
            }
            // Full restore.
            snap.hp = snap.max_hp;
            snap.resource_current = snap.resource_max;
            snap.status_effects = []; // sleep clears status effects
            snapDirty = true;
          } else {
            // brief_rest: 50% restore, no status clear.
            snap.hp = clamp(snap.hp + Math.floor(snap.max_hp / 2), 0, snap.max_hp);
            snap.resource_current = clamp(
              snap.resource_current + Math.floor(snap.resource_max / 2),
              0,
              snap.resource_max,
            );
            snapDirty = true;
          }
          result.applied.push(change);
          break;
        }

        case "combat_start": {
          // Insert encounter + enemies. Initiative rolls happen in combat-action when it
          // first runs; here we just stage the encounter.
          const { data: enc, error: encErr } = await sb
            .from("combat_encounters")
            .insert({ campaign_id: campaignId, status: "active" })
            .select("id")
            .single();
          if (encErr || !enc) {
            result.rejected.push({ change, reason: `failed to create encounter: ${encErr?.message}` });
            break;
          }
          const enemyRows = change.enemies.map((e: typeof change.enemies[number]) => ({
            encounter_id: enc.id as string,
            name: e.name,
            archetype: e.archetype,
            element: e.element,
            hp: e.hp,
            max_hp: e.hp,
            ac: e.ac,
            base_damage: e.base_damage,
            attack_dice: e.attack_dice,
            is_boss: e.is_boss,
            template_boss_id: e.template_boss_id,
          }));
          const { error: enemyErr } = await sb.from("combat_enemies").insert(enemyRows);
          if (enemyErr) {
            result.rejected.push({ change, reason: `failed to create enemies: ${enemyErr.message}` });
            break;
          }
          result.combatEncounterId = enc.id as string;
          result.applied.push(change);
          break;
        }

        case "side_quest_progress": {
          const { data: row } = await sb
            .from("campaign_side_missions")
            .select("id, current_step, status")
            .eq("campaign_id", campaignId)
            .eq("template_side_mission_id", change.template_side_mission_id)
            .maybeSingle();
          if (!row) {
            result.rejected.push({ change, reason: "side mission not active for campaign" });
            break;
          }
          if (row.status !== "active") {
            result.rejected.push({ change, reason: `side mission already ${row.status}` });
            break;
          }
          if (change.event === "complete") {
            await sb.from("campaign_side_missions").update({
              status: "completed",
              completed_at: new Date().toISOString(),
            }).eq("id", row.id as string);
            // Reward XP from the template definition.
            const { data: tpl } = await sb
              .from("template_side_missions")
              .select("reward_xp, reward_items")
              .eq("id", change.template_side_mission_id)
              .maybeSingle();
            if (tpl?.reward_xp) {
              snap.xp += tpl.reward_xp as number;
              snapDirty = true;
              while (snap.level < DIFFICULTY.maxLevel && snap.xp >= xpRequiredForNext(snap.level)) {
                snap.xp -= xpRequiredForNext(snap.level);
                snap.level += 1;
                snap.max_hp += DIFFICULTY.hpGainPerLevel;
                snap.hp = Math.min(snap.hp + DIFFICULTY.hpGainPerLevel, snap.max_hp);
                result.leveledUpTo = snap.level;
              }
            }
            // Inject reward items into inventory.
            const items = (tpl?.reward_items as Array<{ name: string; qty?: number; description?: string; element?: string; item_type?: string }> | null) ?? [];
            if (items.length > 0) {
              await sb.from("campaign_inventory").insert(
                items.map((it) => ({
                  campaign_id: campaignId,
                  name: it.name,
                  qty: it.qty ?? 1,
                  description: it.description ?? "",
                  element: it.element ?? "neutral",
                  item_type: it.item_type ?? "misc",
                })),
              );
            }
          } else if (change.event === "fail") {
            await sb.from("campaign_side_missions").update({
              status: "failed",
              completed_at: new Date().toISOString(),
            }).eq("id", row.id as string);
          } else {
            await sb.from("campaign_side_missions").update({
              current_step: (row.current_step as number) + 1,
            }).eq("id", row.id as string);
          }
          result.applied.push(change);
          break;
        }
      }
    } catch (err) {
      log.error("state_change_failed", { change_type: change.type, err: (err as Error).message });
      result.rejected.push({ change, reason: (err as Error).message });
    }
  }

  if (snapDirty) {
    await sb.from("campaign_characters").update({
      hp: snap.hp,
      max_hp: snap.max_hp,
      resource_current: snap.resource_current,
      level: snap.level,
      xp: snap.xp,
      status_effects: snap.status_effects,
    }).eq("id", snap.id);
  }

  return result;
}

/**
 * Match an LLM-detected side quest intent (free-text trigger key) against the campaign's
 * template side missions. If a match exists, isn't already started, and we're under the
 * max_simultaneous cap, start it.
 */
export async function tryStartSideMissionFromIntent(
  sb: SupabaseClient,
  campaignId: string,
  trigger: string,
  currentPhase: string,
  log: Logger,
): Promise<{ started: boolean; mission?: { id: string; title: string } }> {
  const { data: campaign } = await sb
    .from("campaigns")
    .select("template_id")
    .eq("id", campaignId)
    .maybeSingle();
  if (!campaign) return { started: false };

  const { data: candidates } = await sb
    .from("template_side_missions")
    .select("*")
    .eq("template_id", campaign.template_id);

  const candidate = (candidates ?? []).find((c: Record<string, unknown>) =>
    (c.trigger_intent as string).toLowerCase() === trigger.toLowerCase()
  );
  if (!candidate) return { started: false };

  const requiredPhase = candidate.required_phase as string | null;
  if (requiredPhase && requiredPhase !== currentPhase) {
    log.info("side_mission_phase_mismatch", { trigger, requiredPhase, currentPhase });
    return { started: false };
  }

  // Already started?
  const { data: existing } = await sb
    .from("campaign_side_missions")
    .select("id")
    .eq("campaign_id", campaignId)
    .eq("template_side_mission_id", candidate.id as string)
    .maybeSingle();
  if (existing) return { started: false };

  // Max simultaneous cap.
  const { count: activeCount } = await sb
    .from("campaign_side_missions")
    .select("id", { count: "exact", head: true })
    .eq("campaign_id", campaignId)
    .eq("status", "active");
  const cap = (candidate.max_simultaneous as number) ?? 3;
  if ((activeCount ?? 0) >= cap) {
    log.info("side_mission_cap_reached", { trigger, activeCount, cap });
    return { started: false };
  }

  const { data: inserted, error } = await sb
    .from("campaign_side_missions")
    .insert({
      campaign_id: campaignId,
      template_side_mission_id: candidate.id as string,
      status: "active",
    })
    .select("id")
    .single();
  if (error || !inserted) {
    log.error("side_mission_insert_failed", { trigger, err: error?.message });
    return { started: false };
  }
  return { started: true, mission: { id: inserted.id as string, title: candidate.title as string } };
}
