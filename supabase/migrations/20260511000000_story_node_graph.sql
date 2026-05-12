-- =====================================================================
-- DungeonKu — Story Node Graph (foundation for the scripted-story redesign)
-- =====================================================================
--
-- This migration introduces the data layer for the new "scripted story
-- graph + AI flavor" architecture documented in
-- /STORY_ENGINE_REDESIGN.md (root of repo).
--
-- WHY:
--   The previous architecture re-asked the LLM to invent the world,
--   plot, and options every turn. That cost ~3000 tokens per turn and
--   produced loops, contradictions, and stalls.
--
--   This migration adds a finite-state machine on top of which the LLM
--   becomes optional flavor:
--     • story_nodes  — every authored beat (scene, dialog, combat, etc.)
--     • story_edges  — every transition between beats, with gating
--     • campaign_node_state — per-campaign cursor + flags
--     • story_templates.root_node_id — entry point per campaign
--     • profiles.ai_role_*_enabled — per-user toggles for the four AI
--       roles (A reskin, B intent-map, C npc-voice, D roll-narrator)
--
-- COMBAT, DICE, SKILLS, INVENTORY, AVATAR LORE all remain as-is. The
-- story graph wraps them: a story_nodes row of type='combat' invokes
-- the existing combat engine via on_enter_actions; a roll inside a
-- scene is still resolved by resolve-roll. The graph just decides
-- WHICH scene we are in.
--
-- Schema-aware. Tables were moved from public → dungeonku in
-- 20260507000000; we set search_path so unqualified references resolve
-- against whichever schema currently owns the parent tables.
-- =====================================================================

set search_path to dungeonku, public;

-- ---------------------------------------------------------------------
-- 1. story_nodes — every authored beat
-- ---------------------------------------------------------------------
-- One row per "beat" of any campaign template. The body is dry,
-- finishable narration that the engine will display verbatim unless
-- ai_reskin_policy fires (Role A).
create table if not exists story_nodes (
  id              text primary key,
                  -- Stable, human-readable. Convention:
                  --   <template_slug>__<scene_slug>
                  -- e.g. "ember_outpost__intro"

  template_id     text not null
                  references story_templates(id) on delete cascade,

  type            text not null check (type in (
                    'scene',       -- ambient narration + options
                    'dialog',      -- NPC line + reply options (Role C may rewrite)
                    'choice',      -- pure branching, minimal narration
                    'combat',      -- on_enter_actions starts a combat encounter
                    'outcome',     -- terminal-ish: success/failure scene
                    'transition'   -- bridging beat
                  )),

  body            text not null default '',
                  -- Dry narration the engine displays as-is when no AI
                  -- role is fired. Should be self-contained: a player
                  -- with all four AI toggles OFF must still get a
                  -- coherent, finishable story.

  speaker         text,
                  -- For dialog nodes: the NPC who is speaking.
                  -- Used by Role C to rewrite the line in-character.

  speaker_profile jsonb default '{}'::jsonb,
                  -- Optional NPC tone bundle, e.g.
                  --   { "tone": ["gruff","weary","fair"],
                  --     "default_mood": "neutral" }
                  -- Mood may also be derived dynamically from flags
                  -- by the prompt builder.

  tags            jsonb default '[]'::jsonb,
                  -- Free-form tags. Engine recognises:
                  --   "pivotal"           — eligible for Role A reskin
                  --                         when ai_reskin_policy=
                  --                         "pivotal_only"
                  --   "first_visit"       — engine-applied
                  --   "show_locked"       — display gated edges greyed
                  --   "replayable_actions"— on_enter runs every visit
                  -- Authors may add their own.

  on_enter_actions jsonb default '[]'::jsonb,
                  -- Ordered list of side-effects fired the first time
                  -- the campaign enters this node (or every visit if
                  -- "replayable_actions" tag set). Each item:
                  --   { kind: "...", payload: { ... } }
                  -- Action kinds (handled in story_engine.ts):
                  --   grant_item        { item_id, qty }
                  --   grant_skill       { skill_id }
                  --   set_flag          { key, value }
                  --   consume_item      { item_id, qty }
                  --   cost_resource     { amount }
                  --   start_combat     { boss_id | enemy_set_id }
                  --   damage_player     { dice, element }
                  --   heal_player       { dice }
                  --   change_phase      { to_phase }
                  --   end_campaign      { outcome, summary_seed }

  ai_reskin_policy text not null default 'pivotal_only'
                  check (ai_reskin_policy in (
                    'always',         -- always send body to Role A
                    'pivotal_only',   -- only if "pivotal" tag set
                    'never'           -- show body verbatim
                  )),

  sort_order      int default 0,
  created_at      timestamptz default now()
);

create index if not exists idx_story_nodes_template
  on story_nodes(template_id, sort_order);

-- ---------------------------------------------------------------------
-- 2. story_edges — transitions between nodes
-- ---------------------------------------------------------------------
-- Each row is one option visible (or hidden) on its from_node. The
-- option_id is short and unique within from_node so authors can
-- reference it from analytics or debug logs.
create table if not exists story_edges (
  id              text primary key,
                  -- Convention: "<from_node_id>:<option_id>"

  from_node_id    text not null
                  references story_nodes(id) on delete cascade,

  option_id       text not null,
                  -- Short id, stable across edits. Unique within
                  -- from_node_id (see UNIQUE below).

  option_label    text not null,
                  -- Visible button text. 2-7 words, starts with verb.

  to_node_id      text not null
                  references story_nodes(id) on delete restrict,

  requires        jsonb default '{}'::jsonb,
                  -- Gating predicate. ALL keys ANDed; arrays = any-of.
                  -- Examples:
                  --   { "class":   ["warrior","blacksmith"] }
                  --   { "skill":   ["sig_anvil_skin"] }
                  --   { "stat":    { "STR": ">=14", "WIS": ">=10" } }
                  --   { "item":    ["forge_hammer"] }
                  --   { "flag":    ["completed_tutorial"] }
                  --   { "not_flag":["betrayed_smith"] }
                  --   { "hp_pct_above": 0.5 }
                  --   { "hp_pct_below": 0.25 }
                  -- Empty {} means unconditional.

  consumes        jsonb default '[]'::jsonb,
                  -- Side-effects when this edge is taken. Same kinds
                  -- as on_enter_actions but typically narrower:
                  -- set_flag, consume_item, cost_resource.

  sort_order      int default 0,

  unique (from_node_id, option_id)
);

create index if not exists idx_story_edges_from
  on story_edges(from_node_id, sort_order);

-- ---------------------------------------------------------------------
-- 3. campaign_node_state — per-campaign cursor + flags
-- ---------------------------------------------------------------------
-- One row per active campaign that uses the story-graph engine.
-- Initialized by CampaignsRepository.create() at the same time the
-- campaign_characters row is inserted.
create table if not exists campaign_node_state (
  campaign_id      uuid primary key
                   references campaigns(id) on delete cascade,

  current_node_id  text references story_nodes(id) on delete set null,

  visited_node_ids jsonb default '[]'::jsonb,
                   -- Array of node ids; engine appends on entry.
                   -- Used so on_enter_actions only fire on first visit
                   -- (unless "replayable_actions" tag is set).

  flags            jsonb default '{}'::jsonb,
                   -- Arbitrary kv set by edges/nodes. Queried by
                   -- requires.flag / requires.not_flag. Also stores
                   -- engine-internal counters like
                   --   intent_map_used: int (Role B rate limit)

  updated_at       timestamptz default now()
);

-- RLS — same owner-only pattern as other campaign-scoped tables.
alter table campaign_node_state enable row level security;

drop policy if exists "owners read campaign_node_state"  on campaign_node_state;
drop policy if exists "owners write campaign_node_state" on campaign_node_state;

create policy "owners read campaign_node_state"
  on campaign_node_state for select
  using (exists (
    select 1 from campaigns c
    where c.id = campaign_node_state.campaign_id
      and c.user_id = auth.uid()
  ));

create policy "owners write campaign_node_state"
  on campaign_node_state for all
  using (exists (
    select 1 from campaigns c
    where c.id = campaign_node_state.campaign_id
      and c.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from campaigns c
    where c.id = campaign_node_state.campaign_id
      and c.user_id = auth.uid()
  ));

-- ---------------------------------------------------------------------
-- 4. story_templates.root_node_id — entry point
-- ---------------------------------------------------------------------
-- New campaigns initialize campaign_node_state.current_node_id from
-- this column. NULL means "this template has no graph yet" — those
-- campaigns fall back to legacy behavior (or are blocked, depending on
-- §11 of STORY_ENGINE_REDESIGN.md).
alter table story_templates
  add column if not exists root_node_id text
    references story_nodes(id) on delete set null;

-- ---------------------------------------------------------------------
-- 5. campaigns.is_legacy — lock pre-graph campaigns to read-only
-- ---------------------------------------------------------------------
-- See §11 of STORY_ENGINE_REDESIGN.md. Backfilled here so the Flutter
-- campaign list can render a clear "Legacy" tag and route those
-- campaigns to a read-only history viewer instead of into the new
-- engine.
alter table campaigns
  add column if not exists is_legacy bool default false;

update campaigns
  set is_legacy = true
  where created_at < timestamp '2026-05-11'
    and is_legacy is distinct from true;

-- ---------------------------------------------------------------------
-- 6. profiles — per-user AI role toggles
-- ---------------------------------------------------------------------
-- Defaults: all roles enabled. The user can opt out of any subset to
-- save tokens; engine must degrade gracefully (use dry body / no
-- narration override / no free-text) when a role is disabled.
alter table profiles
  add column if not exists ai_role_reskinner_enabled    bool default true,
  add column if not exists ai_role_intent_mapper_enabled bool default true,
  add column if not exists ai_role_npc_voice_enabled    bool default true,
  add column if not exists ai_role_roll_narrator_enabled bool default true;
