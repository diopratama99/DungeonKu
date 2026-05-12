-- =====================================================================
-- Phase 1.5 — Combat ↔ story-engine flag handshake
--
-- Two changes:
--
-- 1. Gate existing "won" edges behind requires:{flag:["combat_won"]} so
--    the player can't skip combat by clicking the result option before
--    the fight resolves.
--
-- 2. Add "fled" edges for every combat node that currently has none, so
--    a player who flees has somewhere to go.  These are gated behind
--    requires:{flag:["combat_fled"]}.
--
-- The flags themselves are written by combat-action/index.ts on encounter
-- resolution (Phase 1.5 server changes) and cleared by
-- story_engine.ts:actStartCombat when a new combat begins.
-- =====================================================================

set search_path to dungeonku, public;

-- -------------------------------------------------------------------
-- 1. Gate combat-result "won" edges
-- -------------------------------------------------------------------

-- Gate: walk through after defeating the gate guards
UPDATE story_edges
SET requires = '{"flag":["combat_won"]}'::jsonb
WHERE id = 'ember_outpost__gate_combat:won';

-- Gate: step out of the barracks after clearing it
UPDATE story_edges
SET requires = '{"flag":["combat_won"]}'::jsonb
WHERE id = 'ember_outpost__barracks_combat:back';

-- Gate: leave the kennel shed after clearing it
UPDATE story_edges
SET requires = '{"flag":["combat_won"]}'::jsonb
WHERE id = 'ember_outpost__kennel_combat:back';

-- Gate: walk out of the sanctum after defeating Commander Korr
UPDATE story_edges
SET requires = '{"flag":["combat_won"]}'::jsonb
WHERE id = 'ember_outpost__korr_killed:to_pyrrhic';

-- -------------------------------------------------------------------
-- 2. Add "fled" edges for each combat node
-- -------------------------------------------------------------------

INSERT INTO story_edges
  (id, from_node_id, option_id, option_label, to_node_id, requires, consumes, sort_order)
VALUES
  -- Gate combat: flee back to the approach decision
  ('ember_outpost__gate_combat:flee',
   'ember_outpost__gate_combat',
   'flee', 'Break away and run',
   'ember_outpost__decide_approach',
   '{"flag":["combat_fled"]}'::jsonb, '[]'::jsonb, 20),

  -- Barracks combat: fall back into the courtyard
  ('ember_outpost__barracks_combat:flee',
   'ember_outpost__barracks_combat',
   'flee', 'Pull back before it gets worse',
   'ember_outpost__courtyard',
   '{"flag":["combat_fled"]}'::jsonb, '[]'::jsonb, 20),

  -- Kennel combat: run out of the shed
  ('ember_outpost__kennel_combat:flee',
   'ember_outpost__kennel_combat',
   'flee', 'Run out of the kennel',
   'ember_outpost__courtyard',
   '{"flag":["combat_fled"]}'::jsonb, '[]'::jsonb, 20),

  -- Korr boss fight: retreat back into the sanctum antechamber
  ('ember_outpost__korr_killed:flee',
   'ember_outpost__korr_killed',
   'flee', 'Fall back from the sanctum',
   'ember_outpost__sanctum_main',
   '{"flag":["combat_fled"]}'::jsonb, '[]'::jsonb, 30)

ON CONFLICT (id) DO NOTHING;
