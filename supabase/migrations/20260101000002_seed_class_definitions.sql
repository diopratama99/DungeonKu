-- Seed: 6 base classes for MVP.
-- Resource maxes follow the "Resources: MP & Stamina" table in the product spec.
-- starting_ac values are tuned for the "Very Hard" baseline (small-enemy DC 14+, boss DC 18+).

insert into public.class_definitions
  (id, name, description, base_element_default, resource_type, starting_hp, starting_resource, starting_ac, base_stats, starting_skills, level_progression, notes, sort_order)
values
  ('warrior', 'Warrior',
    'Front-line melee fighter. Heavy armor, blunt weapons, weathers blows others can''t.',
    'neutral', 'stamina', 30, 30, 14,
    '{"STR": 16, "DEX": 12, "CON": 14, "INT": 10, "WIS": 10, "CHA": 11}'::jsonb,
    '["power_strike", "shield_bash"]'::jsonb,
    '{"3": ["whirlwind"], "5": ["challenging_roar"], "7": ["earthshatter"]}'::jsonb,
    'Tank archetype. High HP, high STR.', 10),

  ('rogue', 'Rogue',
    'Quick, sly, deadly. Lives in the shadow and strikes vital points.',
    'neutral', 'stamina', 22, 25, 13,
    '{"STR": 11, "DEX": 16, "CON": 12, "INT": 13, "WIS": 12, "CHA": 12}'::jsonb,
    '["backstab", "evasive_step"]'::jsonb,
    '{"3": ["poison_blade"], "5": ["shadow_strike"], "7": ["vanish"]}'::jsonb,
    'High DEX. Crit-based DPS.', 20),

  ('mage', 'Mage',
    'Channels elemental fury. Frail body, devastating magic.',
    'fire', 'mp', 18, 30, 11,
    '{"STR": 9, "DEX": 12, "CON": 11, "INT": 16, "WIS": 14, "CHA": 12}'::jsonb,
    '["arcane_bolt", "elemental_blast"]'::jsonb,
    '{"3": ["ward"], "5": ["elemental_storm"], "7": ["mana_surge"]}'::jsonb,
    'Player picks base element from Fire/Water/Wind/Earth/Lightning/Dark at creation. The default of fire is overridden in code.',
    30),

  ('priest', 'Priest',
    'Servant of the light. Mends wounds, smites the corrupt.',
    'light', 'mp', 22, 25, 12,
    '{"STR": 11, "DEX": 10, "CON": 13, "INT": 12, "WIS": 16, "CHA": 14}'::jsonb,
    '["mend_wounds", "holy_smite"]'::jsonb,
    '{"3": ["bless"], "5": ["divine_radiance"], "7": ["sanctuary"]}'::jsonb,
    'Light element is exclusive to Priest.', 40),

  ('ranger', 'Ranger',
    'Wandering hunter. Tracks beasts and looses arrows from afar.',
    'wind', 'stamina', 24, 25, 13,
    '{"STR": 12, "DEX": 16, "CON": 13, "INT": 11, "WIS": 14, "CHA": 11}'::jsonb,
    '["aimed_shot", "snare"]'::jsonb,
    '{"3": ["multi_shot"], "5": ["hawk_eye"], "7": ["wind_walk"]}'::jsonb,
    'Wind-attuned by trade. Ranged DPS.', 50),

  ('blacksmith', 'Blacksmith',
    'Forge-toughened artisan. Wields a heavy hammer and tempers gear on the road.',
    'neutral', 'stamina', 28, 35, 14,
    '{"STR": 15, "DEX": 11, "CON": 15, "INT": 12, "WIS": 11, "CHA": 11}'::jsonb,
    '["forge_strike", "temper_armor"]'::jsonb,
    '{"3": ["blazing_hammer"], "5": ["runic_strike"], "7": ["anvil_drop"]}'::jsonb,
    'Durable hybrid. Can imbue weapons with elemental damage on the fly.', 60);
