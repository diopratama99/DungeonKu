-- =====================================================================
-- DungeonKu — Move from public to dungeonku schema
-- =====================================================================
-- Idempotent forward migration. Safe to re-run.
--
-- Strategy:
--   * MOVE: app-specific tables + their RLS policies + indexes + triggers
--   * COEXIST: profiles (shared with another app on this Supabase) — create
--     dungeonku.profiles fresh + backfill, leave public.profiles alone
--   * Functions: recreate in dungeonku schema with explicit search_path
--   * auth.users trigger: rename to on_auth_user_created_dungeonku so it
--     can coexist with other apps' signup hooks
-- =====================================================================


-- ---------------------------------------------------------------------
-- 2a. Schema
-- ---------------------------------------------------------------------
create schema if not exists dungeonku;


-- ---------------------------------------------------------------------
-- 2b. Drop legacy auth.users trigger BEFORE moving handle_new_user
--     so we can recreate with app-specific name afterwards.
-- ---------------------------------------------------------------------
drop trigger if exists on_auth_user_created            on auth.users;
drop trigger if exists on_auth_user_created_dungeonku  on auth.users;


-- ---------------------------------------------------------------------
-- 2c. Move tables from public → dungeonku (MOVE list)
--     RLS policies, indexes, constraints, table-level triggers ikut otomatis.
-- ---------------------------------------------------------------------
do $mv$
declare
  tbls text[] := array[
    'class_definitions',
    'skills',
    'avatar_templates',
    'story_templates',
    'template_bosses',
    'template_side_missions',
    'characters',
    'campaigns',
    'campaign_characters',
    'campaign_inventory',
    'campaign_skills',
    'campaign_bosses',
    'campaign_side_missions',
    'combat_encounters',
    'combat_enemies',
    'messages',
    'world_memory',
    'pending_rolls',
    'dice_rolls'
  ];
  t text;
begin
  foreach t in array tbls loop
    begin
      execute format('alter table if exists public.%I set schema dungeonku', t);
    exception
      when undefined_table     then null;  -- already moved or never existed
      when duplicate_table     then null;  -- already exists in target schema
      when invalid_schema_name then null;
    end;
  end loop;
end
$mv$;


-- ---------------------------------------------------------------------
-- 2d. COEXIST: dungeonku.profiles (kept separate from public.profiles
--     so the other app's profile schema is untouched).
-- ---------------------------------------------------------------------
create table if not exists dungeonku.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

alter table dungeonku.profiles enable row level security;

drop policy if exists "profiles_select_own" on dungeonku.profiles;
drop policy if exists "profiles_insert_own" on dungeonku.profiles;
drop policy if exists "profiles_update_own" on dungeonku.profiles;

create policy "profiles_select_own" on dungeonku.profiles
  for select to authenticated using (id = auth.uid());

create policy "profiles_insert_own" on dungeonku.profiles
  for insert to authenticated with check (id = auth.uid());

create policy "profiles_update_own" on dungeonku.profiles
  for update to authenticated using (id = auth.uid());

-- Backfill: bikin row untuk user existing yang belum punya (idempotent)
insert into dungeonku.profiles (id)
select u.id
from auth.users u
left join dungeonku.profiles p on p.id = u.id
where p.id is null;


-- ---------------------------------------------------------------------
-- 2e. Move existing functions to dungeonku schema (best-effort).
--     Aman re-run: kalau sudah dipindah / sudah ada di target → no-op.
-- ---------------------------------------------------------------------
do $mig$
declare
  fns text[] := array[
    'public.is_campaign_owner(uuid)',
    'public.enforce_character_limit()',
    'public.handle_new_user()'
    -- NOTE: public.touch_updated_at() sengaja TIDAK dipindah karena nama
    -- generic dan kemungkinan dipakai app lain. Kita create copy di
    -- dungeonku schema saja (lihat 2f).
  ];
  fn text;
begin
  foreach fn in array fns loop
    begin
      execute format('alter function %s set schema dungeonku', fn);
    exception
      when undefined_function  then null;
      when duplicate_function  then null;
      when invalid_schema_name then null;
    end;
  end loop;
end
$mig$;


-- ---------------------------------------------------------------------
-- 2f. Recreate function bodies dengan referensi schema-qualified
--     dan search_path eksplisit (best practice untuk security definer).
-- ---------------------------------------------------------------------
create or replace function dungeonku.is_campaign_owner(p_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = dungeonku, public, pg_temp
as $$
  select exists (
    select 1 from dungeonku.campaigns
    where id = p_campaign_id and user_id = auth.uid()
  );
$$;

create or replace function dungeonku.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = dungeonku, public, pg_temp
as $$
begin
  insert into dungeonku.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function dungeonku.enforce_character_limit()
returns trigger
language plpgsql
set search_path = dungeonku, public, pg_temp
as $$
begin
  if (select count(*) from dungeonku.characters where user_id = new.user_id) >= 3 then
    raise exception 'Maximum of 3 characters per user reached';
  end if;
  return new;
end;
$$;

create or replace function dungeonku.touch_updated_at()
returns trigger
language plpgsql
set search_path = dungeonku, public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;


-- ---------------------------------------------------------------------
-- 2g. Recreate trigger di auth.users dengan nama app-specific.
--     Multiple apps boleh coexist: Postgres fire trigger berdasar nama alfabetis.
-- ---------------------------------------------------------------------
create trigger on_auth_user_created_dungeonku
  after insert on auth.users
  for each row execute function dungeonku.handle_new_user();


-- ---------------------------------------------------------------------
-- 2h. Recreate table-level triggers untuk pointing ke dungeonku.* functions
--     (kalau sebelumnya pointing ke public.*, biar eksplisit & konsisten).
-- ---------------------------------------------------------------------

-- characters
drop trigger if exists enforce_character_limit_trigger on dungeonku.characters;
create trigger enforce_character_limit_trigger
  before insert on dungeonku.characters
  for each row execute function dungeonku.enforce_character_limit();

drop trigger if exists characters_touch_updated_at on dungeonku.characters;
create trigger characters_touch_updated_at
  before update on dungeonku.characters
  for each row execute function dungeonku.touch_updated_at();

-- profiles
drop trigger if exists profiles_touch_updated_at on dungeonku.profiles;
create trigger profiles_touch_updated_at
  before update on dungeonku.profiles
  for each row execute function dungeonku.touch_updated_at();

-- campaign_characters
drop trigger if exists campaign_characters_touch_updated_at on dungeonku.campaign_characters;
create trigger campaign_characters_touch_updated_at
  before update on dungeonku.campaign_characters
  for each row execute function dungeonku.touch_updated_at();

-- world_memory
drop trigger if exists world_memory_touch_updated_at on dungeonku.world_memory;
create trigger world_memory_touch_updated_at
  before update on dungeonku.world_memory
  for each row execute function dungeonku.touch_updated_at();


-- ---------------------------------------------------------------------
-- 2h-2. Recreate RLS policies yang reference is_campaign_owner.
--       Setelah tabel pindah, function reference unqualified akan resolve
--       via search_path. Kita explicitly point ke dungeonku.is_campaign_owner.
-- ---------------------------------------------------------------------

-- campaign_characters
drop policy if exists "campaign_characters_select_own" on dungeonku.campaign_characters;
drop policy if exists "campaign_characters_insert_own" on dungeonku.campaign_characters;
create policy "campaign_characters_select_own" on dungeonku.campaign_characters
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));
create policy "campaign_characters_insert_own" on dungeonku.campaign_characters
  for insert to authenticated with check (dungeonku.is_campaign_owner(campaign_id));

-- campaign_inventory
drop policy if exists "campaign_inventory_select_own" on dungeonku.campaign_inventory;
create policy "campaign_inventory_select_own" on dungeonku.campaign_inventory
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));

-- campaign_skills
drop policy if exists "campaign_skills_select_own" on dungeonku.campaign_skills;
drop policy if exists "campaign_skills_insert_own" on dungeonku.campaign_skills;
create policy "campaign_skills_select_own" on dungeonku.campaign_skills
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));
create policy "campaign_skills_insert_own" on dungeonku.campaign_skills
  for insert to authenticated with check (dungeonku.is_campaign_owner(campaign_id));

-- campaign_bosses
drop policy if exists "campaign_bosses_select_own" on dungeonku.campaign_bosses;
drop policy if exists "campaign_bosses_insert_own" on dungeonku.campaign_bosses;
create policy "campaign_bosses_select_own" on dungeonku.campaign_bosses
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));
create policy "campaign_bosses_insert_own" on dungeonku.campaign_bosses
  for insert to authenticated with check (dungeonku.is_campaign_owner(campaign_id));

-- campaign_side_missions
drop policy if exists "campaign_side_missions_select_own" on dungeonku.campaign_side_missions;
create policy "campaign_side_missions_select_own" on dungeonku.campaign_side_missions
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));

-- combat_encounters
drop policy if exists "combat_encounters_select_own" on dungeonku.combat_encounters;
create policy "combat_encounters_select_own" on dungeonku.combat_encounters
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));

-- combat_enemies (subquery references combat_encounters)
drop policy if exists "combat_enemies_select_own" on dungeonku.combat_enemies;
create policy "combat_enemies_select_own" on dungeonku.combat_enemies
  for select to authenticated using (
    exists (
      select 1 from dungeonku.combat_encounters ce
      where ce.id = combat_enemies.encounter_id
        and dungeonku.is_campaign_owner(ce.campaign_id)
    )
  );

-- messages
drop policy if exists "messages_select_own" on dungeonku.messages;
drop policy if exists "messages_insert_own" on dungeonku.messages;
create policy "messages_select_own" on dungeonku.messages
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));
create policy "messages_insert_own" on dungeonku.messages
  for insert to authenticated with check (dungeonku.is_campaign_owner(campaign_id));

-- world_memory
drop policy if exists "world_memory_select_own" on dungeonku.world_memory;
create policy "world_memory_select_own" on dungeonku.world_memory
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));

-- pending_rolls
drop policy if exists "pending_rolls_select_own" on dungeonku.pending_rolls;
create policy "pending_rolls_select_own" on dungeonku.pending_rolls
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));

-- dice_rolls
drop policy if exists "dice_rolls_select_own" on dungeonku.dice_rolls;
create policy "dice_rolls_select_own" on dungeonku.dice_rolls
  for select to authenticated using (dungeonku.is_campaign_owner(campaign_id));


-- ---------------------------------------------------------------------
-- 2i. Grants & default privileges
-- ---------------------------------------------------------------------
grant usage on schema dungeonku to anon, authenticated, service_role;

grant all on all tables    in schema dungeonku to anon, authenticated, service_role;
grant all on all sequences in schema dungeonku to anon, authenticated, service_role;
grant all on all functions in schema dungeonku to anon, authenticated, service_role;

alter default privileges in schema dungeonku
  grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema dungeonku
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema dungeonku
  grant all on functions to anon, authenticated, service_role;
