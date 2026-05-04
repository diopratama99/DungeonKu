-- Seed: skills catalog. ~28 entries covering the 6 classes + 1 universal basic_attack.
-- Cost rule: basic_attack is free, every class skill costs MP (casters) or Stamina (martials).
-- modifier_stat is the attribute used for the attack roll (and, when relevant, damage bonus).

insert into public.skills
  (id, name, description, element, kind, cost_type, cost_amount, dice, modifier_stat, base_damage_or_effect, available_to_classes, required_level, is_basic_attack, sort_order)
values
  -- Universal
  ('basic_attack', 'Basic Attack', 'A simple swing or strike with your equipped weapon.', 'neutral', 'attack', 'free', 0, 'd6', 'STR',
    '{"description": "Standard attack with equipped weapon."}'::jsonb,
    '[]'::jsonb, 1, true, 0),

  -- Warrior
  ('power_strike', 'Power Strike',
    'A heavy two-handed swing aimed to break guards.',
    'neutral', 'attack', 'stamina', 4, 'd8', 'STR',
    '{"damage_bonus": 2}'::jsonb, '["warrior"]'::jsonb, 1, false, 10),

  ('shield_bash', 'Shield Bash',
    'Slam with your shield to dent armor and stagger the foe.',
    'neutral', 'attack', 'stamina', 3, 'd6', 'STR',
    '{"status_on_hit": {"key": "stunned", "duration": 1}}'::jsonb,
    '["warrior"]'::jsonb, 1, false, 11),

  ('whirlwind', 'Whirlwind',
    'A reckless spin that strikes every nearby enemy.',
    'neutral', 'attack', 'stamina', 8, '2d6', 'STR',
    '{"aoe": true}'::jsonb, '["warrior"]'::jsonb, 3, false, 12),

  ('challenging_roar', 'Challenging Roar',
    'A bellow that draws every enemy''s eye and bolsters your stance.',
    'neutral', 'buff', 'stamina', 5, null, null,
    '{"self_buff": {"ac_bonus": 2, "duration": 3}, "taunt": {"duration": 2}}'::jsonb,
    '["warrior"]'::jsonb, 5, false, 13),

  -- Rogue
  ('backstab', 'Backstab',
    'Strike a vulnerable point. Devastating against unaware foes.',
    'neutral', 'attack', 'stamina', 4, 'd6', 'DEX',
    '{"damage_bonus_if_unaware": 5}'::jsonb, '["rogue"]'::jsonb, 1, false, 20),

  ('evasive_step', 'Evasive Step',
    'A reading of the foe''s tells; you slip just out of reach.',
    'neutral', 'buff', 'stamina', 3, null, null,
    '{"self_buff": {"ac_bonus": 3, "duration": 1}}'::jsonb,
    '["rogue"]'::jsonb, 1, false, 21),

  ('poison_blade', 'Poison Blade',
    'A coated edge that festers in the wound.',
    'neutral', 'attack', 'stamina', 5, 'd6', 'DEX',
    '{"status_on_hit": {"key": "poisoned", "duration": 3, "tick_damage": 2}}'::jsonb,
    '["rogue"]'::jsonb, 3, false, 22),

  ('shadow_strike', 'Shadow Strike',
    'A blink of darkness, then your blade is in their ribs.',
    'dark', 'attack', 'stamina', 6, 'd8', 'DEX',
    '{"crit_threshold": 18}'::jsonb, '["rogue"]'::jsonb, 5, false, 23),

  -- Mage (element-flexible: elemental_blast and elemental_storm use the character''s base_element)
  ('arcane_bolt', 'Arcane Bolt',
    'A pure missile of unaligned magical force.',
    'neutral', 'attack', 'mp', 3, 'd6', 'INT',
    '{}'::jsonb, '["mage"]'::jsonb, 1, false, 30),

  ('elemental_blast', 'Elemental Blast',
    'A focused gout of your attuned element.',
    'fire', 'attack', 'mp', 5, 'd8', 'INT',
    '{"use_caster_element": true}'::jsonb,
    '["mage"]'::jsonb, 1, false, 31),

  ('ward', 'Ward',
    'A weave of protective sigils.',
    'neutral', 'buff', 'mp', 4, null, null,
    '{"self_buff": {"ac_bonus": 3, "duration": 2}}'::jsonb,
    '["mage"]'::jsonb, 3, false, 32),

  ('elemental_storm', 'Elemental Storm',
    'You unleash your element across the battlefield.',
    'fire', 'attack', 'mp', 10, '2d8', 'INT',
    '{"use_caster_element": true, "aoe": true}'::jsonb,
    '["mage"]'::jsonb, 5, false, 33),

  -- Priest
  ('mend_wounds', 'Mend Wounds',
    'Light pours into broken flesh.',
    'light', 'heal', 'mp', 4, '2d6', 'WIS',
    '{"heal": true, "heal_bonus_stat": "WIS"}'::jsonb,
    '["priest"]'::jsonb, 1, false, 40),

  ('holy_smite', 'Holy Smite',
    'A column of judgement falls from above.',
    'light', 'attack', 'mp', 5, 'd8', 'WIS',
    '{}'::jsonb, '["priest"]'::jsonb, 1, false, 41),

  ('bless', 'Bless',
    'A whispered prayer that steadies the hand.',
    'light', 'buff', 'mp', 4, null, null,
    '{"self_buff": {"attack_bonus": 2, "duration": 3}}'::jsonb,
    '["priest"]'::jsonb, 3, false, 42),

  ('divine_radiance', 'Divine Radiance',
    'A burst of cleansing light, brightest against shadow.',
    'light', 'attack', 'mp', 8, '2d8', 'WIS',
    '{"aoe": true}'::jsonb, '["priest"]'::jsonb, 5, false, 43),

  -- Ranger
  ('aimed_shot', 'Aimed Shot',
    'You take a breath and let an arrow fly true.',
    'wind', 'attack', 'stamina', 4, 'd8', 'DEX',
    '{}'::jsonb, '["ranger"]'::jsonb, 1, false, 50),

  ('snare', 'Snare',
    'A coil of wire and bramble at the foe''s feet.',
    'wind', 'debuff', 'stamina', 3, 'd4', 'DEX',
    '{"status_on_hit": {"key": "rooted", "duration": 2}}'::jsonb,
    '["ranger"]'::jsonb, 1, false, 51),

  ('multi_shot', 'Multi Shot',
    'Two arrows nocked, two foes pierced.',
    'wind', 'attack', 'stamina', 6, '2d6', 'DEX',
    '{"hits_two_targets": true}'::jsonb,
    '["ranger"]'::jsonb, 3, false, 52),

  ('hawk_eye', 'Hawk Eye',
    'Time slows. The next shot finds its mark.',
    'wind', 'buff', 'stamina', 5, null, null,
    '{"self_buff": {"next_attack_bonus": 5, "guaranteed_hit": true}}'::jsonb,
    '["ranger"]'::jsonb, 5, false, 53),

  -- Blacksmith
  ('forge_strike', 'Forge Strike',
    'A measured hammer blow that channels heat from the haft.',
    'neutral', 'attack', 'stamina', 4, 'd8', 'STR',
    '{"can_imbue_element": true}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 60),

  ('temper_armor', 'Temper Armor',
    'You re-set the rivets on your plates mid-fight.',
    'neutral', 'buff', 'stamina', 4, null, null,
    '{"self_buff": {"ac_bonus": 3, "duration": 2}}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 61),

  ('blazing_hammer', 'Blazing Hammer',
    'You channel forge heat into the head of your hammer.',
    'fire', 'attack', 'stamina', 6, 'd8', 'STR',
    '{}'::jsonb, '["blacksmith"]'::jsonb, 3, false, 62),

  ('runic_strike', 'Runic Strike',
    'A blow that sears its mark deeper if old wounds linger.',
    'neutral', 'attack', 'stamina', 7, 'd10', 'STR',
    '{"bonus_damage_if_status": 4}'::jsonb,
    '["blacksmith"]'::jsonb, 5, false, 63);
