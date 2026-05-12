-- =====================================================================
-- DungeonKu — Avatar lore + per-avatar signature skill
-- =====================================================================
-- Extends the 35 avatar templates (7 classes × 5) with narrative depth
-- and a unique gameplay hook each:
--
--   1. Schema additions on `avatar_templates`:
--      + backstory          text       — 1-2 sentence origin
--      + personality_tags   jsonb      — 3-4 trait keywords
--      + story_hooks        jsonb      — 2-3 narrative seeds DM can pull on
--      + signature_skill_id text       — FK -> skills.id (the avatar's
--                                        unique ability)
--
--   2. 35 new rows in `skills`, prefixed `sig_`, one per avatar.
--      Class-bound (so they can't be picked up by other classes via the
--      level-up table) but their canonical owner is the avatar, not the
--      class.
--
--   3. UPDATE all 35 avatars to wire backstory + personality + hooks +
--      signature_skill_id.
--
-- Runtime:
--   • CampaignsRepository.create() will look up the chosen character's
--     avatar_id and insert avatar.signature_skill_id into campaign_skills
--     so the ability becomes a real, usable skill in combat from turn 1.
--   • Edge function context.ts joins avatar_templates so backstory +
--     personality + hooks reach the DM system prompt as flavor.
--
-- Schema-aware: tables were moved from public → dungeonku in
-- 20260507000000. We set the session search_path here so unqualified
-- table references resolve to whichever schema currently owns them
-- (dungeonku in production; public on legacy clones — silently ignored
-- if a schema in the list doesn't exist).
-- =====================================================================

set search_path to dungeonku, public;

-- ---------------------------------------------------------------------
-- 1. Schema additions
-- ---------------------------------------------------------------------
alter table avatar_templates
  add column if not exists backstory          text,
  add column if not exists personality_tags   jsonb default '[]'::jsonb,
  add column if not exists story_hooks        jsonb default '[]'::jsonb,
  add column if not exists signature_skill_id text;

-- ---------------------------------------------------------------------
-- 2. Signature skills — 35 rows, idempotent.
--
--    All `sig_*` skills follow the existing skills schema (see
--    20260101000003_seed_skills). Cost balanced against class-equivalent
--    skills; effects are descriptive enough for the LLM DM to invoke
--    them narratively, but the dice/modifier columns mean the existing
--    combat resolver also accepts them as ordinary skills.
--
--    available_to_classes is set so the ability can never be granted to
--    the wrong class through level-up tables; it's avatar-bound, not
--    class-broad.
-- ---------------------------------------------------------------------

insert into skills
  (id, name, description, element, kind, cost_type, cost_amount, dice,
   modifier_stat, base_damage_or_effect, available_to_classes,
   required_level, is_basic_attack, sort_order)
values
  -- ----- WARRIOR signatures -----
  ('sig_ironcast_stance', 'Ironcast Stance',
    $sd$You plant your feet and raise the shield. Until your next turn you take half damage from physical hits, and you cannot be moved or knocked prone.$sd$,
    'neutral', 'buff', 'stamina', 5, null, 'STR',
    '{"self_buff": {"damage_reduction": 0.5, "immovable": true, "duration": 1}}'::jsonb,
    '["warrior"]'::jsonb, 1, false, 1010),

  ('sig_rallying_cry', 'Rallying Cry',
    $sd$You raise your voice and the company forms up — even if the company is just you. Allies (you included) gain advantage on their next attack roll.$sd$,
    'neutral', 'buff', 'stamina', 4, null, 'CHA',
    '{"party_buff": {"next_attack_advantage": true, "duration": 2}}'::jsonb,
    '["warrior"]'::jsonb, 1, false, 1011),

  ('sig_hillstone_headbutt', 'Hillstone Headbutt',
    $sd$An ugly, low headbutt that nobody trains for. On hit, the foe is stunned for one turn; even on a miss, they are rattled.$sd$,
    'neutral', 'attack', 'stamina', 3, 'd6', 'STR',
    '{"status_on_hit": {"key": "stunned", "duration": 1}, "status_on_miss": {"key": "rattled", "duration": 1}}'::jsonb,
    '["warrior"]'::jsonb, 1, false, 1012),

  ('sig_sentinels_vow', $$Sentinel's Vow$$,
    $sd$You silently mark a foe as your charge. Until one of you falls, you deal +d4 damage to that foe and they cannot easily escape your reach.$sd$,
    'neutral', 'buff', 'stamina', 4, null, 'WIS',
    '{"single_target_mark": {"damage_bonus": "d4", "duration": 99, "binding": true}}'::jsonb,
    '["warrior"]'::jsonb, 1, false, 1013),

  ('sig_shield_wall', 'Shield Wall',
    $sd$You step between an ally and a swung weapon. The next attack against any nearby ally hits you instead, and you absorb half its damage.$sd$,
    'neutral', 'buff', 'stamina', 3, null, 'STR',
    '{"redirect_next_ally_hit": true, "damage_reduction": 0.5, "duration": 2}'::jsonb,
    '["warrior"]'::jsonb, 1, false, 1014),

  -- ----- ROGUE signatures -----
  ('sig_vanish', 'Vanish',
    $sd$You melt into shadow mid-step. Until your next turn you cannot be targeted by attacks, and your next attack from concealment crits on 17+.$sd$,
    'neutral', 'buff', 'stamina', 5, null, 'DEX',
    '{"self_buff": {"invisible": true, "next_attack_crit_threshold": 17, "duration": 1}}'::jsonb,
    '["rogue"]'::jsonb, 1, false, 1020),

  ('sig_cruel_smile', 'Cruel Smile',
    $sd$You hold the foe's eye and smile. Their nerve breaks — until your next turn they have disadvantage on attacks, and on a failed save they may flee.$sd$,
    'neutral', 'debuff', 'stamina', 4, null, 'CHA',
    '{"status_on_hit": {"key": "frightened", "duration": 2}, "save_dc_stat": "CHA"}'::jsonb,
    '["rogue"]'::jsonb, 1, false, 1021),

  ('sig_wanderers_lock', $$Wanderer's Lock$$,
    $sd$Your hands know more locks than you do. Bypass any single mundane lock, ward, trap, or seal — no roll, no noise. Magical seals reduce in difficulty by one tier.$sd$,
    'neutral', 'utility', 'stamina', 3, null, 'DEX',
    '{"auto_bypass_lock": true, "magical_difficulty_reduction": 1}'::jsonb,
    '["rogue"]'::jsonb, 1, false, 1022),

  ('sig_light_fingers', 'Light Fingers',
    $sd$Mid-fight you pluck something useful off a foe — a key, a vial, a pouch of coins. DM picks something narratively appropriate; minor damage on contact.$sd$,
    'neutral', 'attack', 'stamina', 4, 'd4', 'DEX',
    '{"on_hit_steal_item": true}'::jsonb,
    '["rogue"]'::jsonb, 1, false, 1023),

  ('sig_twilight_pirouette', 'Twilight Pirouette',
    $sd$You pirouette through the foes' line. Pass through any space without provoking attacks; the next attack made against you this turn misses automatically.$sd$,
    'neutral', 'buff', 'stamina', 5, null, 'DEX',
    '{"self_buff": {"free_movement": true, "next_hit_against_misses": true, "duration": 1}}'::jsonb,
    '["rogue"]'::jsonb, 1, false, 1024),

  -- ----- MAGE signatures -----
  ('sig_bookmark_memory', 'Bookmark Memory',
    $sd$You bookmark a spell mid-cast. The next time you cast that exact skill this scene, it costs no MP.$sd$,
    'arcane', 'utility', 'free', 0, null, 'INT',
    '{"bookmark_next_skill": true}'::jsonb,
    '["mage"]'::jsonb, 1, false, 1030),

  ('sig_wildbloom', 'Wildbloom',
    $sd$You crouch and root one hand to the ground. Healing flora bursts up — allies who step on it heal d6, and the patch entangles enemies who walk through.$sd$,
    'nature', 'buff', 'mp', 5, 'd6', 'WIS',
    '{"area_heal": "d6", "entangle_enemies": true, "duration": 3}'::jsonb,
    '["mage"]'::jsonb, 1, false, 1031),

  ('sig_thunderclap', 'Thunderclap',
    $sd$You clap your hands and the air explodes. Stuns all nearby foes for one turn; deafens you and any allies too close.$sd$,
    'lightning', 'attack', 'mp', 6, '2d6', 'INT',
    '{"aoe": true, "status_on_hit": {"key": "stunned", "duration": 1}, "self_status": {"key": "deafened", "duration": 1}}'::jsonb,
    '["mage"]'::jsonb, 1, false, 1032),

  ('sig_crystaline_halt', 'Crystaline Halt',
    $sd$You point at a foe and freeze the breath in their lungs. Single foe is held in place and skips their next turn; failed save adds cold damage.$sd$,
    'ice', 'debuff', 'mp', 5, null, 'INT',
    '{"status_on_hit": {"key": "frozen", "duration": 1}, "save_dc_stat": "INT", "on_save_fail_damage": "d6"}'::jsonb,
    '["mage"]'::jsonb, 1, false, 1033),

  ('sig_ember_scrawl', 'Ember Scrawl',
    $sd$You scrawl a glowing rune. At the start of your next turn, the rune detonates for d8 fire damage to anyone in or adjacent to the marked space.$sd$,
    'fire', 'attack', 'mp', 5, 'd8', 'INT',
    '{"delayed_aoe": {"duration": 1, "dice": "d8", "element": "fire"}}'::jsonb,
    '["mage"]'::jsonb, 1, false, 1034),

  -- ----- PRIEST signatures -----
  ('sig_whispered_prayer', 'Whispered Prayer',
    $sd$A small kindness in the form of a prayer. Heal an ally for d6 and remove one minor status (stunned, frightened, charmed).$sd$,
    'holy', 'heal', 'mp', 4, 'd6', 'WIS',
    '{"ally_heal": "d6", "remove_minor_status": true}'::jsonb,
    '["priest"]'::jsonb, 1, false, 1040),

  ('sig_roadside_mend', 'Roadside Mend',
    $sd$You drop your pack and work fast. One ally is restored to full HP. Once per scene.$sd$,
    'holy', 'heal', 'mp', 8, null, 'WIS',
    '{"ally_full_heal": true, "scene_limited": true}'::jsonb,
    '["priest"]'::jsonb, 1, false, 1041),

  ('sig_voice_of_choir', 'Voice of the Choir',
    $sd$Your sermon-voice fills the room. Allies gain advantage on their next social roll, and one hostile NPC must save against being momentarily swayed.$sd$,
    'holy', 'buff', 'mp', 5, null, 'CHA',
    '{"party_buff": {"social_advantage": true, "duration": 2}, "status_on_hit": {"key": "swayed", "duration": 1}}'::jsonb,
    '["priest"]'::jsonb, 1, false, 1042),

  ('sig_stone_communion', 'Stone Communion',
    $sd$You touch a person, place, or object and let the stones tell you what they remember. Learn one truth: a hidden motive, a recent event, a suppressed memory.$sd$,
    'nature', 'utility', 'mp', 6, null, 'WIS',
    '{"reveal_truth": true}'::jsonb,
    '["priest"]'::jsonb, 1, false, 1043),

  ('sig_battle_blessing', 'Battle Blessing',
    $sd$You touch an ally's brow before the swing. The next attack against them deals half damage — even a critical becomes survivable.$sd$,
    'holy', 'buff', 'mp', 4, null, 'WIS',
    '{"ally_damage_reduction_next_hit": 0.5, "duration": 2}'::jsonb,
    '["priest"]'::jsonb, 1, false, 1044),

  -- ----- RANGER signatures -----
  ('sig_one_with_trees', 'One With Trees',
    $sd$You stand still and become foliage. In any natural terrain you cannot be detected by mundane means; your next shot from concealment doubles its damage dice.$sd$,
    'nature', 'buff', 'stamina', 4, null, 'WIS',
    '{"self_buff": {"natural_concealment": true, "next_attack_double_dice": true, "duration": 3}}'::jsonb,
    '["ranger"]'::jsonb, 1, false, 1050),

  ('sig_hawks_eye', $$Hawk's Eye$$,
    $sd$Your hawk circles overhead and shows you the angles. Your next ranged attack ignores cover, has advantage, and rolls a bonus damage die.$sd$,
    'neutral', 'attack', 'stamina', 4, 'd8', 'DEX',
    '{"next_ranged_ignores_cover": true, "next_ranged_advantage": true, "bonus_damage_die": "d6"}'::jsonb,
    '["ranger"]'::jsonb, 1, false, 1051),

  ('sig_bog_step', 'Bog Step',
    $sd$You move through any difficult terrain — mud, water, vines, snow — as if it were dry road. Allies within reach can follow your steps.$sd$,
    'nature', 'buff', 'stamina', 3, null, 'DEX',
    '{"self_buff": {"ignore_difficult_terrain": true, "ally_follow": true, "duration": 5}}'::jsonb,
    '["ranger"]'::jsonb, 1, false, 1052),

  ('sig_cold_read', 'Cold Read',
    $sd$You study a foe and their tells stop being tells. Learn one weakness (element, status, old wound); your next attack against them crits on 17+.$sd$,
    'neutral', 'utility', 'stamina', 4, null, 'WIS',
    '{"reveal_enemy_weakness": true, "next_attack_crit_threshold": 17, "duration": 2}'::jsonb,
    '["ranger"]'::jsonb, 1, false, 1053),

  ('sig_hunters_mark', $$Hunter's Mark$$,
    $sd$You name a quarry. Until the scene ends or the quarry falls, you deal +d4 damage to that foe and you can always sense their direction.$sd$,
    'neutral', 'buff', 'stamina', 4, null, 'WIS',
    '{"single_target_mark": {"damage_bonus": "d4", "track": true, "duration": 99}}'::jsonb,
    '["ranger"]'::jsonb, 1, false, 1054),

  -- ----- BLACKSMITH signatures -----
  ('sig_anvil_skin', 'Anvil Skin',
    $sd$Your hide is closer to iron than skin. The next time you would take damage, halve it. Once per scene.$sd$,
    'neutral', 'buff', 'free', 0, null, 'CON',
    '{"next_damage_halved": true, "scene_limited": true}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 1060),

  ('sig_cinder_toss', 'Cinder Toss',
    $sd$You scoop hot coals from your forge-pouch and hurl them. Small AoE; foes in range take fire damage and may be set alight.$sd$,
    'fire', 'attack', 'stamina', 4, 'd6', 'STR',
    '{"aoe": true, "status_on_hit": {"key": "burning", "duration": 2, "tick_damage": 2}}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 1061),

  ('sig_iron_song', 'Iron Song',
    $sd$You hum the working-tune as the fight begins. Each ally's armor counts as one tier sturdier (+1 AC) and shrugs off the next minor status.$sd$,
    'neutral', 'buff', 'stamina', 5, null, 'CHA',
    '{"party_buff": {"ac_bonus": 1, "shrug_minor_status": true, "duration": 3}}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 1062),

  ('sig_field_repair', 'Field Repair',
    $sd$You patch a piece of equipment mid-fight. Restore one broken/damaged weapon, shield, or armor; if it had a special property, that property is renewed.$sd$,
    'neutral', 'utility', 'stamina', 3, null, 'INT',
    '{"repair_equipment": true, "restore_special_property": true}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 1063),

  ('sig_dwarvish_smash', 'Dwarvish Smash',
    $sd$You drop your hammer in the dwarven way — timing instead of muscle. Heavy single-target damage; foe is stunned and their armor takes a notch.$sd$,
    'neutral', 'attack', 'stamina', 6, '2d6', 'STR',
    '{"status_on_hit": {"key": "stunned", "duration": 1}, "damages_armor": true}'::jsonb,
    '["blacksmith"]'::jsonb, 1, false, 1064),

  -- ----- BARD signatures -----
  ('sig_road_song', 'Road Song',
    $sd$You strum a march. Each ally regains a small amount of stamina/MP, and any minor status effect ticks down faster.$sd$,
    'neutral', 'buff', 'stamina', 4, null, 'CHA',
    '{"party_resource_restore": 2, "minor_status_double_tick": true, "duration": 3}'::jsonb,
    '["bard"]'::jsonb, 1, false, 1070),

  ('sig_face_swap', 'Face Swap',
    $sd$Paint, posture, accent — three things at once — and you become someone else for the scene. Convince any single NPC you are a different specific person, until you do something out of character.$sd$,
    'neutral', 'utility', 'stamina', 5, null, 'CHA',
    '{"disguise_self": true, "scene_limited": true}'::jsonb,
    '["bard"]'::jsonb, 1, false, 1071),

  ('sig_coin_song', 'Coin-Song',
    $sd$You name a price and everyone hears it as fair. Sway a single NPC's price or decision toward your offer; once per NPC per scene.$sd$,
    'neutral', 'utility', 'stamina', 4, null, 'CHA',
    '{"bargain_advantage": true, "scene_limited": true}'::jsonb,
    '["bard"]'::jsonb, 1, false, 1072),

  ('sig_hearthsong', 'Hearthsong',
    $sd$You sing a song that means home. Allies recover a small amount of HP and stamina, and gain advantage on their next save against fear or charm.$sd$,
    'neutral', 'buff', 'stamina', 5, 'd4', 'CHA',
    '{"party_heal": "d4", "party_resource_restore": 2, "save_advantage_fear_charm": true, "duration": 2}'::jsonb,
    '["bard"]'::jsonb, 1, false, 1073),

  ('sig_twilight_dirge', 'Twilight Dirge',
    $sd$A low dirge that fills the air with a slow, settling sorrow. Single foe rolls all attacks and saves at disadvantage until end of next turn.$sd$,
    'neutral', 'debuff', 'stamina', 4, null, 'CHA',
    '{"status_on_hit": {"key": "sorrowful", "duration": 2, "all_rolls_disadvantage": true}}'::jsonb,
    '["bard"]'::jsonb, 1, false, 1074)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- 3. Avatar lore — backstory + personality + hooks + signature link.
--
--    Each block: a single UPDATE per avatar so the migration is easy
--    to read row-by-row when content needs editorial revision.
-- ---------------------------------------------------------------------

-- ----- WARRIOR -----
update avatar_templates set
  backstory = $bs$Once a frontier paladin sworn to a fallen order, you carried the last shield of your barracks out of a burning chapter house. The shield's crest is now your only god.$bs$,
  personality_tags = $tg$["stoic", "dutiful", "weary", "loyal"]$tg$::jsonb,
  story_hooks = $hk$["An old comrade — presumed dead — surfaces in the city you ride into.", "The crest on your shield is recognized by an enemy who served your fallen order.", "A child wears a holy medallion identical to one you buried with a friend."]$hk$::jsonb,
  signature_skill_id = 'sig_ironcast_stance'
where id = 'warrior_01';

update avatar_templates set
  backstory = $bs$You led the Crimson Lance through three border wars. The banner is gone, the company is gone, but the men still answer when you call — and so does every old enemy.$bs$,
  personality_tags = $tg$["commanding", "battle-scarred", "charismatic", "blunt"]$tg$::jsonb,
  story_hooks = $hk$["A surviving subordinate has gone freelance and is operating in this region.", "A vassal of an enemy you once defeated holds a quiet grudge.", "A war ballad about your company is sung in the local tavern, and not all the verses are flattering."]$hk$::jsonb,
  signature_skill_id = 'sig_rallying_cry'
where id = 'warrior_02';

update avatar_templates set
  backstory = $bs$You grew up in a hillfolk fighting circle where everything has rules and nothing is fair. Now you carry your village's crooked grin into bigger fights.$bs$,
  personality_tags = $tg$["scrappy", "earthy", "irreverent", "tough"]$tg$::jsonb,
  story_hooks = $hk$["Your village's annual fighting festival is happening in three days, and your name is still on the bracket.", "A bigger fighter you once dropped has been hunting you across kingdoms.", "A kid from your hillfolk wants to be the next you and is following the party at a distance."]$hk$::jsonb,
  signature_skill_id = 'sig_hillstone_headbutt'
where id = 'warrior_03';

update avatar_templates set
  backstory = $bs$An order of silent oath-keepers raised you and gave you a face you never wear. You guard one thing at a time, and you never explain what.$bs$,
  personality_tags = $tg$["silent", "obsessive", "watchful", "principled"]$tg$::jsonb,
  story_hooks = $hk$["Your current vow is unspoken — even the party doesn't know what (or who) you've sworn to protect.", "Another sentinel of your order is in the city, and they have broken their veil for the first time.", "The thing you swore to guard is in this room with you."]$hk$::jsonb,
  signature_skill_id = 'sig_sentinels_vow'
where id = 'warrior_04';

update avatar_templates set
  backstory = $bs$You learned the shield-line from a war-hall full of women who would have died for the wrong queen. They mostly did. You chose differently and you remember everyone.$bs$,
  personality_tags = $tg$["protective", "principled", "battle-mournful", "fierce"]$tg$::jsonb,
  story_hooks = $hk$["A noble in this town wears the colors of the queen you abandoned.", "An old shield-sister is now a sellsword with the rival faction.", "A relic of your war-hall — a horn, a banner, a brooch — surfaces in an unlikely place."]$hk$::jsonb,
  signature_skill_id = 'sig_shield_wall'
where id = 'warrior_05';

-- ----- ROGUE -----
update avatar_templates set
  backstory = $bs$The slums raised you, the rooftops finished the job. You learned to be where nobody looks, and you taught yourself a second language: silence.$bs$,
  personality_tags = $tg$["wary", "quiet", "loyal-to-few", "haunted"]$tg$::jsonb,
  story_hooks = $hk$["Your street name is on a wanted poster for a job you didn't pull.", "A childhood friend from the slums has moved up — they run a whole crew now.", "The alley you grew up in is being torn down for new construction."]$hk$::jsonb,
  signature_skill_id = 'sig_vanish'
where id = 'rogue_01';

update avatar_templates set
  backstory = $bs$Your first name was a nickname. You smiled because the alternative was crying, and at some point smiling became cheaper than crying. Now your work is mostly knives, and you still smile.$bs$,
  personality_tags = $tg$["sardonic", "cruel-edged", "charming", "fearless"]$tg$::jsonb,
  story_hooks = $hk$["Someone in the city remembers your real name.", "A target you spared has become wealthy and won't admit they remember you.", "A rival cutter copies your smile to scare people, and they're getting better at it."]$hk$::jsonb,
  signature_skill_id = 'sig_cruel_smile'
where id = 'rogue_02';

update avatar_templates set
  backstory = $bs$You've never settled. You walk in, you pick the lock, you walk out. Towns blur. The names you give blur. Only the locks remember the same.$bs$,
  personality_tags = $tg$["enigmatic", "free", "evasive", "patient"]$tg$::jsonb,
  story_hooks = $hk$["An innkeeper recognizes you from a town two kingdoms away.", "The ward on a famous vault was supposedly yours.", "A young grifter is using your old aliases."]$hk$::jsonb,
  signature_skill_id = 'sig_wanderers_lock'
where id = 'rogue_03';

update avatar_templates set
  backstory = $bs$You make people lighter. They never feel it. The trick is not the cut — it is the smile after, where you palm the coin into someone else's pocket and walk.$bs$,
  personality_tags = $tg$["light-fingered", "playful", "greedy", "slippery"]$tg$::jsonb,
  story_hooks = $hk$["A merchant in the market has the family ring you lifted years ago and doesn't know whose it was.", "A noble offers you a fortune to lift one specific item — and they're lying about what it is.", "Your old fence has gone respectable and pretends not to know you."]$hk$::jsonb,
  signature_skill_id = 'sig_light_fingers'
where id = 'rogue_04';

update avatar_templates set
  backstory = $bs$A noble house bought you as a dance-pupil, and you cut your way out of the contract one chandelier at a time. You move like dancing because that is the body you have. Knives just rhyme with steps.$bs$,
  personality_tags = $tg$["graceful", "vengeful", "elegant", "merciless"]$tg$::jsonb,
  story_hooks = $hk$["A noble of the house that bought you is at the upcoming masquerade.", "Another dance-pupil from your old house is now a courtier.", "A song from your training days is being played somewhere you didn't expect."]$hk$::jsonb,
  signature_skill_id = 'sig_twilight_pirouette'
where id = 'rogue_05';

-- ----- MAGE -----
update avatar_templates set
  backstory = $bs$You served four years polishing the wand-hands of an archmage. You read his marginalia, you copied his cantrips into a smaller book, and one night you walked out with that book.$bs$,
  personality_tags = $tg$["bookish", "anxious", "curious", "secretly-ambitious"]$tg$::jsonb,
  story_hooks = $hk$["Your old master has begun searching for the missing book.", "A fellow apprentice from the tower has just shown up, claiming to have left for the same reasons.", "A spell from your stolen book has appeared on a wanted poster."]$hk$::jsonb,
  signature_skill_id = 'sig_bookmark_memory'
where id = 'mage_01';

update avatar_templates set
  backstory = $bs$You learned magic from your grandmother's herb-shed. The towers don't think it's real. Your grandmother is dead and you keep the shed locked but stocked, just in case.$bs$,
  personality_tags = $tg$["earthy", "kind", "grounded", "skeptical-of-authority"]$tg$::jsonb,
  story_hooks = $hk$["A village near here has fallen ill in a way only your grandmother's notes could explain.", "A real hedge-witch is being burned in the next town and the party will pass through.", "The herb-shed was broken into recently."]$hk$::jsonb,
  signature_skill_id = 'sig_wildbloom'
where id = 'mage_02';

update avatar_templates set
  backstory = $bs$You went to sea on a stormship as a tally-clerk and came back as something else. The sailors don't say what happened in the Skerry; you don't either. Lightning answers when you whistle.$bs$,
  personality_tags = $tg$["wild", "intense", "unpredictable", "lonely"]$tg$::jsonb,
  story_hooks = $hk$["A storm-sworn sailor from the same ship has gone mad.", "The Skerry incident is being investigated by an Inquisitor you've heard of.", "Lightning crackles around your hand even when you are calm."]$hk$::jsonb,
  signature_skill_id = 'sig_thunderclap'
where id = 'mage_03';

update avatar_templates set
  backstory = $bs$You apprenticed under a jotunn who lived alone on a glacier. They taught you to slow time the way ice slows water. You came back warmer than you should have been.$bs$,
  personality_tags = $tg$["patient", "remote", "precise", "very-still"]$tg$::jsonb,
  story_hooks = $hk$["Your jotunn-master is dying, and the glacier is melting.", "A relic from the jotunn's hut surfaces in a southern auction.", "Another ice-mage in the city is using your master's signature."]$hk$::jsonb,
  signature_skill_id = 'sig_crystaline_halt'
where id = 'mage_04';

update avatar_templates set
  backstory = $bs$You were in the cinder-school when it burned. The teachers let it burn — said the magic was in the ashes, not the books. You came out with marks on your skin that look like writing if you tilt your head.$bs$,
  personality_tags = $tg$["scarred", "philosophical", "fire-haunted", "deliberate"]$tg$::jsonb,
  story_hooks = $hk$["The other survivors of the cinder-school have a tattoo that matches your scars.", "Someone is collecting cinder-school survivors for a project.", "A fire-cult is using runes that look exactly like your marks."]$hk$::jsonb,
  signature_skill_id = 'sig_ember_scrawl'
where id = 'mage_05';

-- ----- PRIEST -----
update avatar_templates set
  backstory = $bs$You spent your novitiate copying scripture and never once raised your voice. The mother superior said you would be a priest of the small things — and she was right.$bs$,
  personality_tags = $tg$["humble", "quiet", "kind", "observant"]$tg$::jsonb,
  story_hooks = $hk$["A novice has run away from your monastery and ended up in this region.", "A scrap of scripture you copied has been bound into someone else's prayer book.", "The mother superior who taught you has fallen ill."]$hk$::jsonb,
  signature_skill_id = 'sig_whispered_prayer'
where id = 'priest_01';

update avatar_templates set
  backstory = $bs$You don't belong to any temple. You have a ledger of every person you've patched up and you read their names before bed. You don't always remember faces, but you remember names.$bs$,
  personality_tags = $tg$["compassionate", "rootless", "thorough", "tired"]$tg$::jsonb,
  story_hooks = $hk$["A name from your ledger walks into the tavern.", "A village you helped years ago is in danger again.", "Someone is healing people in your style across the road, but charging for it."]$hk$::jsonb,
  signature_skill_id = 'sig_roadside_mend'
where id = 'priest_02';

update avatar_templates set
  backstory = $bs$Your faith trades in ornament. The temple paid for your gold-thread vestments, and your sermons fill chapels because you are good — and you know it. You have not yet decided whether the goodness is real.$bs$,
  personality_tags = $tg$["eloquent", "vain", "doubting", "warm"]$tg$::jsonb,
  story_hooks = $hk$["A rival speaker from your faith has begun to draw your usual crowd.", "A minor noble has commissioned a sermon you'd rather not give.", "An old congregation member appears claiming you saved their life — and you don't remember them."]$hk$::jsonb,
  signature_skill_id = 'sig_voice_of_choir'
where id = 'priest_03';

update avatar_templates set
  backstory = $bs$You climbed the holy peak as a youth and stayed thirty years. The mountain spoke to you in stones; the stones told you things about people. You came down because the mountain told you to.$bs$,
  personality_tags = $tg$["distant", "blunt", "perceptive", "unworldly"]$tg$::jsonb,
  story_hooks = $hk$["A pilgrim arrives looking for the wisdom you supposedly carry.", "A piece of the mountain — a chip, a stone, a relic — is being trafficked.", "The mountain has stopped speaking to you, recently."]$hk$::jsonb,
  signature_skill_id = 'sig_stone_communion'
where id = 'priest_04';

update avatar_templates set
  backstory = $bs$You walked with regiments. You blessed weapons, you closed eyes, you wrote letters home for boys who couldn't write. You no longer pretend the gods care equally.$bs$,
  personality_tags = $tg$["weary", "practical", "cynical-gentle", "unshakable"]$tg$::jsonb,
  story_hooks = $hk$["A soldier you blessed before they died has a sister in this town.", "A regimental flag you remember is being carried by the wrong side.", "A general from your old service has just arrived in the city."]$hk$::jsonb,
  signature_skill_id = 'sig_battle_blessing'
where id = 'priest_05';

-- ----- RANGER -----
update avatar_templates set
  backstory = $bs$Your wood is small. You've walked every game-trail of it since you were eight, and you can name the rooks. You agreed to leave because something was hunting in your wood, and the only way to learn what was to follow it out.$bs$,
  personality_tags = $tg$["watchful", "rooted", "soft-spoken", "tireless"]$tg$::jsonb,
  story_hooks = $hk$["News from your wood: another deer carcass has been found.", "An old poacher who knew the wood as well as you has gone respectable.", "A bird you bonded with has flown the wrong direction."]$hk$::jsonb,
  signature_skill_id = 'sig_one_with_trees'
where id = 'ranger_01';

update avatar_templates set
  backstory = $bs$Your hawk's name is older than you. She was your father's, and her father's. She does not love you, exactly, but you understand each other. She brings you sightings and you bring her warm meat.$bs$,
  personality_tags = $tg$["alert", "patient", "wry", "clannish"]$tg$::jsonb,
  story_hooks = $hk$["Your hawk has begun bringing back things from a place you don't recognize.", "A falconer in the city covets her openly.", "Your father's old falconry partner is now a captain of the watch."]$hk$::jsonb,
  signature_skill_id = 'sig_hawks_eye'
where id = 'ranger_02';

update avatar_templates set
  backstory = $bs$Your village is made of pole-houses over standing water. You learned to walk on bog before grass. The marsh is patient and so are you, and you have eaten things you do not name.$bs$,
  personality_tags = $tg$["unhurried", "self-reliant", "private", "amused"]$tg$::jsonb,
  story_hooks = $hk$["A surveyor from the kingdom is mapping your marsh.", "A drained reach of marsh has surfaced something very old.", "A marsh-bound elder has sent for you — by name, somehow."]$hk$::jsonb,
  signature_skill_id = 'sig_bog_step'
where id = 'ranger_03';

update avatar_templates set
  backstory = $bs$You were raised by an aunt who didn't believe in the cold. You learned to read snow like other people read scripture. There are bodies in your past you don't apologize for finding.$bs$,
  personality_tags = $tg$["cool-headed", "exact", "haunted", "competent"]$tg$::jsonb,
  story_hooks = $hk$["An old quarry has resurfaced in a different province.", "A new tracker has copied your reading-of-snow notation.", "Your aunt has died, and the funeral is in the dead of winter."]$hk$::jsonb,
  signature_skill_id = 'sig_cold_read'
where id = 'ranger_04';

update avatar_templates set
  backstory = $bs$Your people hunt the savanna. You can run a deer to ground over half a day and you have. The cities call your work cruel and you don't argue, but you eat what you kill.$bs$,
  personality_tags = $tg$["enduring", "earthy", "direct", "quietly-fierce"]$tg$::jsonb,
  story_hooks = $hk$["A traveling lord wants to commission you for a hunt you don't approve of.", "Your old hunting-partner has converted to vegetarianism and won't speak to you.", "Game in this region has thinned in a way that doesn't make sense."]$hk$::jsonb,
  signature_skill_id = 'sig_hunters_mark'
where id = 'ranger_05';

-- ----- BLACKSMITH -----
update avatar_templates set
  backstory = $bs$You worked your father's forge for twenty years. He could not afford to apprentice you formally; you taught yourself by ruining iron until the iron stopped letting you ruin it. Your hands look like stone.$bs$,
  personality_tags = $tg$["steady", "stubborn", "deliberate", "kind-when-asked"]$tg$::jsonb,
  story_hooks = $hk$["Your father's forge is failing without you and a letter has caught up to you.", "A piece of your work has surfaced as evidence in a crime.", "A guild-master wants to buy out your unfinished commissions."]$hk$::jsonb,
  signature_skill_id = 'sig_anvil_skin'
where id = 'blacksmith_01';

update avatar_templates set
  backstory = $bs$You apprenticed under a master who heated metal too hot, on purpose. You learned cinders are a tool. Your shop is gone now and you carry the anger out as work.$bs$,
  personality_tags = $tg$["hot-tempered", "passionate", "ambitious", "raw"]$tg$::jsonb,
  story_hooks = $hk$["Your old master is alive after all and operating in the same region.", "A rival apprentice from your shop is selling forged blades cheap.", "The fire that destroyed your shop wasn't an accident."]$hk$::jsonb,
  signature_skill_id = 'sig_cinder_toss'
where id = 'blacksmith_02';

update avatar_templates set
  backstory = $bs$Your forge is also a chapel. You sing while you hammer; you say the metal hears you. People assume the songs are folk-tunes; they're prayers — your prayers, made of sound that iron understands.$bs$,
  personality_tags = $tg$["soulful", "ritual-minded", "patient", "private"]$tg$::jsonb,
  story_hooks = $hk$["A song you wrote has become popular — and you've never published it.", "A relic-blade carries a tune you recognize from your master.", "A fellow Anvil-Singer is dying and has asked for you by name."]$hk$::jsonb,
  signature_skill_id = 'sig_iron_song'
where id = 'blacksmith_03';

update avatar_templates set
  backstory = $bs$You closed your shop to wander. You repair on the road, you sleep in barns, and you carry an anvil that's small enough to go on a packhorse. The horse hates you. The work is good.$bs$,
  personality_tags = $tg$["unhurried", "self-sufficient", "wry", "quiet"]$tg$::jsonb,
  story_hooks = $hk$["A village remembers a repair you did and asks for another.", "Your former apprentices have become a guild without you.", "The packhorse goes lame in the worst possible village."]$hk$::jsonb,
  signature_skill_id = 'sig_field_repair'
where id = 'blacksmith_04';

update avatar_templates set
  backstory = $bs$You learned in a dwarven hold that does not officially exist. They taught you not to swing the hammer; they taught you to drop it. The difference is small and entirely a matter of timing. You've never told outsiders the trick.$bs$,
  personality_tags = $tg$["measured", "unsentimental", "loyal", "underestimated"]$tg$::jsonb,
  story_hooks = $hk$["The dwarven hold has sent for you, formally.", "A weapon of striking quality has surfaced and the work is yours, but you don't remember making it.", "An outsider claims to have learned 'the drop' from a dwarf."]$hk$::jsonb,
  signature_skill_id = 'sig_dwarvish_smash'
where id = 'blacksmith_05';

-- ----- BARD -----
update avatar_templates set
  backstory = $bs$You have one lute. You bought it after your first lute was smashed in a tavern fight. You promised this one wouldn't get smashed and so far it hasn't, mostly because you've gotten better at the fight part.$bs$,
  personality_tags = $tg$["restless", "self-deprecating", "kind", "watchful"]$tg$::jsonb,
  story_hooks = $hk$["The man who smashed your first lute is in the next town and apparently a councilman now.", "A song you wrote at sixteen has become a wedding standard.", "Your lute's previous owner has surfaced asking after it."]$hk$::jsonb,
  signature_skill_id = 'sig_road_song'
where id = 'bard_01';

update avatar_templates set
  backstory = $bs$You came up through troupes that paint their faces. The paint is part of the work. People say you only feel things when you're masked, and you've never bothered to argue — partly because the people are sometimes right.$bs$,
  personality_tags = $tg$["theatrical", "guarded", "perceptive", "elegant"]$tg$::jsonb,
  story_hooks = $hk$["Your old troupe-leader is performing in town and has invited you to play her opposite.", "Someone has been impersonating you in cities you haven't been to.", "A noble at the upcoming masquerade has commissioned a play that suspiciously matches your past."]$hk$::jsonb,
  signature_skill_id = 'sig_face_swap'
where id = 'bard_02';

update avatar_templates set
  backstory = $bs$You sing where the coin is. You're not above the dirty taverns and you've sung at three thrones. The thrones tip worse than the taverns, but the songs travel further.$bs$,
  personality_tags = $tg$["mercenary", "shrewd", "sociable", "world-weary"]$tg$::jsonb,
  story_hooks = $hk$["A throne you sang at has fallen, and the new ruler remembers your face.", "A patron from a dirty tavern has gotten unexpectedly powerful.", "A song-collector wants to buy your unpublished setlist."]$hk$::jsonb,
  signature_skill_id = 'sig_coin_song'
where id = 'bard_03';

update avatar_templates set
  backstory = $bs$You're not licensed by any guild. You learned songs from your grandmother and her songs are older than the licensing guilds. The guild-people know you and don't bother you, mostly because every new guild-bard learns at least one of your tunes by mistake.$bs$,
  personality_tags = $tg$["folksy", "stubborn", "unflashy", "warm"]$tg$::jsonb,
  story_hooks = $hk$["A licensed guild-bard wants to apprentice with you, secretly.", "Your grandmother's songbook has surfaced in a private collection.", "A village wedding has booked you and only you."]$hk$::jsonb,
  signature_skill_id = 'sig_hearthsong'
where id = 'bard_04';

update avatar_templates set
  backstory = $bs$You sing slow and low and at twilight, mostly. People think it's a gimmick. It isn't. Twilight is when you're best, and the songs you write outside of it are usually thrown away.$bs$,
  personality_tags = $tg$["melancholy", "quiet-witted", "unhurried", "particular"]$tg$::jsonb,
  story_hooks = $hk$["An ex-lover from the old crooner-circuit has just released a song answering one of yours.", "A patron has commissioned a song that must, specifically, not be performed at twilight.", "A poet you respected has died and you're expected to perform the elegy."]$hk$::jsonb,
  signature_skill_id = 'sig_twilight_dirge'
where id = 'bard_05';

-- ---------------------------------------------------------------------
-- 4. Foreign-key constraint on signature_skill_id → skills(id).
--    Added last so all 35 skill rows already exist when the constraint
--    becomes enforceable. Idempotent: drop-if-exists then add.
-- ---------------------------------------------------------------------
alter table avatar_templates
  drop constraint if exists avatar_templates_signature_skill_fk;

alter table avatar_templates
  add constraint avatar_templates_signature_skill_fk
  foreign key (signature_skill_id)
  references skills (id)
  on delete set null;
