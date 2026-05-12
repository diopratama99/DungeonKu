// combat-action — strict turn-based combat resolution.
//
// One HTTP request from the Flutter client = one player action + every subsequent enemy
// turn until it's the player's turn again (or the encounter ends). The client replays the
// returned `events[]` in order to animate them.
//
// Critical invariants:
//   - Initiative, dice rolls, damage numbers, and element multipliers ALL run server-side
//     using deterministic CSPRNG. The client cannot tamper with combat math.
//   - LLM is called ONLY for: boss signature moves with requires_llm_narration=true,
//     enemy death narration when the killed enemy is_boss, player death (game over),
//     and victory. Routine hits/misses use the static narration pool.
//   - Defending status effect (+2 AC) is applied via status_effects on campaign_characters.
//     We read it here, decay duration after the player's next turn ends.
//   - Element multipliers come from elementMultiplier(), never from the LLM.

import { z } from "../_shared/deps.ts";
import { handlePreflight, jsonResponse, errorResponse } from "../_shared/cors.ts";
import { newLogger } from "../_shared/logging.ts";
import type { Logger } from "../_shared/logging.ts";
import { getServiceClient, getAuthenticatedUser } from "../_shared/supabase.ts";
import type { SupabaseClient } from "../_shared/deps.ts";
import { CombatActionRequestSchema } from "../_shared/schemas.ts";
import { rollDie, rollExpression, modifierFromStat } from "../_shared/dice.ts";
import { elementMultiplier, describeMultiplier } from "../_shared/elements.ts";
import type { Element } from "../_shared/elements.ts";
import { narrate } from "../_shared/narration_pools.ts";
import { callPlain } from "../_shared/openai.ts";
import { ENV } from "../_shared/env.ts";
import { DIFFICULTY } from "../_shared/difficulty.ts";

// ----------------------------------------------------------------------
// Types
// ----------------------------------------------------------------------

type TurnSlot = { kind: "player"; initiative: number } | { kind: "enemy"; id: string; initiative: number };

interface CombatEvent {
  kind:
    | "initiative_rolled"
    | "player_attack" | "player_skill" | "player_defend" | "player_item" | "player_flee"
    | "enemy_attack" | "enemy_special"
    | "enemy_defeated" | "player_defeated" | "victory" | "fled";
  actor?: string;
  narration: string;
  damage?: number;
  hit?: boolean;
  critical?: boolean;
  element_effect?: string;
  enemy_id?: string;
  hp_after?: number;
  player_hp_after?: number;
  resource_after?: number;
  xp_awarded?: number;
}

interface EnemyRow {
  id: string;
  name: string;
  archetype: "aggressive" | "tactical" | "boss";
  element: Element;
  hp: number;
  max_hp: number;
  ac: number;
  base_damage: number;
  attack_dice: string;
  skills: Array<{ name: string; dice: string | null; element: string | null; requires_llm_narration?: boolean }>;
  is_boss: boolean;
  template_boss_id: string | null;
  status_effects: Array<{ key: string; label: string; expires_in_turns: number; magnitude: number }>;
}

interface CharRow {
  id: string;
  campaign_id: string;
  hp: number;
  max_hp: number;
  resource_current: number;
  resource_max: number;
  resource_type: "mp" | "stamina";
  level: number;
  xp: number;
  ac: number;
  current_stats: Record<string, number>;
  status_effects: Array<{ key: string; label: string; expires_in_turns: number; magnitude: number }>;
  base_element: Element;
}

// ----------------------------------------------------------------------
// HTTP entry
// ----------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (req.method !== "POST") return errorResponse(405, "method_not_allowed", "Use POST");

  const log = newLogger("combat-action");
  const startedAt = Date.now();

  const user = await getAuthenticatedUser(req);
  if (!user) return errorResponse(401, "unauthorized", "Missing or invalid Bearer token");

  let body: z.infer<typeof CombatActionRequestSchema>;
  try {
    body = CombatActionRequestSchema.parse(await req.json());
  } catch (err) {
    return errorResponse(400, "bad_body", (err as Error).message);
  }

  const sb = getServiceClient();

  // Verify ownership & active encounter.
  const { data: campaign } = await sb
    .from("campaigns")
    .select("id, user_id, status, phase, total_turns, turns_in_current_phase, turns_since_last_progress")
    .eq("id", body.campaign_id)
    .maybeSingle();
  if (!campaign || campaign.user_id !== user.id) {
    return errorResponse(404, "campaign_not_found", "Campaign not found");
  }
  if (campaign.status !== "active") {
    return errorResponse(409, "campaign_not_active", `Campaign is ${campaign.status}`);
  }

  const { data: encounter } = await sb
    .from("combat_encounters")
    .select("*")
    .eq("campaign_id", campaign.id)
    .eq("status", "active")
    .maybeSingle();
  if (!encounter) {
    return errorResponse(409, "no_active_encounter", "There is no active combat encounter");
  }

  // Load enemies + character.
  const { data: enemiesRaw } = await sb
    .from("combat_enemies")
    .select("*")
    .eq("encounter_id", encounter.id);
  const enemies = (enemiesRaw ?? []) as unknown as EnemyRow[];

  const { data: charRaw } = await sb
    .from("campaign_characters")
    .select("*")
    .eq("campaign_id", campaign.id)
    .single();
  if (!charRaw) return errorResponse(500, "no_character", "campaign_characters row missing");
  const char = charRaw as unknown as CharRow;

  const events: CombatEvent[] = [];

  // Initialise initiative if it's a fresh encounter.
  let turnOrder = encounter.turn_order as TurnSlot[] | null;
  let currentActorIndex = encounter.current_actor_index ?? 0;
  let roundNumber = encounter.round_number ?? 1;
  if (!turnOrder || turnOrder.length === 0) {
    turnOrder = rollInitiative(char, enemies);
    currentActorIndex = 0;
    roundNumber = 1;
    events.push({
      kind: "initiative_rolled",
      narration: `Initiative rolled. Order: ${turnOrder.map((s) =>
        s.kind === "player" ? `you (${s.initiative})` : `${enemyById(enemies, s.id)?.name ?? "?"} (${s.initiative})`
      ).join(", ")}.`,
    });
  }

  // If it is NOT the player's turn (enemy won initiative on the very first round, OR the
  // encounter state got out of sync), run enemy turns automatically until the player can act.
  // The old hard-reject (409) was wrong: enemies who win initiative should attack first, not
  // block the player indefinitely.
  {
    let safety2 = 0;
    while (turnOrder[currentActorIndex]?.kind !== "player" && safety2++ < 32) {
      const slot = turnOrder[currentActorIndex];
      if (slot.kind !== "enemy") break;
      const enemy = enemyById(enemies, slot.id);
      if (enemy && enemy.hp > 0) {
        await runEnemyTurn(enemy, char, events);
        await persistCharChanges(sb, char);
        if (char.hp <= 0) {
          // Player killed before landing their first action.
          await onPlayerDeath(sb, encounter.id, campaign.id, char, enemy, events, log);
          await writeCombatOutcomeFlag(sb, campaign.id, "lost");
          log.info("player_defeated_before_first_action", { latency_ms: Date.now() - startedAt });
          return jsonResponse({
            kind: "player_defeated", events, encounter_id: encounter.id, round_number: roundNumber,
            enemies: enemies.map((e) => ({ id: e.id, name: e.name, hp: e.hp, max_hp: e.max_hp, is_boss: e.is_boss, element: e.element })),
            character: { hp: char.hp, max_hp: char.max_hp, resource_current: char.resource_current, resource_max: char.resource_max, ac: char.ac },
          });
        }
      }
      currentActorIndex = (currentActorIndex + 1) % turnOrder.length;
      if (currentActorIndex === 0) roundNumber += 1;
    }
  }

  // ------------------------------ Player action ------------------------------
  const playerActionResult = await resolvePlayerAction(sb, char, enemies, body.action, log, events);

  if (playerActionResult.fled) {
    await closeEncounter(sb, encounter.id, "fled");
    await writeCombatOutcomeFlag(sb, campaign.id, "fled");
    await consumeDefendingBuffIfPresent(sb, char);
    log.info("player_fled", { latency_ms: Date.now() - startedAt });
    return jsonResponse({ kind: "fled", events, encounter_id: encounter.id });
  }

  // Persist enemy HP changes from player action.
  await persistEnemyChanges(sb, enemies);

  // Check victory.
  const aliveEnemies = () => enemies.filter((e) => e.hp > 0);
  if (aliveEnemies().length === 0) {
    await onVictory(sb, encounter.id, campaign.id, enemies, char, events);
    await writeCombatOutcomeFlag(sb, campaign.id, "won");
    await consumeDefendingBuffIfPresent(sb, char);
    log.info("victory", { latency_ms: Date.now() - startedAt });
    return jsonResponse({ kind: "victory", events, encounter_id: encounter.id });
  }

  // ------------------------------ Enemy turns until back to player ------------------------------
  // Advance the actor pointer past the player.
  currentActorIndex = (currentActorIndex + 1) % turnOrder.length;
  if (currentActorIndex === 0) roundNumber += 1;

  let safety = 0;
  while (turnOrder[currentActorIndex]?.kind !== "player") {
    if (safety++ > 32) break; // sanity cap; should never hit

    const slot = turnOrder[currentActorIndex];
    if (slot.kind !== "enemy") break;
    const enemy = enemyById(enemies, slot.id);
    if (!enemy || enemy.hp <= 0) {
      // Skip dead enemies.
      currentActorIndex = (currentActorIndex + 1) % turnOrder.length;
      if (currentActorIndex === 0) roundNumber += 1;
      continue;
    }

    await runEnemyTurn(enemy, char, events);
    await persistCharChanges(sb, char);

    if (char.hp <= 0) {
      // Player defeated.
      await onPlayerDeath(sb, encounter.id, campaign.id, char, enemy, events, log);
      await writeCombatOutcomeFlag(sb, campaign.id, "lost");
      log.info("player_defeated", { latency_ms: Date.now() - startedAt });
      return jsonResponse({ kind: "player_defeated", events, encounter_id: encounter.id });
    }

    currentActorIndex = (currentActorIndex + 1) % turnOrder.length;
    if (currentActorIndex === 0) roundNumber += 1;
  }

  // Decay defending buff (the +2 AC was for ONE round of enemy attacks).
  await consumeDefendingBuffIfPresent(sb, char);

  // Persist combat state.
  await sb.from("combat_encounters").update({
    turn_order: turnOrder,
    current_actor_index: currentActorIndex,
    round_number: roundNumber,
  }).eq("id", encounter.id);

  log.info("turn_resolved", { latency_ms: Date.now() - startedAt, events: events.length });

  return jsonResponse({
    kind: "ongoing",
    events,
    encounter_id: encounter.id,
    round_number: roundNumber,
    current_actor_index: currentActorIndex,
    enemies: enemies.map((e) => ({
      id: e.id, name: e.name, hp: e.hp, max_hp: e.max_hp, is_boss: e.is_boss, element: e.element,
    })),
    character: {
      hp: char.hp, max_hp: char.max_hp,
      resource_current: char.resource_current, resource_max: char.resource_max,
      ac: char.ac,
    },
  });
});

// ----------------------------------------------------------------------
// Initiative
// ----------------------------------------------------------------------
function rollInitiative(char: CharRow, enemies: EnemyRow[]): TurnSlot[] {
  const charInit = rollDie("d20") + modifierFromStat(char.current_stats.DEX ?? 10);
  const slots: TurnSlot[] = [
    { kind: "player", initiative: charInit },
    ...enemies.map<TurnSlot>((e) => ({
      kind: "enemy",
      id: e.id,
      initiative: rollDie("d20") + Math.max(0, Math.floor(e.base_damage / 4)),
    })),
  ];
  slots.sort((a, b) => b.initiative - a.initiative);
  return slots;
}

function enemyById(enemies: EnemyRow[], id: string): EnemyRow | undefined {
  return enemies.find((e) => e.id === id);
}

// ----------------------------------------------------------------------
// Player action resolution
// ----------------------------------------------------------------------
async function resolvePlayerAction(
  sb: SupabaseClient,
  char: CharRow,
  enemies: EnemyRow[],
  action: z.infer<typeof CombatActionRequestSchema>["action"],
  log: Logger,
  events: CombatEvent[],
): Promise<{ fled: boolean }> {
  const aliveEnemies = enemies.filter((e) => e.hp > 0);
  // Default target: lowest-HP non-boss enemy first; if none, the boss.
  const target = aliveEnemies.sort((a, b) => Number(a.is_boss) - Number(b.is_boss) || a.hp - b.hp)[0];

  switch (action.kind) {
    case "attack": {
      if (!target) return { fled: false };
      const stat = pickAttackStat(char);
      const attackRoll = rollDie("d20");
      const modifier = modifierFromStat(char.current_stats[stat] ?? 10);
      const total = attackRoll + modifier;

      if (attackRoll === 1) {
        events.push({ kind: "player_attack", actor: "player", hit: false, narration: narrate("player_attack_miss", { target: target.name }), critical: false });
        return { fled: false };
      }

      if (total < target.ac) {
        events.push({ kind: "player_attack", actor: "player", hit: false, narration: narrate("player_attack_miss", { target: target.name }), critical: false });
        return { fled: false };
      }

      // Hit.
      const isCrit = attackRoll === 20;
      let dmg = rollExpression("d6") + modifierFromStat(char.current_stats[stat] ?? 10);
      if (isCrit) dmg = Math.floor(dmg * 2);
      // Basic attack defaults to character's base_element (only relevant if the player has
      // an enchanted weapon; otherwise it'll be neutral and modifier is 1.0).
      const mul = elementMultiplier(char.base_element, target.element);
      const finalDmg = Math.max(1, Math.floor(dmg * mul));
      target.hp = Math.max(0, target.hp - finalDmg);

      events.push({
        kind: "player_attack", actor: "player", hit: true, critical: isCrit,
        damage: finalDmg, hp_after: target.hp, enemy_id: target.id,
        element_effect: describeMultiplier(mul),
        narration: isCrit
          ? narrate("player_attack_critical", { target: target.name, dmg: finalDmg })
          : narrate("player_attack_hit", { target: target.name, dmg: finalDmg }),
      });

      if (target.hp <= 0) await onEnemyDefeated(target, events);
      return { fled: false };
    }

    case "skill": {
      if (!target) return { fled: false };
      // Look up the skill catalog.
      const { data: skill } = await sb.from("skills").select("*").eq("id", action.skill_id).maybeSingle();
      if (!skill) {
        events.push({ kind: "player_skill", actor: "player", narration: `You attempt ${action.skill_id}, but you don't know that technique.` });
        return { fled: false };
      }
      // Resource check.
      const cost = skill.cost_amount as number;
      const costType = skill.cost_type as "mp" | "stamina" | "free";
      if (costType !== "free") {
        if (costType !== char.resource_type || char.resource_current < cost) {
          events.push({ kind: "player_skill", actor: "player", narration: `You haven't the ${costType.toUpperCase()} for ${skill.name}.` });
          return { fled: false };
        }
        char.resource_current -= cost;
      }

      const stat = (skill.modifier_stat as string | null) ?? pickAttackStat(char);
      const attackRoll = rollDie("d20");
      const modifier = modifierFromStat(char.current_stats[stat] ?? 10);
      const total = attackRoll + modifier;

      // Healing skills bypass attack roll — apply the heal directly.
      if (skill.kind === "heal") {
        const dice = (skill.dice as string | null) ?? "d6";
        const healAmount = rollExpression(dice) + Math.max(0, modifier);
        char.hp = Math.min(char.max_hp, char.hp + healAmount);
        events.push({
          kind: "player_skill", actor: "player",
          damage: -healAmount, player_hp_after: char.hp, resource_after: char.resource_current,
          narration: `Light gathers, and ${healAmount} HP returns to you.`,
        });
        return { fled: false };
      }

      // Buff skills.
      if (skill.kind === "buff") {
        const eff = (skill.base_damage_or_effect as { self_buff?: { ac_bonus?: number; attack_bonus?: number; duration?: number; next_attack_bonus?: number } } | null)?.self_buff;
        if (eff) {
          const filtered = char.status_effects.filter((s) => s.key !== `buff_${skill.id}`);
          filtered.push({
            key: `buff_${skill.id}`,
            label: skill.name as string,
            expires_in_turns: eff.duration ?? 1,
            magnitude: eff.ac_bonus ?? eff.attack_bonus ?? eff.next_attack_bonus ?? 0,
          });
          char.status_effects = filtered;
          events.push({
            kind: "player_skill", actor: "player",
            resource_after: char.resource_current,
            narration: `You weave ${skill.name}. The effect settles into your stance.`,
          });
        }
        return { fled: false };
      }

      // Attack skills.
      if (attackRoll === 1 || total < target.ac) {
        events.push({
          kind: "player_skill", actor: "player", hit: false, resource_after: char.resource_current,
          narration: `Your ${skill.name} misses ${target.name}.`,
        });
        return { fled: false };
      }
      const isCrit = attackRoll === 20;
      const dice = (skill.dice as string | null) ?? "d6";
      let dmg = rollExpression(dice) + modifier;
      if (isCrit) dmg = Math.floor(dmg * 2);
      const skillElement = (skill.element as Element) ?? "neutral";
      const elementForDamage: Element =
        (skill.base_damage_or_effect as { use_caster_element?: boolean } | null)?.use_caster_element
          ? char.base_element
          : skillElement;
      const mul = elementMultiplier(elementForDamage, target.element);
      const finalDmg = Math.max(1, Math.floor(dmg * mul));
      target.hp = Math.max(0, target.hp - finalDmg);

      events.push({
        kind: "player_skill", actor: "player", hit: true, critical: isCrit,
        damage: finalDmg, hp_after: target.hp, enemy_id: target.id,
        resource_after: char.resource_current,
        element_effect: describeMultiplier(mul),
        narration: isCrit
          ? `Your ${skill.name} lands devastatingly on ${target.name} for ${finalDmg} damage. ${describeMultiplier(mul)}.`
          : `Your ${skill.name} strikes ${target.name} for ${finalDmg} damage. ${describeMultiplier(mul)}.`,
      });

      if (target.hp <= 0) await onEnemyDefeated(target, events);
      return { fled: false };
    }

    case "defend": {
      // +2 AC for the duration of the next round of enemy attacks.
      char.status_effects = [
        ...char.status_effects.filter((s) => s.key !== "defending"),
        { key: "defending", label: "Defending", expires_in_turns: 1, magnitude: 2 },
      ];
      events.push({ kind: "player_defend", actor: "player", narration: narrate("combat_defend") });
      return { fled: false };
    }

    case "use_item": {
      // Use a consumable. We resolve a few common item names; unknown items are no-ops.
      const { data: item } = await sb.from("campaign_inventory")
        .select("*")
        .eq("id", action.item_id)
        .maybeSingle();
      if (!item || item.qty <= 0 || item.item_type !== "consumable") {
        events.push({ kind: "player_item", actor: "player", narration: "You reach for the item, but find none." });
        return { fled: false };
      }
      const name = (item.name as string).toLowerCase();
      let narration = `You use ${item.name as string}.`;
      if (name.includes("healing")) {
        const heal = 12;
        char.hp = Math.min(char.max_hp, char.hp + heal);
        narration = `The Healing Potion warms you. ${heal} HP restored.`;
        events.push({ kind: "player_item", actor: "player", damage: -heal, player_hp_after: char.hp, narration });
      } else if (name.includes("mana")) {
        const restore = 12;
        char.resource_current = Math.min(char.resource_max, char.resource_current + restore);
        narration = `Cool clarity floods you. ${restore} ${char.resource_type.toUpperCase()} restored.`;
        events.push({ kind: "player_item", actor: "player", resource_after: char.resource_current, narration });
      } else if (name.includes("stamina") || name.includes("draught")) {
        const restore = 12;
        char.resource_current = Math.min(char.resource_max, char.resource_current + restore);
        narration = `Heat returns to your limbs. ${restore} ${char.resource_type.toUpperCase()} restored.`;
        events.push({ kind: "player_item", actor: "player", resource_after: char.resource_current, narration });
      } else {
        events.push({ kind: "player_item", actor: "player", narration });
      }
      // Decrement inventory.
      const newQty = (item.qty as number) - 1;
      if (newQty <= 0) await sb.from("campaign_inventory").delete().eq("id", item.id as string);
      else await sb.from("campaign_inventory").update({ qty: newQty }).eq("id", item.id as string);
      return { fled: false };
    }

    case "flee": {
      const fleeRoll = rollDie("d20") + modifierFromStat(char.current_stats.DEX ?? 10);
      // Very Hard: flee DC scales with the highest enemy AC.
      const dc = Math.max(15, ...enemies.map((e) => e.ac - 1));
      if (fleeRoll >= dc) {
        events.push({ kind: "player_flee", actor: "player", narration: `You break for it (rolled ${fleeRoll} vs DC ${dc}). You escape.` });
        return { fled: true };
      }
      events.push({ kind: "player_flee", actor: "player", narration: `You try to break away (rolled ${fleeRoll} vs DC ${dc}) — but the path is closed.` });
      return { fled: false };
    }
  }
  // Exhaustiveness fallback — should be unreachable.
  return { fled: false };
}

function pickAttackStat(char: CharRow): "STR" | "DEX" | "INT" | "WIS" {
  const stats = char.current_stats;
  // Choose the highest of STR/DEX for martials; INT/WIS for casters.
  if (char.resource_type === "mp") {
    return (stats.INT ?? 10) >= (stats.WIS ?? 10) ? "INT" : "WIS";
  }
  return (stats.STR ?? 10) >= (stats.DEX ?? 10) ? "STR" : "DEX";
}

// ----------------------------------------------------------------------
// Enemy turn
// ----------------------------------------------------------------------
async function runEnemyTurn(enemy: EnemyRow, char: CharRow, events: CombatEvent[]): Promise<void> {
  // Decide on a signature move for tactical/boss archetypes some of the time.
  const useSignature = enemy.archetype !== "aggressive"
    && enemy.skills.length > 0
    && rollDie("d6") >= (enemy.archetype === "boss" ? 3 : 5);

  const move = useSignature
    ? enemy.skills[Math.floor(Math.random() * enemy.skills.length)]
    : null;

  // Effective AC factoring in defending buff.
  const defending = char.status_effects.find((s) => s.key === "defending");
  const effectiveAC = char.ac + (defending?.magnitude ?? 0);

  const attackRoll = rollDie("d20");
  const total = attackRoll + Math.floor((enemy.base_damage) / 3);

  if (attackRoll === 1 || total < effectiveAC) {
    events.push({
      kind: move ? "enemy_special" : "enemy_attack",
      actor: enemy.name,
      narration: narrate("enemy_attack_miss", { name: enemy.name }),
      hit: false,
    });
    return;
  }

  const isCrit = attackRoll === 20;
  const dice = move?.dice ?? enemy.attack_dice;
  let dmg = rollExpression(dice) + Math.max(0, Math.floor(enemy.base_damage / 4));
  if (isCrit) dmg = Math.floor(dmg * 2);
  const moveElement: Element = (move?.element as Element | undefined) ?? enemy.element;
  const mul = elementMultiplier(moveElement, char.base_element);
  let finalDmg = Math.max(1, Math.floor(dmg * mul));
  // Defending also gives 25% damage reduction.
  if (defending) finalDmg = Math.floor(finalDmg * 0.75);
  // Safety clamp to keep tuning sane.
  const cap = DIFFICULTY.enemyDamageMaxByLevel[Math.min(char.level, DIFFICULTY.maxLevel) - 1] ?? 30;
  finalDmg = Math.min(finalDmg, cap);

  char.hp = Math.max(0, char.hp - finalDmg);

  if (move?.requires_llm_narration) {
    // Boss signature: defer to LLM for narration.
    let narration = `${enemy.name} unleashes ${move.name} — you take ${finalDmg} damage.`;
    try {
      const r = await callPlain({
        model: ENV.OPENAI_MODEL(),
        systemPrompt: `You narrate ONE boss signature move outcome in 1-2 sentences. No meta-commentary, no listing options.`,
        userPrompt: `Boss "${enemy.name}" used "${move.name}". The blow ${isCrit ? "critically " : ""}lands for ${finalDmg} damage. Element effect: ${describeMultiplier(mul)}. Narrate.`,
        maxTokens: 100,
        temperature: 0.7,
      });
      if (r.text.trim()) narration = r.text.trim();
    } catch (_err) {
      // Fall back to deterministic line.
    }
    events.push({
      kind: "enemy_special", actor: enemy.name, hit: true, critical: isCrit,
      damage: finalDmg, player_hp_after: char.hp,
      element_effect: describeMultiplier(mul),
      narration,
    });
    return;
  }

  // Routine: pull from narration pool.
  const pool: Parameters<typeof narrate>[0] = isCrit
    ? "enemy_attack_critical"
    : enemy.archetype === "tactical"
      ? "enemy_attack_hit_tactical"
      : "enemy_attack_hit_aggressive";
  events.push({
    kind: "enemy_attack", actor: enemy.name, hit: true, critical: isCrit,
    damage: finalDmg, player_hp_after: char.hp,
    element_effect: describeMultiplier(mul),
    narration: narrate(pool, { name: enemy.name, dmg: finalDmg, limb: pickLimb() }),
  });
}

function pickLimb(): string {
  return ["shoulder", "arm", "side", "ribs", "thigh"][Math.floor(Math.random() * 5)];
}

// ----------------------------------------------------------------------
// Resolution helpers
// ----------------------------------------------------------------------
async function onEnemyDefeated(enemy: EnemyRow, events: CombatEvent[]): Promise<void> {
  if (enemy.is_boss) {
    let narration = `${enemy.name} crumples, defeated.`;
    try {
      const r = await callPlain({
        model: ENV.OPENAI_MODEL(),
        systemPrompt: `You narrate ONE boss death in 1-2 sentences. No meta-commentary.`,
        userPrompt: `The boss "${enemy.name}" has been defeated. Narrate the moment.`,
        maxTokens: 90,
        temperature: 0.7,
      });
      if (r.text.trim()) narration = r.text.trim();
    } catch (_err) {
      // ignore
    }
    events.push({ kind: "enemy_defeated", actor: enemy.name, enemy_id: enemy.id, narration });
  } else {
    events.push({
      kind: "enemy_defeated", actor: enemy.name, enemy_id: enemy.id,
      narration: `${enemy.name} falls and does not rise.`,
    });
  }
}

async function onVictory(
  sb: SupabaseClient, encounterId: string, campaignId: string,
  enemies: EnemyRow[], char: CharRow, events: CombatEvent[],
): Promise<void> {
  // XP award based on the enemies defeated.
  const xpPerArchetype = { aggressive: 30, tactical: 60, boss: 200 } as const;
  const xpAwarded = enemies.reduce((sum, e) => sum + (xpPerArchetype[e.archetype] ?? 30), 0);

  // Apply XP via the campaign_characters row directly (we already have char in memory).
  let leveledUpTo: number | null = null;
  char.xp += xpAwarded;
  while (char.level < DIFFICULTY.maxLevel && char.xp >= (DIFFICULTY.xpToNext[char.level] ?? Number.POSITIVE_INFINITY)) {
    char.xp -= DIFFICULTY.xpToNext[char.level];
    char.level += 1;
    char.max_hp += DIFFICULTY.hpGainPerLevel;
    char.hp = Math.min(char.hp + DIFFICULTY.hpGainPerLevel, char.max_hp);
    leveledUpTo = char.level;
  }
  await sb.from("campaign_characters").update({
    xp: char.xp, level: char.level, hp: char.hp, max_hp: char.max_hp,
  }).eq("id", char.id);

  // Mark any boss enemies as defeated in campaign_bosses.
  for (const e of enemies) {
    if (e.is_boss && e.template_boss_id) {
      await sb.from("campaign_bosses").update({
        status: "defeated",
        defeated_at: new Date().toISOString(),
      }).eq("campaign_id", campaignId).eq("template_boss_id", e.template_boss_id);
    }
  }

  // LLM narration for victory.
  let narration = `The fight is over. You stand, breath ragged. ${xpAwarded} XP gained.`;
  try {
    const r = await callPlain({
      model: ENV.OPENAI_MODEL(),
      systemPrompt: `You narrate the conclusion of a combat encounter in 1-2 sentences. No meta-commentary, no listing options.`,
      userPrompt: `The player has just defeated: ${enemies.map((e) => e.name).join(", ")}. They earned ${xpAwarded} XP${leveledUpTo ? ` and reached level ${leveledUpTo}` : ""}. Narrate.`,
      maxTokens: 110,
      temperature: 0.7,
    });
    if (r.text.trim()) narration = r.text.trim();
  } catch (_err) {
    // ignore
  }

  events.push({
    kind: "victory",
    narration,
    xp_awarded: xpAwarded,
    player_hp_after: char.hp,
    resource_after: char.resource_current,
  });

  await closeEncounter(sb, encounterId, "won");
}

async function onPlayerDeath(
  sb: SupabaseClient, encounterId: string, campaignId: string,
  char: CharRow, killer: EnemyRow, events: CombatEvent[], log: Logger,
): Promise<void> {
  let narration = `You fall, eyes dimming. ${killer.name} stands over you.`;
  try {
    const r = await callPlain({
      model: ENV.OPENAI_MODEL(),
      systemPrompt: `You narrate a player character's death in 2-3 short sentences. Tone: somber, in-fiction, the character's last sensations. No meta-commentary.`,
      userPrompt: `The character has fallen, killed by "${killer.name}". Narrate their death.`,
      maxTokens: DIFFICULTY.deathNarrationMaxTokens,
      temperature: 0.7,
    });
    if (r.text.trim()) narration = r.text.trim();
  } catch (err) {
    log.warn("death_narration_failed", { err: (err as Error).message });
  }

  events.push({
    kind: "player_defeated",
    narration,
    player_hp_after: 0,
    actor: killer.name,
  });

  await sb.from("combat_encounters").update({
    status: "lost",
    ended_at: new Date().toISOString(),
  }).eq("id", encounterId);
  await sb.from("campaigns").update({ status: "failed" }).eq("id", campaignId);
}

async function closeEncounter(sb: SupabaseClient, encounterId: string, status: "won" | "lost" | "fled"): Promise<void> {
  await sb.from("combat_encounters").update({
    status,
    ended_at: new Date().toISOString(),
  }).eq("id", encounterId);
}

/**
 * Write combat outcome back into campaign_node_state.flags so subsequent
 * story-graph edges can gate on combat_won / combat_fled / combat_lost.
 * No-op for legacy campaigns that have no campaign_node_state row.
 */
async function writeCombatOutcomeFlag(
  sb: SupabaseClient,
  campaignId: string,
  outcome: "won" | "lost" | "fled",
): Promise<void> {
  const { data } = await sb
    .from("campaign_node_state")
    .select("flags")
    .eq("campaign_id", campaignId)
    .maybeSingle();
  if (!data) return; // no story-engine state = legacy campaign

  const current = (data.flags ?? {}) as Record<string, unknown>;
  await sb.from("campaign_node_state")
    .update({
      flags: {
        ...current,
        combat_outcome: outcome,
        combat_won: outcome === "won",
        combat_lost: outcome === "lost",
        combat_fled: outcome === "fled",
        pending_combat_id: null,
      },
      updated_at: new Date().toISOString(),
    })
    .eq("campaign_id", campaignId);
}

async function persistEnemyChanges(sb: SupabaseClient, enemies: EnemyRow[]): Promise<void> {
  // Bulk update enemies' HP. We could do this in a single RPC; for MVP we do parallel per-row updates.
  await Promise.all(
    enemies.map((e) =>
      sb.from("combat_enemies").update({ hp: e.hp, status_effects: e.status_effects }).eq("id", e.id),
    ),
  );
}

async function persistCharChanges(sb: SupabaseClient, char: CharRow): Promise<void> {
  await sb.from("campaign_characters").update({
    hp: char.hp,
    resource_current: char.resource_current,
    status_effects: char.status_effects,
  }).eq("id", char.id);
}

async function consumeDefendingBuffIfPresent(sb: SupabaseClient, char: CharRow): Promise<void> {
  const before = char.status_effects.length;
  const after = char.status_effects
    .map((s) => s.key === "defending"
      ? { ...s, expires_in_turns: s.expires_in_turns - 1 }
      : s)
    .filter((s) => s.expires_in_turns > 0);
  if (after.length !== before) {
    char.status_effects = after;
    await sb.from("campaign_characters").update({ status_effects: after }).eq("id", char.id);
  } else {
    char.status_effects = after;
  }
}
