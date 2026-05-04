-- Seed: ~30 avatar templates (5 per class).
-- We use placehold.co URLs so the app is runnable immediately without any binary asset bundle.
-- Replace these with real pixel-art portraits later by updating image_url; the slug ids are stable.

insert into public.avatar_templates (id, display_name, image_url, class_filter, sort_order) values
  ('warrior_01', 'Bastion of Iron',     'https://placehold.co/256x256/3a2417/d4af37/png?text=Warrior+1', '["warrior"]'::jsonb, 10),
  ('warrior_02', 'Crimson Captain',     'https://placehold.co/256x256/3a2417/c64545/png?text=Warrior+2', '["warrior"]'::jsonb, 11),
  ('warrior_03', 'Hill-Born Brawler',   'https://placehold.co/256x256/3a2417/8a6d3b/png?text=Warrior+3', '["warrior"]'::jsonb, 12),
  ('warrior_04', 'Veiled Sentinel',     'https://placehold.co/256x256/3a2417/4f6d8c/png?text=Warrior+4', '["warrior"]'::jsonb, 13),
  ('warrior_05', 'Shieldmaiden',        'https://placehold.co/256x256/3a2417/d4af37/png?text=Warrior+5', '["warrior"]'::jsonb, 14),

  ('rogue_01',   'Alley Wraith',        'https://placehold.co/256x256/1a1a24/9aa0b8/png?text=Rogue+1',   '["rogue"]'::jsonb, 20),
  ('rogue_02',   'Smiling Knife',       'https://placehold.co/256x256/1a1a24/c64545/png?text=Rogue+2',   '["rogue"]'::jsonb, 21),
  ('rogue_03',   'Hooded Wanderer',     'https://placehold.co/256x256/1a1a24/3b6e58/png?text=Rogue+3',   '["rogue"]'::jsonb, 22),
  ('rogue_04',   'Coin-Cutter',         'https://placehold.co/256x256/1a1a24/d4af37/png?text=Rogue+4',   '["rogue"]'::jsonb, 23),
  ('rogue_05',   'Twilight Dancer',     'https://placehold.co/256x256/1a1a24/8a4ec6/png?text=Rogue+5',   '["rogue"]'::jsonb, 24),

  ('mage_01',    'Tower Apprentice',    'https://placehold.co/256x256/1d2440/c64545/png?text=Mage+1',    '["mage"]'::jsonb, 30),
  ('mage_02',    'Hedge Witch',         'https://placehold.co/256x256/1d2440/3b6e58/png?text=Mage+2',    '["mage"]'::jsonb, 31),
  ('mage_03',    'Stormcaller',         'https://placehold.co/256x256/1d2440/e8c66a/png?text=Mage+3',    '["mage"]'::jsonb, 32),
  ('mage_04',    'Glacier Adept',       'https://placehold.co/256x256/1d2440/4f8cb0/png?text=Mage+4',    '["mage"]'::jsonb, 33),
  ('mage_05',    'Ash-Marked Conjurer', 'https://placehold.co/256x256/1d2440/8a4ec6/png?text=Mage+5',    '["mage"]'::jsonb, 34),

  ('priest_01',  'Cloistered Acolyte',  'https://placehold.co/256x256/3a3520/f4ecd0/png?text=Priest+1',  '["priest"]'::jsonb, 40),
  ('priest_02',  'Wandering Healer',    'https://placehold.co/256x256/3a3520/d4af37/png?text=Priest+2',  '["priest"]'::jsonb, 41),
  ('priest_03',  'Gilded Speaker',      'https://placehold.co/256x256/3a3520/e8c66a/png?text=Priest+3',  '["priest"]'::jsonb, 42),
  ('priest_04',  'Mountain Hermit',     'https://placehold.co/256x256/3a3520/c8b885/png?text=Priest+4',  '["priest"]'::jsonb, 43),
  ('priest_05',  'Field Chaplain',      'https://placehold.co/256x256/3a3520/8a6d3b/png?text=Priest+5',  '["priest"]'::jsonb, 44),

  ('ranger_01',  'Forest Watcher',      'https://placehold.co/256x256/1f3022/3b6e58/png?text=Ranger+1',  '["ranger"]'::jsonb, 50),
  ('ranger_02',  'Hawk-Bound Scout',    'https://placehold.co/256x256/1f3022/d4af37/png?text=Ranger+2',  '["ranger"]'::jsonb, 51),
  ('ranger_03',  'Marshlander',         'https://placehold.co/256x256/1f3022/8a6d3b/png?text=Ranger+3',  '["ranger"]'::jsonb, 52),
  ('ranger_04',  'Frostfen Tracker',    'https://placehold.co/256x256/1f3022/4f8cb0/png?text=Ranger+4',  '["ranger"]'::jsonb, 53),
  ('ranger_05',  'Sun-Browned Hunter',  'https://placehold.co/256x256/1f3022/e8c66a/png?text=Ranger+5',  '["ranger"]'::jsonb, 54),

  ('blacksmith_01', 'Forge-Hardened',   'https://placehold.co/256x256/24180c/d4af37/png?text=Smith+1',   '["blacksmith"]'::jsonb, 60),
  ('blacksmith_02', 'Cinder Apprentice','https://placehold.co/256x256/24180c/c64545/png?text=Smith+2',   '["blacksmith"]'::jsonb, 61),
  ('blacksmith_03', 'Anvil Singer',     'https://placehold.co/256x256/24180c/8a6d3b/png?text=Smith+3',   '["blacksmith"]'::jsonb, 62),
  ('blacksmith_04', 'Iron Wanderer',    'https://placehold.co/256x256/24180c/9aa0b8/png?text=Smith+4',   '["blacksmith"]'::jsonb, 63),
  ('blacksmith_05', 'Dwarvish Striker', 'https://placehold.co/256x256/24180c/e8c66a/png?text=Smith+5',   '["blacksmith"]'::jsonb, 64);
