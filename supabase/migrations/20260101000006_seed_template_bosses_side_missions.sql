-- Seed: bosses and side missions for each story template.
-- Boss tier mix per template aims for the spec's pacing rule:
--   intro→rising after 3 turns, rising→climax once ≥60% small + ≥50% medium defeated,
--   climax→resolution once big boss defeated.
-- HP/AC/damage values use the "Very Hard" baseline.

-- =============================================================
-- The Sunken Crown
-- =============================================================
insert into public.template_bosses
  (template_id, name, description, tier, element, hp, base_damage, ac, order_index, signature_moves)
values
  ('the_sunken_crown', 'Drowned Thrall Captain',
   'A waterlogged dwarven warrior, eyes lit faintly green, plate corroded green-black. He still commands two thralls.',
   'small', 'water', 28, 6, 14, 10,
   '[{"name":"Rust-Choked Lunge","dice":"d6","element":"water","requires_llm_narration":false}]'::jsonb),

  ('the_sunken_crown', 'The Cinderforge Spirit',
   'A spirit bound to the great forge. It speaks in the voice of struck iron and throws ribbons of flame across the foundry.',
   'medium', 'fire', 60, 10, 16, 20,
   '[{"name":"Forge-Belch","dice":"2d6","element":"fire","requires_llm_narration":true},
     {"name":"Anvil Sweep","dice":"d8","element":"neutral","requires_llm_narration":false}]'::jsonb),

  ('the_sunken_crown', 'Lord Brundir''s Shade',
   'The corrupted shade of the dwarven lord-king who drowned his own hold. He still wears the Sunken Crown.',
   'big', 'dark', 110, 16, 18, 30,
   '[{"name":"Crown-Word","dice":"2d8","element":"dark","requires_llm_narration":true},
     {"name":"Drowning Curse","dice":"d10","element":"water","requires_llm_narration":true},
     {"name":"Royal Decree","dice":"d6","element":"neutral","requires_llm_narration":true}]'::jsonb);

-- =============================================================
-- Ashfall
-- =============================================================
insert into public.template_bosses
  (template_id, name, description, tier, element, hp, base_damage, ac, order_index, signature_moves)
values
  ('ashfall', 'The Foreman of the Ash Mill',
   'A bloated cult leader in a flour-grey apron. He grinds bones into the ash and laughs without sound.',
   'medium', 'earth', 70, 11, 15, 10,
   '[{"name":"Choking Cloud","dice":"d8","element":"earth","requires_llm_narration":true},
     {"name":"Cleaver","dice":"d6","element":"neutral","requires_llm_narration":false}]'::jsonb),

  ('ashfall', 'The Pale Choir',
   'Seven robed singers around the child of Wenholt. Their voices are the new dark made audible.',
   'big', 'dark', 130, 14, 17, 30,
   '[{"name":"Hymn of the Long Night","dice":"2d8","element":"dark","requires_llm_narration":true},
     {"name":"Choral Strike","dice":"d10","element":"dark","requires_llm_narration":true}]'::jsonb);

-- =============================================================
-- The Clockwork Heist
-- =============================================================
insert into public.template_bosses
  (template_id, name, description, tier, element, hp, base_damage, ac, order_index, signature_moves)
values
  ('the_clockwork_heist', 'Lock Sentry Mk. III',
   'A waist-high brass automaton on three articulated legs. It clicks softly to itself and discharges a copper baton.',
   'small', 'lightning', 24, 5, 14, 10,
   '[{"name":"Baton Discharge","dice":"d6","element":"lightning","requires_llm_narration":false}]'::jsonb),

  ('the_clockwork_heist', 'Foreman Pretch',
   'A wiry, paranoid foreman with a punch-card pistol and grease under every nail.',
   'small', 'neutral', 28, 6, 14, 20,
   '[{"name":"Punch-Card Pistol","dice":"d8","element":"neutral","requires_llm_narration":false},
     {"name":"Bellow For Help","dice":null,"element":null,"requires_llm_narration":true}]'::jsonb),

  ('the_clockwork_heist', 'The Iron Doorman',
   'A two-meter security automaton in the shape of a butler. Its monocle is a brass-rimmed lens.',
   'medium', 'lightning', 75, 12, 16, 30,
   '[{"name":"Concussive Backhand","dice":"d10","element":"neutral","requires_llm_narration":false},
     {"name":"Steam-Vent Roar","dice":"2d6","element":"fire","requires_llm_narration":true}]'::jsonb),

  ('the_clockwork_heist', 'Cyrus Vehl',
   'The industrialist himself: silver hair, brass-fingered glove, a spider-shaped lapel pin that twitches.',
   'big', 'neutral', 120, 15, 18, 40,
   '[{"name":"Spider-Pin Strike","dice":"d8","element":"lightning","requires_llm_narration":true},
     {"name":"Hire You Instead","dice":null,"element":null,"requires_llm_narration":true},
     {"name":"Steam-Glove Crush","dice":"2d8","element":"neutral","requires_llm_narration":true}]'::jsonb);

-- =============================================================
-- Side missions
-- =============================================================
insert into public.template_side_missions
  (template_id, title, description, trigger_intent, trigger_keywords, reward_xp, reward_items, required_phase, max_simultaneous, steps)
values
  ('the_sunken_crown', 'Free the Apprentice''s Ghost',
   'A young apprentice''s ghost is bound to a hammer in the Cinderforge. Find it, free it, and the ghost may bless your weapon.',
   'help_apprentice_ghost',
   '["help apprentice", "free ghost", "small ghost", "young dwarf"]'::jsonb,
   120,
   '[{"name":"Apprentice''s Blessing","item_type":"misc","qty":1,"description":"+1 to attack rolls for the rest of the campaign."}]'::jsonb,
   'rising', 3,
   '["Find the bound hammer in the Cinderforge.","Speak its true name.","Release the apprentice from the haft."]'::jsonb),

  ('the_sunken_crown', 'Recover the Drowned Ledger',
   'A waterlogged ledger lists where the lesser thralls were buried. Returning it to a sage outside grants gold and gear.',
   'recover_drowned_ledger',
   '["ledger", "drowned book", "ship manifest"]'::jsonb,
   80,
   '[{"name":"Sage''s Pouch","item_type":"misc","qty":1,"description":"60 gold + a Healing Potion."},
     {"name":"Healing Potion","item_type":"consumable","qty":1,"description":"Restores 12 HP on use."}]'::jsonb,
   'rising', 3,
   '["Find the soaked ledger in the Drowning Hall.","Carry it out of the hold."]'::jsonb),

  ('ashfall', 'A Promise of Bread',
   'A starving woman at the Hollow Inn asks you to bring her a sack of grain from a hidden cache. It will not save her, but it may dignify her end.',
   'help_starving_woman',
   '["starving woman", "old lady", "hungry villager", "promise bread"]'::jsonb,
   100,
   '[{"name":"Hand-Stitched Cloak","item_type":"armor","qty":1,"description":"+1 AC, smells faintly of woodsmoke."}]'::jsonb,
   'rising', 3,
   '["Find the grain cache in the cellar of the Hollow Inn.","Return to the woman before sundown."]'::jsonb),

  ('ashfall', 'Bury the Singer',
   'A traveling bard lies frozen by the road, lyre in hand. Burying him properly may quiet a song you''ll otherwise hear at night.',
   'bury_bard',
   '["bury bard", "dead singer", "cold body", "lyre"]'::jsonb,
   80,
   '[{"name":"Singer''s Lyre","item_type":"misc","qty":1,"description":"Reduces ambush chance during brief rests."}]'::jsonb,
   null, 3,
   '["Find a clean patch of earth.","Bury the bard.","Speak a verse over the grave."]'::jsonb),

  ('the_clockwork_heist', 'The Boy in the Boiler Room',
   'A conscripted ''apprentice'' boy in the boiler room asks you to take him out with you when you leave. Refusing has narrative weight.',
   'help_apprentice_boy',
   '["help boy", "apprentice child", "free child", "smuggle out"]'::jsonb,
   140,
   '[{"name":"Brass Whistle","item_type":"misc","qty":1,"description":"A coded whistle that summons aid once per campaign."}]'::jsonb,
   'rising', 3,
   '["Speak with the boy in the boiler room.","Find a way to smuggle him past sentries.","Get him to the alley outside before climbing higher."]'::jsonb),

  ('the_clockwork_heist', 'The Senator''s Mistress',
   'A woman in the Brass Foyer slips you a note. She is the senator''s mistress; she has her own evidence to trade. Following up may yield more leverage.',
   'meet_senators_mistress',
   '["meet woman", "follow note", "mistress", "senator", "trade evidence"]'::jsonb,
   100,
   '[{"name":"Letter of Introduction","item_type":"misc","qty":1,"description":"Bypasses one social check at the patron''s townhouse later."}]'::jsonb,
   'rising', 3,
   '["Read the note.","Meet the mistress in a back room.","Trade or refuse the offered evidence."]'::jsonb);
