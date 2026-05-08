-- Add the Bard class.
-- Originally cut from the v1 seed because we didn't have art for it; the
-- portraits ship in `assets/images/avatars/bard_*.png` so we wire the
-- class up here. Skills get their own IDs so localized art can drop into
-- `assets/images/skills/` later without renames.
--
-- Idempotent + schema-aware: tables were moved from `public` to
-- `dungeonku` in 20260507000000_move_to_dungeonku_schema.sql, so we pick
-- whichever schema currently owns the tables. Re-running this migration
-- on a populated DB is safe (every insert uses `on conflict do nothing`).

do $mig$
declare
  classes_table  text;
  avatars_table  text;
  skills_table   text;
begin
  -- Resolve target schema (dungeonku in production; public on legacy clones).
  if    to_regclass('dungeonku.class_definitions') is not null then classes_table := 'dungeonku.class_definitions';
  elsif to_regclass('public.class_definitions')    is not null then classes_table := 'public.class_definitions';
  else  return; -- table doesn't exist yet — nothing to seed
  end if;

  if    to_regclass('dungeonku.avatar_templates') is not null then avatars_table := 'dungeonku.avatar_templates';
  elsif to_regclass('public.avatar_templates')    is not null then avatars_table := 'public.avatar_templates';
  end if;

  if    to_regclass('dungeonku.skills') is not null then skills_table := 'dungeonku.skills';
  elsif to_regclass('public.skills')    is not null then skills_table := 'public.skills';
  end if;

  -- ----- Bard class definition -----
  execute format($sql$
    insert into %s
      (id, name, description, base_element_default, resource_type,
       starting_hp, starting_resource, starting_ac, base_stats,
       starting_skills, level_progression, notes, sort_order)
    values
      ('bard', 'Bard',
        'Wandering performer-arcanist. Sings the party through danger and turns words into weapons.',
        'neutral', 'stamina', 22, 28, 12,
        '{"STR": 10, "DEX": 13, "CON": 12, "INT": 12, "WIS": 12, "CHA": 16}'::jsonb,
        '["inspire", "discordant_note"]'::jsonb,
        '{"3": ["lullaby"], "5": ["crescendo"], "7": ["finale"]}'::jsonb,
        'CHA-driven hybrid. Buffs allies, debuffs foes, fills gaps in any party.',
        70)
    on conflict (id) do nothing;
  $sql$, classes_table);

  -- ----- Bard avatars (5 portraits, point straight at bundled assets) -----
  if avatars_table is not null then
    execute format($sql$
      insert into %s (id, display_name, image_url, class_filter, sort_order)
      values
        ('bard_01', 'Lute-Bound Wanderer', 'assets/images/avatars/bard_01.png', '["bard"]'::jsonb, 70),
        ('bard_02', 'Painted Player',      'assets/images/avatars/bard_02.png', '["bard"]'::jsonb, 71),
        ('bard_03', 'Coin-Singer',         'assets/images/avatars/bard_03.png', '["bard"]'::jsonb, 72),
        ('bard_04', 'Hedge-Bard',          'assets/images/avatars/bard_04.png', '["bard"]'::jsonb, 73),
        ('bard_05', 'Twilight Crooner',    'assets/images/avatars/bard_05.png', '["bard"]'::jsonb, 74)
      on conflict (id) do nothing;
    $sql$, avatars_table);
  end if;

  -- ----- Bard skills (2 starting + 3 level unlocks). CHA-modified. -----
  if skills_table is not null then
    execute format($sql$
      insert into %s
        (id, name, description, element, kind, cost_type, cost_amount, dice,
         modifier_stat, base_damage_or_effect, available_to_classes,
         required_level, is_basic_attack, sort_order)
      values
        ('inspire', 'Inspire',
          'A short verse that lifts your allies\u2019 spirits. Next ally check gains advantage.',
          'neutral', 'buff', 'stamina', 3, null, 'CHA',
          '{"party_buff": {"next_check_advantage": true, "duration": 2}}'::jsonb,
          '["bard"]'::jsonb, 1, false, 70),

        ('discordant_note', 'Discordant Note',
          'A piercing chord that rattles bones and buckles armor.',
          'neutral', 'attack', 'stamina', 4, 'd6', 'CHA',
          '{"status_on_hit": {"key": "rattled", "duration": 1, "ac_penalty": 1}}'::jsonb,
          '["bard"]'::jsonb, 1, false, 71),

        ('lullaby', 'Lullaby',
          'A slow, drowsing melody. One foe must save against sleep.',
          'neutral', 'debuff', 'stamina', 5, null, 'CHA',
          '{"status_on_hit": {"key": "sleeping", "duration": 2}, "save_dc_stat": "CHA"}'::jsonb,
          '["bard"]'::jsonb, 3, false, 72),

        ('crescendo', 'Crescendo',
          'A building, sweeping refrain that hits every nearby enemy.',
          'neutral', 'attack', 'stamina', 7, '2d6', 'CHA',
          '{"aoe": true}'::jsonb,
          '["bard"]'::jsonb, 5, false, 73),

        ('finale', 'Finale',
          'A song of endings. Heals the party and grants a crit-window for one round.',
          'neutral', 'buff', 'stamina', 8, null, 'CHA',
          '{"party_heal": "d8", "party_buff": {"crit_threshold": 17, "duration": 1}}'::jsonb,
          '["bard"]'::jsonb, 7, false, 74)
      on conflict (id) do nothing;
    $sql$, skills_table);
  end if;
end
$mig$;
