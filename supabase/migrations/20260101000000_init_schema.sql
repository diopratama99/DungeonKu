-- DungeonKu — initial schema
-- Conventions:
--   * UUIDs for user-owned rows (gen_random_uuid()).
--   * TEXT slug PKs for reference data (class_definitions, skills, avatar_templates, story_templates).
--   * status fields use TEXT + CHECK constraints (more migration-friendly than enum types).
--   * jsonb for nested game data (stats, options, state_changes, etc.). Strict shapes are validated in
--     the Edge Functions (zod) and the Flutter client (freezed); we deliberately keep the SQL flexible
--     so we can iterate on the schema without painful migrations.

create extension if not exists "pgcrypto";

----------------------------------------------------------------------
-- Reference data (public-read, seeded). Not user-owned.
----------------------------------------------------------------------

create table if not exists public.class_definitions (
  id                  text primary key,                       -- 'warrior', 'mage', ...
  name                text not null,
  description         text not null default '',
  base_element_default text not null,                         -- 'neutral' for non-magic, 'light' for priest, etc.
  resource_type       text not null check (resource_type in ('mp', 'stamina')),
  starting_hp         integer not null check (starting_hp > 0),
  starting_resource   integer not null check (starting_resource >= 0),
  starting_ac         integer not null default 12,
  base_stats          jsonb not null,                         -- { STR, DEX, CON, INT, WIS, CHA }
  starting_skills     jsonb not null default '[]'::jsonb,     -- array of skill ids
  level_progression   jsonb not null default '{}'::jsonb,     -- { "2": ["skill_id"], "3": [...] }
  notes               text not null default '',
  sort_order          integer not null default 0
);

create table if not exists public.skills (
  id                    text primary key,                     -- 'fireball', 'power_strike', ...
  name                  text not null,
  description           text not null default '',
  element               text not null,                        -- 'fire'|'water'|...|'neutral'|'light'|'dark'
  kind                  text not null check (kind in ('attack', 'heal', 'buff', 'debuff', 'utility')),
  cost_type             text not null check (cost_type in ('mp', 'stamina', 'free')),
  cost_amount           integer not null default 0 check (cost_amount >= 0),
  dice                  text,                                 -- 'd6', '2d6', 'd20', null for non-rolling effects
  modifier_stat         text,                                 -- 'STR'|'DEX'|'INT'|'WIS'|null
  base_damage_or_effect jsonb not null default '{}'::jsonb,   -- e.g. { "damage_bonus": 2, "heal": 8, "status": "poison" }
  available_to_classes  jsonb not null default '[]'::jsonb,   -- array of class ids; empty = available to all
  required_level        integer not null default 1,
  is_basic_attack       boolean not null default false,
  sort_order            integer not null default 0
);

create table if not exists public.avatar_templates (
  id            text primary key,
  display_name  text not null,
  image_url     text not null,
  class_filter  jsonb not null default '[]'::jsonb,           -- array of class ids; empty = any class
  sort_order    integer not null default 0
);

create table if not exists public.story_templates (
  id                text primary key,
  title             text not null,
  short_description text not null,
  genre             text not null,
  world_setting     text not null,                            -- paragraph injected into system prompt
  opening_scene     text not null,                            -- DM's first narration
  dm_guidance       text not null,                            -- bullet points for the DM
  cover_image_url   text,
  is_active         boolean not null default true,
  sort_order        integer not null default 0
);

create table if not exists public.template_bosses (
  id              uuid primary key default gen_random_uuid(),
  template_id     text not null references public.story_templates(id) on delete cascade,
  name            text not null,
  description     text not null default '',
  tier            text not null check (tier in ('small', 'medium', 'big')),
  element         text not null default 'neutral',
  hp              integer not null check (hp > 0),
  base_damage     integer not null check (base_damage >= 0),
  ac              integer not null default 14,
  order_index     integer not null default 0,
  signature_moves jsonb not null default '[]'::jsonb          -- [{ name, dice, requires_llm_narration: bool }]
);

create index if not exists template_bosses_template_idx on public.template_bosses(template_id, order_index);

create table if not exists public.template_side_missions (
  id                uuid primary key default gen_random_uuid(),
  template_id       text not null references public.story_templates(id) on delete cascade,
  title             text not null,
  description       text not null default '',
  trigger_intent    text not null,                            -- canonical trigger key (e.g. 'help_villager')
  trigger_keywords  jsonb not null default '[]'::jsonb,
  reward_xp         integer not null default 100,
  reward_items      jsonb not null default '[]'::jsonb,
  required_phase    text check (required_phase in ('intro', 'rising', 'climax', 'resolution')),
  max_simultaneous  integer not null default 3,
  steps             jsonb not null default '[]'::jsonb        -- ordered list of step descriptions
);

create index if not exists template_side_missions_template_idx on public.template_side_missions(template_id);
create index if not exists template_side_missions_trigger_idx on public.template_side_missions(trigger_intent);

----------------------------------------------------------------------
-- User profile data
----------------------------------------------------------------------

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Auto-create a profile row when a new auth user signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

----------------------------------------------------------------------
-- Characters (profile-level, max 3 per user)
----------------------------------------------------------------------

create table if not exists public.characters (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  name         text not null check (length(name) between 1 and 32),
  class        text not null references public.class_definitions(id),
  base_element text not null,
  avatar_id    text not null references public.avatar_templates(id),
  stats        jsonb not null,                                -- { STR, DEX, CON, INT, WIS, CHA } at creation time
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists characters_user_idx on public.characters(user_id);

create or replace function public.enforce_character_limit()
returns trigger
language plpgsql
as $$
declare
  current_count integer;
begin
  select count(*) into current_count from public.characters where user_id = new.user_id;
  if current_count >= 3 then
    raise exception 'character_limit_reached: a user can have at most 3 characters';
  end if;
  return new;
end;
$$;

create trigger enforce_character_limit_trigger
  before insert on public.characters
  for each row execute function public.enforce_character_limit();

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger characters_touch_updated_at
  before update on public.characters
  for each row execute function public.touch_updated_at();

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

----------------------------------------------------------------------
-- Campaigns
----------------------------------------------------------------------

create table if not exists public.campaigns (
  id                          uuid primary key default gen_random_uuid(),
  user_id                     uuid not null references auth.users(id) on delete cascade,
  character_id                uuid not null references public.characters(id) on delete restrict,
  template_id                 text not null references public.story_templates(id),
  name                        text not null,
  status                      text not null default 'active'
                              check (status in ('active', 'completed', 'failed')),
  phase                       text not null default 'intro'
                              check (phase in ('intro', 'rising', 'climax', 'resolution')),
  turns_in_current_phase      integer not null default 0,
  turns_since_last_progress   integer not null default 0,
  total_turns                 integer not null default 0,
  created_at                  timestamptz not null default now(),
  last_played_at              timestamptz not null default now()
);

create index if not exists campaigns_user_idx on public.campaigns(user_id, last_played_at desc);
create index if not exists campaigns_character_idx on public.campaigns(character_id);

-- Per-campaign character snapshot (HP/MP/Stam/level/XP/inventory live HERE, not on characters)
create table if not exists public.campaign_characters (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null unique references public.campaigns(id) on delete cascade,
  character_id    uuid not null references public.characters(id) on delete restrict,
  level           integer not null default 1 check (level between 1 and 10),
  xp              integer not null default 0,
  hp              integer not null,
  max_hp          integer not null,
  resource_type   text not null check (resource_type in ('mp', 'stamina')),
  resource_current integer not null default 0,
  resource_max    integer not null default 0,
  ac              integer not null default 12,
  current_stats   jsonb not null,                             -- mirrors characters.stats at start, may level up
  status_effects  jsonb not null default '[]'::jsonb,         -- [{ key, label, expires_in_turns, magnitude }]
  base_element    text not null,
  defending_until_turn integer,                               -- combat: defend buff active up to this turn
  updated_at      timestamptz not null default now()
);

create index if not exists campaign_characters_character_idx on public.campaign_characters(character_id);

create trigger campaign_characters_touch_updated_at
  before update on public.campaign_characters
  for each row execute function public.touch_updated_at();

create table if not exists public.campaign_inventory (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references public.campaigns(id) on delete cascade,
  name         text not null,
  qty          integer not null default 1 check (qty >= 0),
  description  text not null default '',
  element      text not null default 'neutral',
  item_type    text not null check (item_type in ('weapon', 'armor', 'consumable', 'misc')),
  metadata     jsonb not null default '{}'::jsonb
);

create index if not exists campaign_inventory_campaign_idx on public.campaign_inventory(campaign_id);

create table if not exists public.campaign_skills (
  id              uuid primary key default gen_random_uuid(),
  campaign_id     uuid not null references public.campaigns(id) on delete cascade,
  skill_id        text not null references public.skills(id),
  learned_at_turn integer not null default 0,
  unique (campaign_id, skill_id)
);

create index if not exists campaign_skills_campaign_idx on public.campaign_skills(campaign_id);

create table if not exists public.campaign_bosses (
  id                uuid primary key default gen_random_uuid(),
  campaign_id       uuid not null references public.campaigns(id) on delete cascade,
  template_boss_id  uuid not null references public.template_bosses(id),
  status            text not null default 'unencountered'
                    check (status in ('unencountered', 'encountered', 'defeated')),
  current_hp        integer,
  defeated_at       timestamptz,
  unique (campaign_id, template_boss_id)
);

create index if not exists campaign_bosses_campaign_idx on public.campaign_bosses(campaign_id);

create table if not exists public.campaign_side_missions (
  id                          uuid primary key default gen_random_uuid(),
  campaign_id                 uuid not null references public.campaigns(id) on delete cascade,
  template_side_mission_id    uuid not null references public.template_side_missions(id),
  status                      text not null default 'active'
                              check (status in ('active', 'completed', 'failed')),
  current_step                integer not null default 0,
  started_at                  timestamptz not null default now(),
  completed_at                timestamptz,
  unique (campaign_id, template_side_mission_id)
);

create index if not exists campaign_side_missions_campaign_idx on public.campaign_side_missions(campaign_id);

----------------------------------------------------------------------
-- Combat
----------------------------------------------------------------------

create table if not exists public.combat_encounters (
  id                    uuid primary key default gen_random_uuid(),
  campaign_id           uuid not null references public.campaigns(id) on delete cascade,
  status                text not null default 'active'
                        check (status in ('active', 'won', 'lost', 'fled')),
  turn_order            jsonb not null default '[]'::jsonb,    -- [{ kind: 'player'|'enemy', id, initiative }]
  current_actor_index   integer not null default 0,
  round_number          integer not null default 1,
  started_at            timestamptz not null default now(),
  ended_at              timestamptz
);

create index if not exists combat_encounters_campaign_idx on public.combat_encounters(campaign_id, status);

create table if not exists public.combat_enemies (
  id                  uuid primary key default gen_random_uuid(),
  encounter_id        uuid not null references public.combat_encounters(id) on delete cascade,
  name                text not null,
  archetype           text not null check (archetype in ('aggressive', 'tactical', 'boss')),
  element             text not null default 'neutral',
  hp                  integer not null,
  max_hp              integer not null,
  ac                  integer not null,
  base_damage         integer not null,
  attack_dice         text not null default 'd6',
  skills              jsonb not null default '[]'::jsonb,      -- [{ name, dice, element, requires_llm_narration }]
  is_boss             boolean not null default false,
  template_boss_id    uuid references public.template_bosses(id),
  status_effects      jsonb not null default '[]'::jsonb
);

create index if not exists combat_enemies_encounter_idx on public.combat_enemies(encounter_id);

----------------------------------------------------------------------
-- Conversation history & memory
----------------------------------------------------------------------

create table if not exists public.messages (
  id                      uuid primary key default gen_random_uuid(),
  campaign_id             uuid not null references public.campaigns(id) on delete cascade,
  role                    text not null check (role in ('player', 'dm', 'system')),
  content                 text not null,
  situation_type          text check (situation_type in ('dialog', 'exploration', 'combat', 'transition')),
  options                 jsonb not null default '[]'::jsonb,
  selected_option_id      text,
  was_cheap_resolve       boolean not null default false,
  requires_roll           jsonb,
  state_changes_applied   jsonb not null default '[]'::jsonb,
  prompt_tokens           integer,
  completion_tokens       integer,
  pivotal_moment          boolean not null default false,
  created_at              timestamptz not null default now()
);

create index if not exists messages_campaign_idx on public.messages(campaign_id, created_at);

create table if not exists public.world_memory (
  id                      uuid primary key default gen_random_uuid(),
  campaign_id             uuid not null unique references public.campaigns(id) on delete cascade,
  summary                 text not null default '',
  covers_message_count    integer not null default 0,
  updated_at              timestamptz not null default now()
);

create trigger world_memory_touch_updated_at
  before update on public.world_memory
  for each row execute function public.touch_updated_at();

----------------------------------------------------------------------
-- Dice
----------------------------------------------------------------------

create table if not exists public.pending_rolls (
  id                    uuid primary key default gen_random_uuid(),
  campaign_id           uuid not null references public.campaigns(id) on delete cascade,
  message_id            uuid references public.messages(id) on delete set null,
  dice                  text not null check (dice in ('d20', 'd6', 'd100')),
  purpose               text not null,
  dc                    integer not null,
  modifier_stat         text check (modifier_stat in ('STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA')),
  llm_call_1_response   jsonb not null,
  created_at            timestamptz not null default now(),
  resolved_at           timestamptz
);

create index if not exists pending_rolls_campaign_idx on public.pending_rolls(campaign_id, resolved_at);

create table if not exists public.dice_rolls (
  id            uuid primary key default gen_random_uuid(),
  campaign_id   uuid not null references public.campaigns(id) on delete cascade,
  dice          text not null check (dice in ('d20', 'd6', 'd100')),
  raw_result    integer not null,
  modifier      integer not null default 0,
  total         integer not null,
  dc            integer not null,
  outcome       text not null check (outcome in ('critical_success', 'success', 'fail', 'critical_fail')),
  purpose       text not null,
  created_at    timestamptz not null default now()
);

create index if not exists dice_rolls_campaign_idx on public.dice_rolls(campaign_id, created_at);
