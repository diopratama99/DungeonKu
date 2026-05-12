-- =====================================================================
-- DungeonKu — Demo template "Ember Outpost" (1/3): Template + Acts I, II
-- =====================================================================
-- Split into three migrations because PostgREST + Supabase migration
-- runners both have body-size limits we'd rather not test:
--   20260511000100  — this file: template row + Act I (road) + Act II (village hub)
--   20260511000200  — Acts III (approach choice) + IV (the four routes)
--   20260511000300  — Acts V (courtyard) + VI (sanctum) + VII (endings)
--                     PLUS every story_edges row (so all node ids exist
--                     before we reference them as edge targets) PLUS the
--                     story_templates.root_node_id update.
--
-- Run them in order. Each file is independently idempotent.
--
-- See STORY_ENGINE_REDESIGN.md and 20260511000000 for context.
-- =====================================================================

set search_path to dungeonku, public;

-- ---------------------------------------------------------------------
-- Template row
-- ---------------------------------------------------------------------
insert into story_templates
  (id, title, short_description, genre, world_setting, opening_scene,
   dm_guidance, cover_image_url, is_active, sort_order)
values
  ('ember_outpost',
   'The Ember Outpost',
   'A frontier cult has burned half a village and stolen the Smithlight. You have one chance to take it back — or to take something more.',
   'low fantasy',
   $ws$Ashbrook is a smithing village on the King's Road. For four generations its smiths have kept their forges lit from the same flame: the Smithlight, a small handheld lantern said to have been gifted by a wandering dwarf-priest. Tools blessed by it cut truer; wolves shy from cattle that wear ribbons singed in it; a candle lit from it does not gutter in any wind. None of this is loud magic. It is a small, working magic that makes a small, working life possible.

The Ember Order is a fire-cult. They believe sacred fire is hoarded by the unfaithful and must be returned to "the great burning." Six weeks ago they marched on Ashbrook in numbers, took the Smithlight from the smithy by force, killed three villagers in the doing, and retreated to a hilltop fort upriver. Petitions to the King's Reeve have gone unanswered. The village has hired you.

The Ember Outpost was a King's watchtower a century ago. The Order has reinforced the curtain wall and installed their own commander — a woman named Korr, who rides a black-faced mule and rarely shows her face. The outpost holds about thirty Order initiates, six watchmen, three fire-touched hounds, and one apprentice smith conscripted from the village. The Smithlight is kept in a small sanctum at the back of the keep.$ws$,
   $os$You crest the last rise on the King's Road. Below, Ashbrook smokes in two columns: one from the smithy chimney, working as it should; the other from a half-burned thatch roof, working as it should not. Beyond the village a chalk bluff rises from the river, and on top of it sits the Ember Outpost. The road forks ahead. Left descends to the village. Right curves up the bluff.$os$,
   'You are running on the new story-graph engine. Body text and option labels are authored ahead of time; only narrate flavor on pivotal nodes. Honor the player''s build choices — every class has its own paths, and they should feel different.',
   'assets/images/campaigns/covers/ember_outpost.png', true, 5)
on conflict (id) do update set
  title             = excluded.title,
  short_description = excluded.short_description,
  genre             = excluded.genre,
  world_setting     = excluded.world_setting,
  opening_scene     = excluded.opening_scene,
  dm_guidance       = excluded.dm_guidance,
  cover_image_url   = excluded.cover_image_url,
  is_active         = excluded.is_active,
  sort_order        = excluded.sort_order;

-- ---------------------------------------------------------------------
-- ACT I — The Road to Ashbrook
-- ---------------------------------------------------------------------

insert into story_nodes
  (id, template_id, type, body, speaker, speaker_profile, tags,
   on_enter_actions, ai_reskin_policy, sort_order)
values

('ember_outpost__intro', 'ember_outpost', 'scene',
 $b$The King's Road is hard mud underfoot, and the wind carries pine-smoke and something burned that should not have been burned — wool, or thatch, or both. Ahead, the road forks. Left drops into a shallow valley where a smithing village smokes in two columns. Right climbs a chalk bluff to the keep on top of it. You have heard the keep called the Ember Outpost. You have not heard it called anything good. A traveler is coming up the road toward you, not slowing.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_1"]$t$::jsonb, '[]'::jsonb,
 'pivotal_only', 100),

('ember_outpost__travel_dawn', 'ember_outpost', 'transition',
 $b$You push on now, to reach Ashbrook by mid-morning. The road is empty at this hour; only the chimney-smoke moves. You walk with the sun warming your back and the bluff with the outpost on it climbing slowly into your right peripheral, like a bad thought you're choosing not to look at.$b$,
 null, '{}'::jsonb, $t$["act_1"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"arrived_dawn","value":true}}]$a$::jsonb,
 'never', 110),

('ember_outpost__travel_dusk', 'ember_outpost', 'transition',
 $b$You stop and sleep in a roadside hollow, to arrive at Ashbrook at dusk. The fire you keep is small. Once during the night you wake to the distant howl of something that does not sound like a normal wolf, and you check your weapons by feel. By the time you near Ashbrook the sun is low and the village is gold-edged.$b$,
 null, '{}'::jsonb, $t$["act_1"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"arrived_dusk","value":true}}]$a$::jsonb,
 'never', 111),

('ember_outpost__village_outskirts', 'ember_outpost', 'scene',
 $b$The traveler is a thin man in a smith's leather apron, carrying a child on his back and a tied bundle at his hip. His left eyebrow is gone, recently. The child has not made a sound. "They came back two nights ago," the smith says, low and fast. "They wanted more iron. I had nothing left to give. The Reeve sent no one. Don't go to the village if you mean to live. Don't go to the keep at all." His voice cracks on the last word.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_1"]$t$::jsonb,
 '[]'::jsonb, 'pivotal_only', 120),

('ember_outpost__traveler_helped', 'ember_outpost', 'transition',
 $b$You press a half-day's rations and a coin into the smith's hand and tell him the road south is clear for two days at least. He stares at you for a long moment, swallows, and finally nods. "Tell Bren," he says — only that. Then he is past you and gone, the child still silent.$b$,
 null, '{}'::jsonb, $t$[]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"helped_traveler","value":true}},{"kind":"cost_resource","payload":{"amount":1}}]$a$::jsonb,
 'never', 121),

('ember_outpost__traveler_robbed', 'ember_outpost', 'transition',
 $b$You step into the smith's path and ask him for what he carries. He looks at you with something that is not surprise, hands over the coin and the bundle, and walks past you without slowing. The child on his back never takes its eyes off you. You will think about that face later than you would like to.$b$,
 null, '{}'::jsonb, $t$[]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"robbed_traveler","value":true}},{"kind":"grant_item","payload":{"item_id":"smiths_purse","qty":1}}]$a$::jsonb,
 'never', 122),

('ember_outpost__ashbrook_arrival', 'ember_outpost', 'scene',
 $b$Ashbrook is a single street curling around a green. There is a smithy whose chimney is alive, an inn with a bell on a post, a small stone chapel, and at least one house that no longer has a roof. A few villagers stand in the green doing nothing — not idling, exactly, but waiting. They watch you arrive without surprise. A woman in burnt clothes sits on the step of the roofless house, hands open in her lap. The smell of the village is woodsmoke and something charred and sweet you do not want to think about. Somewhere a hammer rings on metal — once, twice, then a long pause. Whoever is working at the smithy is not working hard.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_2"]$t$::jsonb,
 '[]'::jsonb, 'pivotal_only', 130),

-- ---------------------------------------------------------------------
-- ACT II — Ashbrook (the village hub)
-- ---------------------------------------------------------------------

('ember_outpost__ashbrook_hub', 'ember_outpost', 'choice',
 $b$The village is small enough to take in at a glance. The inn, the smithy, the chapel, the burnt house, the stable. Anyone you mean to talk to is within a stone's throw, but each of them will want their share of the day. The bluff with the Ember Outpost on it sits on the horizon like a promise.$b$,
 null, '{}'::jsonb, $t$["act_2", "hub", "replayable_actions"]$t$::jsonb,
 '[]'::jsonb, 'never', 140),

-- Inn
('ember_outpost__inn_dialog', 'ember_outpost', 'dialog',
 $b$The Inn is one room with five tables. Innkeeper Vela is a wiry woman with a livid burn on her right forearm; she does not hide it. She nods at you over the bar and pours something dark into a clay cup before you've said anything. "You're the one they sent for. Or you're not. I've stopped guessing. Sit. What do you want."$b$,
 'Innkeeper Vela',
 $sp$ {"tone":["dry","direct","quietly-angry","fair"], "default_mood":"watchful"} $sp$::jsonb,
 $t$["act_2", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'never', 141),

('ember_outpost__inn_outpost_info', 'ember_outpost', 'dialog',
 $b$Vela sets her cloth down. "Gate is on the east face. Two guards day, four night. Watchman called Halve runs the day shift and he'll listen if you've got coin or a story. Chapel inside the keep — they pray to a flame they keep there, not a god. Smithy's inside too, with our boy Tyne in it, working for them now whether he means to or not." She looks at you. "That what you wanted?"$b$,
 'Innkeeper Vela',
 $sp$ {"tone":["dry","direct"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_gate_layout","value":true}}]$a$::jsonb,
 'never', 142),

('ember_outpost__inn_korr_info', 'ember_outpost', 'dialog',
 $b$Vela's face changes when you ask about the Commander. "Korr," she says, like the name is food she has been chewing too long. "She came through here once before all this. Six, seven years back. Stayed three nights, paid in good coin, didn't drink. Asked questions about our smith — Bren — like she knew the family. I should've asked her name then. I didn't." She pours herself a cup. "Whatever she's doing up there, it isn't only about the lantern."$b$,
 'Innkeeper Vela',
 $sp$ {"tone":["dry","reluctant","old-pain"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_korr_history","value":true}}]$a$::jsonb,
 'never', 143),

('ember_outpost__inn_drink', 'ember_outpost', 'dialog',
 $b$Vela pours from the dark bottle without asking. The drink is bitter and warming and tastes like something a grandmother would make. She watches you finish it. "On the house," she says, then quietly, "tonight."$b$,
 'Innkeeper Vela',
 $sp$ {"tone":["dry"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"heal_player","payload":{"dice":"d4"}}]$a$::jsonb,
 'never', 144),

('ember_outpost__inn_room', 'ember_outpost', 'dialog',
 $b$Vela hands you a key on a leather thong. "Top of the stairs, on the right. Bar the door. Don't open it for anyone who knocks polite — anyone polite up here at night isn't ours." You sleep four hours dreamlessly. When you wake, your pack is exactly where you left it, and there is bread on the chair by the bed.$b$,
 'Innkeeper Vela',
 $sp$ {"tone":["dry"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"heal_player","payload":{"dice":"d8"}},{"kind":"set_flag","payload":{"key":"rested","value":true}}]$a$::jsonb,
 'never', 145),

-- Smith
('ember_outpost__smith_dialog', 'ember_outpost', 'dialog',
 $b$Bren's smithy is open on three sides. The forge is hot but the work on the bench is small — a horseshoe, a pot-handle, ordinary things. Bren is a heavy woman in a leather apron with grey at her temples; her left hand is wrapped in clean linen. She doesn't look up. "You're the one come for the lantern. Or you're not. I keep saying that today." She turns the horseshoe on the anvil. "Ask what you came to ask."$b$,
 'Smith Bren',
 $sp$ {"tone":["plain","heavy","grieving","blunt"], "default_mood":"working-through-it"} $sp$::jsonb,
 $t$["act_2", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'never', 150),

('ember_outpost__smith_korr_info', 'ember_outpost', 'dialog',
 $b$Bren's hammer stops mid-swing. She looks at you for the first time. Her eyes are the same color as the sister she will not name. "Korr is my sister. Older by three years. She left the village when she was seventeen and the church we had then was bad, and she didn't come home until she came home with thirty Order men at her back to take the lantern. I don't know what they did to her in those years between. I don't think she does either, anymore." The hammer goes on the anvil. "If you can do it without killing her, do it without killing her. If you can't, I'll understand."$b$,
 'Smith Bren',
 $sp$ {"tone":["plain","heavy","grieving"], "default_mood":"resigned"} $sp$::jsonb,
 $t$["pivotal", "act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_korr_sister","value":true}}]$a$::jsonb,
 'pivotal_only', 151),

('ember_outpost__smith_anvil_help', 'ember_outpost', 'dialog',
 $b$You take up Bren's hammer. The cracked horseshoe sings under the heat the way it should, and Bren watches you work without comment until you set the finished piece down. Then she nods, once, and goes to the back of the smithy. She comes back with a forge-hammer wrapped in oiled cloth. "This was my father's. I'd be using it if my hand were whole. Take it. Bring it back if you can."$b$,
 'Smith Bren',
 $sp$ {"tone":["plain","quiet","approving"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"forge_friend","value":true}},{"kind":"grant_item","payload":{"item_id":"forge_hammer","qty":1}}]$a$::jsonb,
 'never', 152),

('ember_outpost__smith_repair', 'ember_outpost', 'dialog',
 $b$Bren takes your worn gear, looks at it without much expression, and works for the better part of an hour with her good hand. When she's done it's not pretty but it'll hold an edge another two seasons. She refuses payment beyond what you've already given. "Bring the lantern back," she says. "That's payment."$b$,
 'Smith Bren',
 $sp$ {"tone":["plain"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"cost_resource","payload":{"amount":3}},{"kind":"set_flag","payload":{"key":"gear_repaired","value":true}}]$a$::jsonb,
 'never', 153),

-- Priest
('ember_outpost__priest_dialog', 'ember_outpost', 'dialog',
 $b$The chapel is one room with three rows of benches and a stone altar with nothing on it. Brother Tarin is a thin old man whose vestments are mended cleanly. He is sitting on the front bench, not praying, only sitting. "There used to be a candle here lit from the lantern," he says, before you can speak. "It would not gutter. The wind could come in the door and the candle would not gutter. They took the lantern, and now the candle does what every other candle does. I find I am angrier than I expected to be."$b$,
 'Brother Tarin',
 $sp$ {"tone":["calm","aged","quietly-furious","precise"], "default_mood":"contemplative-anger"} $sp$::jsonb,
 $t$["act_2", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'never', 160),

('ember_outpost__priest_smithlight_info', 'ember_outpost', 'dialog',
 $b$Tarin folds his hands. "The Smithlight is not a god. It is a working. A wandering dwarf-priest gave it to the first Bren-of-Ashbrook four generations ago because the family fed him when he had no work. It blesses craft, and keeps wolves off cattle, and a candle lit from it does not gutter. That is all. There is no doctrine. No prayers. There is a flame, and the flame is kept lit, and small good things follow. The Order misunderstands it. They think it is hoarded sacred fire. It is not. It is a kindness from one stranger to another, kept alive."$b$,
 'Brother Tarin',
 $sp$ {"tone":["calm","precise"]} $sp$::jsonb,
 $t$["pivotal", "act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_relic","value":true}}]$a$::jsonb,
 'pivotal_only', 161),

('ember_outpost__priest_blessing', 'ember_outpost', 'dialog',
 $b$Tarin marks your forehead with oil from a small clay jar. The oil is cold, then warm, then cold. "Whatever you find up there," he says, "be honest with it. Lying to it will hurt you more than it." He is looking past you when he says this. You feel something in your chest that was tight loosen by a small, helpful amount.$b$,
 'Brother Tarin',
 $sp$ {"tone":["calm","gentle"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"heal_player","payload":{"dice":"d10"}},{"kind":"set_flag","payload":{"key":"blessed","value":true}}]$a$::jsonb,
 'never', 162),

('ember_outpost__priest_pray', 'ember_outpost', 'dialog',
 $b$You sit on the back bench and try to pray. You are not sure what you are praying to. After a while Tarin sits next to you without speaking. The room is very quiet, in a way that feels intentional. After a longer while, you stand up. Tarin doesn't follow you out.$b$,
 'Brother Tarin',
 $sp$ {"tone":["silent"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"prayed","value":true}}]$a$::jsonb,
 'never', 163),

-- Burnt-house woman (Mira)
('ember_outpost__burnt_woman_dialog', 'ember_outpost', 'dialog',
 $b$The woman on the step of the roofless house does not turn her head when you approach. Her name, you learn from the way the children pass and call to her, is Mira. Her hands are open on her lap, palms up, and there is soot in the lines of them. She speaks before you do. "My husband was in the second room. They didn't mean to. They thought it was empty. That's what one of them said to another while I was hiding in the well. 'I thought it was empty.'" She looks up at you. "I've been turning that sentence over for two weeks. I cannot get it to mean anything I can use."$b$,
 'Mira',
 $sp$ {"tone":["flat","exhausted","unstartled","piercing"], "default_mood":"hollow"} $sp$::jsonb,
 $t$["pivotal", "act_2", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'pivotal_only', 170),

('ember_outpost__burnt_woman_helped', 'ember_outpost', 'transition',
 $b$You spend the better part of the afternoon clearing what you can clear with your hands, and stacking what stones still hold their shape. Mira works beside you without speaking. When you stop, she presses a small thing into your palm — a round amulet of dark wood with a faint warm spot on one side, like it had been lit by a candle that did not gutter. "He carved it the spring we married," she says. "I want it back. I want it back enough that I'm giving it to you, do you understand?"$b$,
 'Mira',
 $sp$ {"tone":["flat","trusting-against-odds"]} $sp$::jsonb,
 $t$["pivotal", "act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"mira_grateful","value":true}},{"kind":"grant_item","payload":{"item_id":"miras_amulet","qty":1}},{"kind":"set_flag","payload":{"key":"comforted_mira","value":true}}]$a$::jsonb,
 'pivotal_only', 171),

('ember_outpost__burnt_woman_comforted', 'ember_outpost', 'dialog',
 $b$You sit next to Mira. You don't talk. After a long time she says, "Thank you for not telling me anything." You sit a little longer, and then she says, "Go on. Don't stop until it's done. That's what he would have said."$b$,
 'Mira',
 $sp$ {"tone":["flat","quiet"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"comforted_mira","value":true}}]$a$::jsonb,
 'never', 172),

('ember_outpost__burnt_woman_info', 'ember_outpost', 'dialog',
 $b$Mira tells you about the night, in a voice with no inflection. They came in three groups. One went straight for the smithy. One held the green. One went house to house with torches, looking for "irons" — for ironwork blessed by the lantern. They said grace before they did it. That detail seems to bother her almost as much as the rest.$b$,
 'Mira',
 $sp$ {"tone":["flat","precise"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_attack_details","value":true}}]$a$::jsonb,
 'never', 173),

-- Orphan (Jen)
('ember_outpost__orphan_dialog', 'ember_outpost', 'dialog',
 $b$There is a boy of about ten sitting on the chapel wall, swinging his legs and not looking at any of the adults. His hair has been cut roughly with a knife. When you come over, he watches you sideways without turning his head. "My da used to go up the bluff," he says, before you ask. "Before the Order came. There's a way up the back. He showed me once, but I'm not telling you for free."$b$,
 'Jen',
 $sp$ {"tone":["sharp","wary","hopeful-against-his-will"], "default_mood":"defensive"} $sp$::jsonb,
 $t$["act_2", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'never', 180),

('ember_outpost__orphan_fed', 'ember_outpost', 'dialog',
 $b$You hand the boy what bread you have on you and a wedge of cheese. He eats it like he is afraid you will take it back. When he is done he wipes his mouth on his sleeve and looks you in the face for the first time. "My da's name is Quint. He's at the old fox-den past the willow. Tell him Jen sent you and to give back what he took from the cupboard." He pulls a bent piece of wire from his sleeve and presses it into your hand. "It's better than nothing for a lock," he says.$b$,
 'Jen',
 $sp$ {"tone":["sharp","slightly-warmed"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"cost_resource","payload":{"amount":2}},{"kind":"set_flag","payload":{"key":"orphan_friend","value":true}},{"kind":"set_flag","payload":{"key":"knows_smuggler_quint","value":true}},{"kind":"grant_item","payload":{"item_id":"bent_lockpick","qty":1}}]$a$::jsonb,
 'never', 181),

('ember_outpost__orphan_father', 'ember_outpost', 'dialog',
 $b$"My da," the boy says carefully, "used to be a smuggler. Now he is a smuggler who lives in a hole. The fox-den past the willow. If you go without a thing for me, he won't talk to you. He's not nice. He used to be." He looks down at his hands. "Tell him I said the cup is in the cupboard. He'll know."$b$,
 'Jen',
 $sp$ {"tone":["sharp","careful"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_smuggler_quint","value":true}}]$a$::jsonb,
 'never', 182),

('ember_outpost__orphan_played', 'ember_outpost', 'dialog',
 $b$You sit with Jen on the wall for a while. He shows you how to flick a stone into the chapel bell so it makes a small hum without ringing properly. He laughs once. After he laughs he looks angry, like he had not meant to.$b$,
 'Jen',
 $sp$ {"tone":["sharp","wary"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"children_remember","value":true}}]$a$::jsonb,
 'never', 183),

-- Stable (Hask)
('ember_outpost__stable_dialog', 'ember_outpost', 'dialog',
 $b$Old Hask is asleep on a hay bale when you find him, and he wakes before you've made any sound — there's a knife in his hand before he has finished sitting up. Then he sees you and slowly puts the knife down. "Sorry, sorry. Habit. The Order took two of my horses. The two best, of course. Bastards." He spits. "What do you want."$b$,
 'Old Hask',
 $sp$ {"tone":["gruff","tired","still-sharp"], "default_mood":"prickly"} $sp$::jsonb,
 $t$["act_2", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'never', 190),

('ember_outpost__stable_paths_info', 'ember_outpost', 'dialog',
 $b$Hask draws in the dirt with a stick. "Gate's east. Easiest, most watched. Back of the bluff," he scratches a curve, "is a chalk slope. I've climbed it three times in my life. Two of those I was younger and stupider. Take it slow and you can do it. There's a ledge near the top — keep left of it or you'll go over." He draws a small X. "There. Don't go right of the X. Promise me that."$b$,
 'Old Hask',
 $sp$ {"tone":["gruff","earnest"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_back_path","value":true}}]$a$::jsonb,
 'never', 191),

('ember_outpost__stable_horses', 'ember_outpost', 'dialog',
 $b$Hask talks about the two horses for a long time. The mare was named Plum and the gelding was named Bishop. He cried a little, in passing, and then was annoyed at himself. He gave you nothing except this, but when you left you felt slightly heavier in a way you could not name.$b$,
 'Old Hask',
 $sp$ {"tone":["gruff","grieving"]} $sp$::jsonb,
 $t$["act_2"]$t$::jsonb, '[]'::jsonb, 'never', 192)

on conflict (id) do nothing;
