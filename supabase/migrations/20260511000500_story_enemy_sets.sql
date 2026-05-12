-- =====================================================================
-- DungeonKu — story_enemy_sets
-- =====================================================================
-- Lookup table for combat encounters initiated by the story engine.
-- When a story node fires {kind:"start_combat", payload:{enemy_set_id}}
-- or {kind:"start_combat", payload:{boss_id}}, actStartCombat in
-- story_engine.ts queries this table and inserts the appropriate rows
-- into combat_enemies for the newly-created encounter.
--
-- Keys mirror the string IDs used in story_nodes.on_enter_actions so
-- the authoring schema stays plain JSON without UUID references.
-- =====================================================================

set search_path to dungeonku, public;

create table if not exists story_enemy_sets (
  id          text primary key,   -- e.g. 'gate_guards', 'commander_korr'
  template_id text not null references story_templates(id) on delete cascade,
  enemies     jsonb not null      -- array of enemy objects (see below)
  -- Each element mirrors the combat_enemies insert shape:
  -- { name, archetype, element, hp, ac, base_damage, attack_dice, is_boss }
  -- attack_dice defaults to 'd6' when omitted.
  -- is_boss defaults to false when omitted.
);

-- RLS: only service role writes; players can read via combat_enemies (already RLS'd)
alter table story_enemy_sets enable row level security;
-- No player-facing SELECT policy — only the edge function (service role) reads this.

-- =====================================================================
-- Seed: Ember Outpost enemy sets
-- =====================================================================

-- ---------- gate_guards ----------
-- Two fire soldiers posted at the outpost gate (Act 3).
-- Confrontational but not elite fighters.
insert into story_enemy_sets (id, template_id, enemies) values (
  'gate_guards',
  'ember_outpost',
  '[
    {
      "name": "Gate Guard",
      "archetype": "aggressive",
      "element": "fire",
      "hp": 18,
      "ac": 13,
      "base_damage": 5,
      "attack_dice": "d8",
      "is_boss": false
    },
    {
      "name": "Gate Guard",
      "archetype": "aggressive",
      "element": "fire",
      "hp": 18,
      "ac": 13,
      "base_damage": 5,
      "attack_dice": "d8",
      "is_boss": false
    }
  ]'::jsonb
) on conflict (id) do nothing;

-- ---------- barracks_pair ----------
-- Two off-duty soldiers in the barracks: the scarred veteran and his
-- less-experienced partner (Act 5, barracks encounter).
insert into story_enemy_sets (id, template_id, enemies) values (
  'barracks_pair',
  'ember_outpost',
  '[
    {
      "name": "Scarred Veteran",
      "archetype": "tactical",
      "element": "fire",
      "hp": 22,
      "ac": 14,
      "base_damage": 6,
      "attack_dice": "d8",
      "is_boss": false
    },
    {
      "name": "Red Leather Soldier",
      "archetype": "aggressive",
      "element": "fire",
      "hp": 18,
      "ac": 13,
      "base_damage": 4,
      "attack_dice": "d6",
      "is_boss": false
    }
  ]'::jsonb
) on conflict (id) do nothing;

-- ---------- fire_hounds ----------
-- Three hounds in the kennel, led by a larger pack leader (Act 5).
-- Fast, low AC, fight in a pack — defeat the pack leader to break
-- the formation.
insert into story_enemy_sets (id, template_id, enemies) values (
  'fire_hounds',
  'ember_outpost',
  '[
    {
      "name": "Fire Hound",
      "archetype": "aggressive",
      "element": "fire",
      "hp": 12,
      "ac": 12,
      "base_damage": 4,
      "attack_dice": "d6",
      "is_boss": false
    },
    {
      "name": "Fire Hound",
      "archetype": "aggressive",
      "element": "fire",
      "hp": 12,
      "ac": 12,
      "base_damage": 4,
      "attack_dice": "d6",
      "is_boss": false
    },
    {
      "name": "Pack Leader Hound",
      "archetype": "aggressive",
      "element": "fire",
      "hp": 18,
      "ac": 13,
      "base_damage": 5,
      "attack_dice": "d6",
      "is_boss": false
    }
  ]'::jsonb
) on conflict (id) do nothing;

-- ---------- dwarven_wards ----------
-- Two stone construct guardians sealing the dwarven passage (Act 3).
-- High AC, slow, earth element — tactical not aggressive.
insert into story_enemy_sets (id, template_id, enemies) values (
  'dwarven_wards',
  'ember_outpost',
  '[
    {
      "name": "Dwarven Stone Ward",
      "archetype": "tactical",
      "element": "earth",
      "hp": 26,
      "ac": 16,
      "base_damage": 6,
      "attack_dice": "d8",
      "is_boss": false
    },
    {
      "name": "Dwarven Stone Ward",
      "archetype": "tactical",
      "element": "earth",
      "hp": 26,
      "ac": 16,
      "base_damage": 6,
      "attack_dice": "d8",
      "is_boss": false
    }
  ]'::jsonb
) on conflict (id) do nothing;

-- ---------- commander_korr ----------
-- Final boss of Ember Outpost — Commander Korr, a former soldier
-- now bound to the outpost by oath and circumstance. Fire element,
-- high HP, boss archetype.
insert into story_enemy_sets (id, template_id, enemies) values (
  'commander_korr',
  'ember_outpost',
  '[
    {
      "name": "Commander Korr",
      "archetype": "boss",
      "element": "fire",
      "hp": 60,
      "ac": 16,
      "base_damage": 8,
      "attack_dice": "d10",
      "is_boss": true
    }
  ]'::jsonb
) on conflict (id) do nothing;
