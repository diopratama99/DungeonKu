-- =====================================================================
-- Ember Outpost (2/3) — Acts III (approach) + IV (the four routes)
-- =====================================================================
-- See 20260511000100 header for the split rationale.
-- =====================================================================

set search_path to dungeonku, public;

insert into story_nodes
  (id, template_id, type, body, speaker, speaker_profile, tags,
   on_enter_actions, ai_reskin_policy, sort_order)
values

-- ---------------------------------------------------------------------
-- ACT III — Choosing an Approach
-- ---------------------------------------------------------------------

('ember_outpost__leave_for_outpost', 'ember_outpost', 'transition',
 $b$You leave Ashbrook with the village in your back. None of them say goodbye. Vela watches you go from the doorway of the inn. Mira does not turn her head. Jen, on the chapel wall, raises one hand exactly once.$b$,
 null, '{}'::jsonb, $t$["act_3"]$t$::jsonb, '[]'::jsonb, 'never', 200),

('ember_outpost__outpost_view', 'ember_outpost', 'scene',
 $b$You climb the old goat-track halfway up the bluff and stop where it bends. From here you can see the whole face of the Ember Outpost. The east gate is set in a curtain wall about fifteen paces tall, with a brazier burning at it day and night and at least two figures in red moving on its parapet. The wall to the south curves up against the cliff edge — you can see, against the sky, where the chalk drops sheer to the river below. To the north, farther around, there is a draw choked with brambles where Hask said the back path is. Somewhere underground, the bluff is honeycombed with old workings — that is what Bren's father always said, and Bren says it now too. You can choose your way in.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_3"]$t$::jsonb, '[]'::jsonb,
 'pivotal_only', 210),

('ember_outpost__decide_approach', 'ember_outpost', 'choice',
 $b$Four ways present themselves, in roughly increasing strangeness: the front gate, the back climb, the smuggler's tunnel if Quint will help you, and the dwarven workings if you can find a way down to them at all.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_3"]$t$::jsonb,
 '[]'::jsonb, 'pivotal_only', 211),

-- ---------------------------------------------------------------------
-- ACT IV-A — Front Gate
-- ---------------------------------------------------------------------

('ember_outpost__gate_approach', 'ember_outpost', 'scene',
 $b$You walk up the bluff path openly, the way a courier might. The gate is a heavy oak door banded with iron and standing half-open. A brazier in a cage of black iron burns to one side, and a man in red leathers is leaning on the wall next to it with the bored look of a guard who has not had to do anything difficult in some time. He sees you and raises one eyebrow. "State your business," he says. The way he says it makes it clear he is willing to be talked to and equally willing not to be.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb, '[]'::jsonb, 'never', 220),

('ember_outpost__gate_dialog', 'ember_outpost', 'dialog',
 $b$Watch Sergeant Halve is broader than he is tall, and the red leathers look like he has been comfortable in them a long time. He has a gold ring in one ear and a face that has been broken at least once. He smiles at you the way a man smiles when he is not sure yet whether he is going to be pleased or angry, and is willing to be either. "You have a moment of my attention. Don't waste it, friend."$b$,
 'Watch Sergeant Halve',
 $sp$ {"tone":["affable","corrupt","not-stupid","easy-with-violence"], "default_mood":"willing"} $sp$::jsonb,
 $t$["pivotal", "act_4"]$t$::jsonb, '[]'::jsonb, 'pivotal_only', 221),

('ember_outpost__gate_bribed', 'ember_outpost', 'transition',
 $b$Halve weighs the coin in his hand for a long moment, says nothing, and then steps aside. He does not look at you on your way past. "Walk slow," he says, mostly to himself. "Walk slow."$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"cost_resource","payload":{"amount":5}},{"kind":"set_flag","payload":{"key":"entered_via_bribe","value":true}}]$a$::jsonb,
 'never', 222),

('ember_outpost__gate_bluffed', 'ember_outpost', 'transition',
 $b$You give Halve a story so calm and plausible he forgets, halfway through it, that he has heard others like it before. By the end he is nodding and waving you through with the impatience of a man who does not want to be caught having been polite.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"entered_via_bluff","value":true}}]$a$::jsonb,
 'never', 223),

('ember_outpost__gate_intimidated', 'ember_outpost', 'transition',
 $b$You do not raise your voice, exactly. You only stand a little closer than Halve was expecting and let your weight settle into your front foot. He looks at you, considers his men, considers the size of his afternoon, and steps to one side without comment. He will remember this. So will you.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"entered_via_intimidate","value":true}}]$a$::jsonb,
 'never', 224),

('ember_outpost__gate_combat', 'ember_outpost', 'combat',
 $b$Halve's smile does not go away — it only changes character. He takes two steps back into the gateway and shouts a single name, and a second man is there before the name is finished. Steel sings.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_4", "combat"]$t$::jsonb,
 $a$[{"kind":"start_combat","payload":{"enemy_set_id":"gate_guards"}}]$a$::jsonb,
 'pivotal_only', 225),

('ember_outpost__gate_combat_won', 'ember_outpost', 'transition',
 $b$Halve is on the ground with his eyes still open. The other man is leaning against the gate frame in a way the dead lean. You step over them both. The brazier hisses as you pass it. You can hear, distantly, a horn — but it is uncertain, a single short note, like whoever blew it was not sure they meant to.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"entered_via_combat","value":true}},{"kind":"set_flag","payload":{"key":"alarm_uncertain","value":true}}]$a$::jsonb,
 'never', 226),

-- ---------------------------------------------------------------------
-- ACT IV-B — Back Path
-- ---------------------------------------------------------------------

('ember_outpost__back_path_climb', 'ember_outpost', 'scene',
 $b$The draw is choked with brambles, but underneath the brambles the chalk is honest. You find the goat-track Hask described and follow it up. About a third of the way the path narrows to a ledge no wider than your foot. You can see the ledge Hask warned you about — a wedge of rock that looks easy and is not. Below it the bluff drops to brown river. Above it the chalk goes pale in the light.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb, '[]'::jsonb, 'never', 230),

('ember_outpost__back_path_top', 'ember_outpost', 'transition',
 $b$You come up onto the back wall of the Ember Outpost where the chalk meets the curtain. The wall here is older — it was the King's watchtower, before. There is a gap where masonry has fallen. You slip through it into a goat-paddock that no longer holds goats, and from there into the courtyard.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"entered_via_back","value":true}}]$a$::jsonb,
 'never', 231),

('ember_outpost__back_path_falter', 'ember_outpost', 'transition',
 $b$You move too fast on the bad ledge. The chalk crumbles under your right foot and for a long, expensive second you are fully airborne. You catch a root with one hand, and a piece of yourself with the other, and pull yourself up against the cliff. You sit very still for some time before you go on. You are alive. You are not as fine as you were.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"damage_player","payload":{"dice":"d6","element":"neutral"}}]$a$::jsonb,
 'never', 232),

-- ---------------------------------------------------------------------
-- ACT IV-C — Smuggler's Tunnel
-- ---------------------------------------------------------------------

('ember_outpost__smuggler_meet', 'ember_outpost', 'dialog',
 $b$The fox-den past the willow is exactly that — a hollow under a clay bank, lined with sacking and one stub of candle. Quint is a long-jawed man in a grease-stained coat. He sees you coming a long way off and is not pleased. By the time you are close enough to talk to, he has a knife on his belt unbuckled. "State your business and don't lie. I'll know."$b$,
 'Quint the Smuggler',
 $sp$ {"tone":["paranoid","dry","damaged","oddly-tender-when-startled"], "default_mood":"defensive"} $sp$::jsonb,
 $t$["act_4", "dialog_hub"]$t$::jsonb, '[]'::jsonb, 'never', 240),

('ember_outpost__smuggler_paid', 'ember_outpost', 'transition',
 $b$Quint takes the coin without thanks and pulls a board aside in the back wall of the den, revealing a black opening that smells of damp clay. "Walk straight. Don't take side passages. They go to bad places. And don't tell anyone in the village. Some of them think I'm dead. I'd like that to keep."$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"cost_resource","payload":{"amount":7}},{"kind":"set_flag","payload":{"key":"entered_via_tunnel","value":true}}]$a$::jsonb,
 'never', 241),

('ember_outpost__smuggler_dealing', 'ember_outpost', 'dialog',
 $b$You tell Quint that Jen sent you. You say the cup is in the cupboard. Quint goes very still. Then he sits down on the clay floor of the fox-den, a little harder than he meant to, and is quiet for a while. "Tell him it's not in the cupboard, it's in the loose stone behind the cupboard. Tell him I knew he'd find it. Tell him —" he stops. "Tell him I'm sorry. Just that." He stands up. Pulls the board aside. Hands you a stub of marked wax. "This will see you through to the sanctum if you show it to no one until you need it. Walk straight. Don't take side passages."$b$,
 'Quint the Smuggler',
 $sp$ {"tone":["careful","cracked-open","old-pain"]} $sp$::jsonb,
 $t$["pivotal", "act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"quint_friendly","value":true}},{"kind":"set_flag","payload":{"key":"entered_via_tunnel","value":true}},{"kind":"grant_item","payload":{"item_id":"sanctum_wax_seal","qty":1}}]$a$::jsonb,
 'pivotal_only', 242),

('ember_outpost__smuggler_threatened', 'ember_outpost', 'transition',
 $b$You make it clear to Quint that you have come too far for him to be a problem. He stares at you for a long moment, then steps aside without a word. The board comes off the back wall. You walk into the dark with him watching your back the whole way. He will tell someone you were here, eventually. You walk faster.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"quint_angry","value":true}},{"kind":"set_flag","payload":{"key":"entered_via_tunnel","value":true}}]$a$::jsonb,
 'never', 243),

('ember_outpost__tunnel_walk', 'ember_outpost', 'scene',
 $b$The tunnel is older than Quint. It is older than Ashbrook. The walls in places are limewashed in patterns whose meaning you do not know. About halfway through, the floor sinks ankle-deep in cold groundwater that smells of nothing in particular; you wade. The air after that is dry, then dryer. You pass a side-passage that breathes warm. You walk straight, the way Quint said. Eventually the tunnel rises and ends in a small wooden hatch held closed with one bent nail.$b$,
 null, '{}'::jsonb, $t$["act_4"]$t$::jsonb, '[]'::jsonb, 'never', 244),

-- ---------------------------------------------------------------------
-- ACT IV-D — Dwarven Workings (Blacksmith / sig_iron_song easter egg)
-- ---------------------------------------------------------------------

('ember_outpost__dwarf_tunnel', 'ember_outpost', 'scene',
 $b$You leave the goat-track halfway up the bluff and slip down a fault in the chalk that no goat would care about. The fault opens into a low stone room — old work, dwarven work, the kind of fitted blocks you only see in Bren's father's stories. At the back of the room is a sealed doorway, and into the lintel of the doorway is set a single iron tuning-fork the size of your forearm. The wall around it is patient with waiting.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_4"]$t$::jsonb,
 '[]'::jsonb, 'pivotal_only', 250),

('ember_outpost__dwarf_tunnel_open', 'ember_outpost', 'transition',
 $b$You strike the iron fork the way a smith strikes iron — short, true, on the second harmonic. The fork sings, and the seal answers. The fitted blocks slide aside without sound. You step through into a passage that has not been walked in a long time, but that knows you walked it now.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"dwarven_passage","value":true}}]$a$::jsonb,
 'pivotal_only', 251),

('ember_outpost__forge_secret', 'ember_outpost', 'scene',
 $b$The dwarven passage opens into a small chamber that smells of dry iron. On one wall, an engraving: a dwarf-priest holding a small lantern out to a smith, who kneels with hands open. Beneath the engraving in dwarven runes is a sentence. You can read it, more or less. It says: "A gift, kept lit, is a gift." There is a way out of this chamber too, into a back stair you suspect leads up into the smithy of the outpost itself. You know more about the Smithlight now than anyone in the outpost knows.$b$,
 null, '{}'::jsonb, $t$["pivotal", "act_4"]$t$::jsonb,
 $a$[{"kind":"set_flag","payload":{"key":"knows_smithlight_origin","value":true}},{"kind":"set_flag","payload":{"key":"entered_via_dwarf","value":true}}]$a$::jsonb,
 'pivotal_only', 252),

('ember_outpost__dwarf_tunnel_break', 'ember_outpost', 'combat',
 $b$You decide the seal is just stone and your problem is just steel. You set to it with what tools you have. The fitted blocks resist longer than you expected; the noise of it is worse than you expected; and when the seal finally yields, two of the dwarven wards stamped into its underside flare and lash at you like coiled wire.$b$,
 null, '{}'::jsonb, $t$["act_4", "combat"]$t$::jsonb,
 $a$[{"kind":"start_combat","payload":{"enemy_set_id":"dwarven_wards"}},{"kind":"set_flag","payload":{"key":"dwarven_passage","value":true}},{"kind":"set_flag","payload":{"key":"broke_dwarven_seal","value":true}}]$a$::jsonb,
 'never', 253)

on conflict (id) do nothing;
