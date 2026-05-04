-- Row Level Security
--
-- Strategy:
--   * Reference data (class_definitions, skills, avatar_templates, story_templates, template_bosses,
--     template_side_missions) is public-read for any authenticated user, no writes.
--   * User-owned tables: clients can read+write their own rows, scoped via auth.uid().
--   * Campaign sub-tables (campaign_characters, inventory, bosses, etc.): clients SELECT only.
--     Edge Functions use the service-role key and bypass RLS for mutations, so all game-state
--     transitions remain server-authoritative.
--   * Messages, pending_rolls, dice_rolls: SELECT only from clients. Inserts happen via Edge Functions.

----------------------------------------------------------------------
-- Helper: is the caller the owner of the given campaign?
----------------------------------------------------------------------
create or replace function public.is_campaign_owner(p_campaign_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.campaigns
    where id = p_campaign_id and user_id = auth.uid()
  );
$$;

----------------------------------------------------------------------
-- Reference data: public read
----------------------------------------------------------------------
alter table public.class_definitions enable row level security;
create policy "class_definitions_read" on public.class_definitions
  for select to authenticated using (true);

alter table public.skills enable row level security;
create policy "skills_read" on public.skills
  for select to authenticated using (true);

alter table public.avatar_templates enable row level security;
create policy "avatar_templates_read" on public.avatar_templates
  for select to authenticated using (true);

alter table public.story_templates enable row level security;
create policy "story_templates_read" on public.story_templates
  for select to authenticated using (is_active);

alter table public.template_bosses enable row level security;
create policy "template_bosses_read" on public.template_bosses
  for select to authenticated using (true);

alter table public.template_side_missions enable row level security;
create policy "template_side_missions_read" on public.template_side_missions
  for select to authenticated using (true);

----------------------------------------------------------------------
-- profiles
----------------------------------------------------------------------
alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select to authenticated using (id = auth.uid());

create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (id = auth.uid());

create policy "profiles_update_own" on public.profiles
  for update to authenticated using (id = auth.uid());

----------------------------------------------------------------------
-- characters (full CRUD by owner; max-3 enforced by trigger)
----------------------------------------------------------------------
alter table public.characters enable row level security;

create policy "characters_select_own" on public.characters
  for select to authenticated using (user_id = auth.uid());

create policy "characters_insert_own" on public.characters
  for insert to authenticated with check (user_id = auth.uid());

create policy "characters_update_own" on public.characters
  for update to authenticated using (user_id = auth.uid());

create policy "characters_delete_own" on public.characters
  for delete to authenticated using (user_id = auth.uid());

----------------------------------------------------------------------
-- campaigns (clients can create + delete + see + rename; gameplay state writes go via Edge Functions)
----------------------------------------------------------------------
alter table public.campaigns enable row level security;

create policy "campaigns_select_own" on public.campaigns
  for select to authenticated using (user_id = auth.uid());

create policy "campaigns_insert_own" on public.campaigns
  for insert to authenticated with check (user_id = auth.uid());

create policy "campaigns_update_own" on public.campaigns
  for update to authenticated using (user_id = auth.uid());

create policy "campaigns_delete_own" on public.campaigns
  for delete to authenticated using (user_id = auth.uid());

----------------------------------------------------------------------
-- Campaign sub-tables: SELECT only from clients. Mutations via service-role Edge Functions.
----------------------------------------------------------------------
alter table public.campaign_characters enable row level security;
create policy "campaign_characters_select_own" on public.campaign_characters
  for select to authenticated using (is_campaign_owner(campaign_id));
create policy "campaign_characters_insert_own" on public.campaign_characters
  for insert to authenticated with check (is_campaign_owner(campaign_id));

alter table public.campaign_inventory enable row level security;
create policy "campaign_inventory_select_own" on public.campaign_inventory
  for select to authenticated using (is_campaign_owner(campaign_id));

alter table public.campaign_skills enable row level security;
create policy "campaign_skills_select_own" on public.campaign_skills
  for select to authenticated using (is_campaign_owner(campaign_id));
create policy "campaign_skills_insert_own" on public.campaign_skills
  for insert to authenticated with check (is_campaign_owner(campaign_id));

alter table public.campaign_bosses enable row level security;
create policy "campaign_bosses_select_own" on public.campaign_bosses
  for select to authenticated using (is_campaign_owner(campaign_id));
create policy "campaign_bosses_insert_own" on public.campaign_bosses
  for insert to authenticated with check (is_campaign_owner(campaign_id));

alter table public.campaign_side_missions enable row level security;
create policy "campaign_side_missions_select_own" on public.campaign_side_missions
  for select to authenticated using (is_campaign_owner(campaign_id));

alter table public.combat_encounters enable row level security;
create policy "combat_encounters_select_own" on public.combat_encounters
  for select to authenticated using (is_campaign_owner(campaign_id));

alter table public.combat_enemies enable row level security;
create policy "combat_enemies_select_own" on public.combat_enemies
  for select to authenticated using (
    exists (
      select 1 from public.combat_encounters ce
      where ce.id = combat_enemies.encounter_id
        and is_campaign_owner(ce.campaign_id)
    )
  );

alter table public.messages enable row level security;
create policy "messages_select_own" on public.messages
  for select to authenticated using (is_campaign_owner(campaign_id));
create policy "messages_insert_own" on public.messages
  for insert to authenticated with check (is_campaign_owner(campaign_id));

alter table public.world_memory enable row level security;
create policy "world_memory_select_own" on public.world_memory
  for select to authenticated using (is_campaign_owner(campaign_id));

alter table public.pending_rolls enable row level security;
create policy "pending_rolls_select_own" on public.pending_rolls
  for select to authenticated using (is_campaign_owner(campaign_id));

alter table public.dice_rolls enable row level security;
create policy "dice_rolls_select_own" on public.dice_rolls
  for select to authenticated using (is_campaign_owner(campaign_id));
