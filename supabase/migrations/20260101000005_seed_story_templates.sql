-- Seed: 3 story templates.
-- world_setting, dm_guidance, and opening_scene are written to be re-injected verbatim into the
-- DM system prompt every turn; that's how we keep the LLM on rails without long message history.

insert into public.story_templates
  (id, title, short_description, genre, world_setting, opening_scene, dm_guidance, cover_image_url, is_active, sort_order)
values
  ('the_sunken_crown',
   'The Sunken Crown',
   'A drowned dwarven hold has resurfaced after a thousand years. Within waits a relic that some say can rewrite a kingdom''s fate.',
   'high fantasy',
   'The kingdom of Veylan rests on cold, fjord-cut shores. For a thousand years a dwarven hold called Karak Brun lay submerged after a magical cataclysm split its dam. Last spring, the waters drew back. Karak Brun rose dripping, its iron gates ajar. The Sunken Crown — a circlet said to grant lawful authority to any who claim it — is rumored to be deep in the lord''s tomb. Veylan''s court has dispatched a single agent because a force would draw attention from rival kingdoms. Vibe: classic high fantasy, methodical dungeon crawl, dwarven runes glowing in cold water, traps, hidden vaults, a sense that the hold itself remembers. Key locations: the Iron Gate, the Drowning Hall, the Cinderforge, the Tomb of Lord Brundir.',
   'Cold spray slaps your face as the longboat scrapes onto the black sand of Karak Brun''s outer quay. The captain leaves you with a lantern, two days'' rations, and a curt nod. Before you, the iron gate of the dwarven hold yawns half-open. A trickle of seawater hisses across its threshold. From inside drifts a smell of wet stone, old smoke, and something else — iron, but warm. You are alone. The kingdom''s hopes ride on what you bring back.',
   '- Maintain a methodical, classic-dungeon-crawl pace. Reward investigation. Punish carelessness with traps.
- The dwarven hold is sentient in subtle ways: doors close, distant hammering is heard, runes flare for an instant.
- Encounters: drowned dwarven thralls, animated armor, a corrupted forge-spirit, finally Lord Brundir''s shade.
- DO NOT teleport the player out of the hold. The campaign happens entirely inside Karak Brun until the climax.
- DO NOT introduce sci-fi or modern technology. This is high fantasy.
- The Sunken Crown is the goal; don''t let the player claim it before defeating Lord Brundir''s shade.',
   null, true, 10),

  ('ashfall',
   'Ashfall',
   'The sun has not risen in fourteen days. Ash falls instead. You walk a dying road in search of a child rumored to still see green.',
   'dark fantasy',
   'A dark-fantasy / post-apocalyptic world. Two weeks ago the sun stopped rising. The sky bleeds a grey-orange light at noon at best. Fine ash drifts constantly, coating fields and mouths. Crops have died. Wells turn brackish. Most settlements are barricaded ruins now; the rest are cults of the new dark. Rumor on the road: a child in the village of Wenholt still sees colors and dreams green. Some say the child can sing the sun back. Others want the child silenced. The road from your starting hamlet to Wenholt is two weeks on foot — through dying forests, ash-clogged rivers, and the occasional thing that should not be moving. Vibe: hushed, mournful, harsh. NPCs speak briefly and don''t laugh. Key locations: the Hollow Inn, the Ash Mill, the Bone Orchard, Wenholt.',
   'Your boots leave grey prints. Each step kicks up a small puff of ash that hangs, then settles, slow. The road south is cracked. Far off you can hear something dragging — too rhythmic to be the wind. The hamlet behind you is no longer a place you can return to. Ahead, two weeks of road and the village of Wenholt. You have one canteen, half full.',
   '- Tone is sombre, hushed, sometimes outright bleak. Avoid quippy NPCs.
- Resources are precious. Make the player feel the weight of every potion, every meal.
- The ash is not just weather. It clings to wounds, dampens magic faintly, occasionally coats things that move.
- Encounters: ash-rotted travelers, a starving wolf-thing, a cultist patrol, finally the Pale Choir at Wenholt.
- DO NOT introduce a happy daylight scene. The sun does not return until the climax (and only if the player wins).
- DO NOT pivot to high fantasy or sci-fi. This is bleak dark fantasy.',
   null, true, 20),

  ('the_clockwork_heist',
   'The Clockwork Heist',
   'A reclusive industrialist has bought a senator. You have one night to break into his clockwork tower and steal the proof.',
   'steampunk mystery',
   'A steampunk city called Brassmere. Towering smokestacks, copper trams, gas-lit alleys, neighborhoods stratified by altitude (the rich live up where the air is clean). The reclusive industrialist Cyrus Vehl has, your patron believes, bribed Senator Marchpane to push a bill that would let his factories conscript orphans as ''apprentices''. Proof of the bribe — a ledger — sits in Vehl''s clockwork tower. You have one night before Vehl moves the ledger to a vault offshore. Vibe: heist, intrigue, mechanical puzzles, brief social manipulation, rooftop sprints, the constant smell of coal. NPCs speak in clipped Edwardian register. Key locations: the Clockmaker''s Alley, the Brass Foyer, the Gear Atrium, Vehl''s Office.',
   'Rain hisses on the tin roof above your head. From the alley below you can see Vehl''s clockwork tower — twelve stories of brass and copper, lit window by window from the inside. Your patron''s last whispered note crinkles in your palm: *Tonight or never. The ledger is on the eleventh floor. Do not let yourself be photographed.* A copper tram rattles past at street level, scattering pigeons.',
   '- Maintain a heist tempo: tense, sneaky, choices have noisy or quiet consequences.
- Time pressure is real. The player has roughly until dawn (roughly 10 turns of in-fiction time).
- Encounters: clockwork sentries, a paranoid foreman, a security automaton, finally a confrontation with Cyrus Vehl himself in his office.
- DO NOT pivot to fantasy or magic. Magic does not exist in Brassmere — only mechanical engineering, mostly poorly understood.
- DO NOT let the player simply walk in. There must be cost: stealth checks, time, or violence.
- The ledger is the goal; loot is fine, but the ledger must leave the tower with the player.',
   null, true, 30);
