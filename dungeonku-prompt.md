# Master Prompt: DungeonKu — AI Dungeon Master Mobile App

> Copy-paste prompt ini ke Claude Code / Cursor. Section di bawah `---` adalah promptnya.

---

# Project: DungeonKu

You are helping me build **DungeonKu**, a mobile DnD-style game app where the Dungeon Master is powered by an LLM. I'm building this partly to learn AI orchestration patterns. Read this entire spec before writing any code, then ask me clarifying questions before scaffolding.

## Tech Stack (fixed — do not suggest alternatives)

- **Frontend:** Flutter (latest stable). State management: Riverpod 2.x. Routing: go_router.
- **Backend:** Supabase
  - Postgres for game state, campaigns, characters, message history
  - Auth (email + Google sign-in)
  - Edge Functions (Deno/TypeScript) for all LLM calls — the Flutter client must NEVER call the LLM provider directly
  - Row Level Security on every table
- **LLM:** OpenAI API, model `gpt-4o` (make the model name an env var so I can swap it). Called from Edge Functions only. Use OpenAI's structured outputs feature (`response_format: { type: "json_schema", ... }`) to enforce the response schema — do not rely on prompt-based JSON.

## Product Spec

### Core loop
Solo player chats with an AI Dungeon Master. The DM narrates the world, presents situations, and responds to the player's actions. Most turns, the player picks from 3 pre-generated action options (sometimes 5 in pivotal moments) — these are resolved cheaply without an LLM call. The LLM is invoked only on key moments: free-text actions, story-significant choices, and dice-roll outcomes. The player has a character with stats, inventory, level, skills, and a base element. The DM weaves these into the narrative.

### MVP scope
- **Solo player only.** No multiplayer, no real-time party.
- **Up to 3 characters per user profile.** Characters live at the profile level (not the campaign level). When starting a new campaign, the user picks one of their existing characters (or creates a new one if they have < 3 slots). Characters can be edited (name, cosmetic) and deleted from a Characters screen. Deleting a character with active campaigns must warn the user.
- **Multiple campaigns per user**, each saved independently and resumable. A character can be used across multiple campaigns; the character's level/inventory/state is **per-campaign-run**, not shared across campaigns (each campaign has its own snapshot).
- **Persistent state per campaign:** character snapshot (stats, inventory, level/XP, skills, status effects), full message history, world memory/summary, phase, boss progression, side mission progress.

### Screens (minimum)
1. **Auth** — sign in / sign up
2. **Home / Characters roster** — shows the user's up to 3 characters with create/edit/delete; entry point to start or resume campaigns
3. **Campaigns list** — user's campaigns; resume, delete, see status (active/completed) and which character is in it
4. **Template picker** — when creating a new campaign, user picks from a small set of pre-made story templates
5. **Character creation** — name, **job/class** (which determines starting stats AND base element), starting stats are derived from class
6. **Game screen** — the main screen, see below
7. **Settings** — sign out, model selection (optional)

### Campaign templates (important)
To keep player exploration bounded and minimize API costs, every new campaign starts from a **template**. Templates are not user-generated — they're seeded server-side and read-only for MVP.

Each template defines:
- `id`, `title`, `cover_image` (optional), `short_description`
- `genre` (e.g., high fantasy, dark fantasy, sci-fi, post-apocalyptic, mystery)
- `world_setting` — a paragraph describing the world: tone, key locations, factions, vibe
- `bosses` — a small array (2–4) of major antagonists/milestones, each with name, short description, and rough difficulty/order
- `opening_scene` — the DM's first narration when the campaign starts
- `dm_guidance` — bullet points injected into the DM's system prompt: what the DM should emphasize, what's off-limits, tone to maintain

**Why this matters for orchestration:** the template's `world_setting`, `bosses`, and `dm_guidance` get injected into the system prompt every turn. This:
- Keeps the DM on-rails — it won't randomly teleport the player to a sci-fi world mid high-fantasy campaign
- Gives the LLM clear narrative goalposts (the bosses) so the story has direction
- Reduces token usage because we don't need long message history to maintain world consistency — the world is re-asserted in the system prompt every turn

Seed 3–5 templates in a migration so the app is usable immediately. Examples:
- "The Sunken Crown" — high fantasy, 3 bosses, classic dungeon crawl vibe
- "Ashfall" — dark fantasy/post-apocalyptic, 2 bosses, survival tone
- "The Clockwork Heist" — steampunk mystery, 4 bosses, intrigue-focused

### Bosses & progression tracking
Track boss state per campaign in a `campaign_bosses` table (status: `unencountered` | `encountered` | `defeated`). The DM gets the current boss states injected each turn so it knows what's been resolved and what's still ahead. When all bosses are defeated, the DM should narrate an ending and the campaign is marked `completed`. The DM's structured output should also be able to emit `boss_status_change` events as part of `state_changes` so the Edge Function can update boss progression.

### Game screen layout (critical — get this right)
This is the main screen the user spends 95% of their time on. Visual style: **pixelated classic / retro RPG aesthetic** (think early Final Fantasy, Chrono Trigger, modern indie like Sea of Stars). Use a pixel-style font (e.g., "Press Start 2P" or "VT323"), chunky borders, and a muted/parchment color palette. The chat itself can still be readable (don't go full 8-bit text), but UI chrome (buttons, frames, dice, inventory icons) should feel pixelated and nostalgic.

- **Top:** campaign name + small back button + a subtle pixel-style **phase indicator** (e.g., 4 small icons or a chunky progress bar showing intro/rising/climax/resolution)
- **Middle (scrollable):** chat messages
  - DM messages styled like narration in a parchment-toned bubble or boxed frame; pure narration in italic or a different color from spoken NPC dialog
  - Player messages on the opposite side, simpler styling
  - Auto-scroll to bottom on new message
  - Loading indicator (pixel-art spinner) while DM is "thinking"
- **Action panel (above the input bar):** 3 (sometimes 5) **action option buttons** generated for the current turn. Each button has a label and a small icon hinting at its kind (sword for combat-template, sparkle for situational, exclamation for pivotal). Tap = submit. This is what the player uses 70–80% of turns.
- **Bottom input bar (fixed):**
  - **Stats button** (left) — opens character sheet bottom sheet (HP, level, XP, stats, inventory, skills, status effects, base element). Read-only for MVP.
  - **Custom action toggle** — taps reveal the text field for free-text input (collapsed by default to encourage button use; LLM call is more expensive)
  - Text field + Send button (only visible when toggle is open)
- **Dice roll overlay:** when the DM emits `requires_roll`, the action panel locks and a 3D dice animation overlay appears. Player taps to roll, animation plays for ~1.5s, settles on the server-determined result, then DM narration of the outcome appears.
- **Side mission toast:** when a new side mission triggers, a small pixel-styled banner slides in from the top: "New side quest: [title]"

### What the LLM does (and doesn't)
- The LLM is **only** the storyteller / DM. Its job is narrative continuity, presenting choices, describing outcomes, and guiding the adventure.
- The LLM should reference the character's stats and inventory in its narration when relevant (e.g., "Your Strength of 16 lets you shove the door open").
- For MVP, **the LLM does not directly mutate game state.** State changes (gaining items, taking damage, leveling up) happen through structured outputs the Edge Function parses — see the orchestration section.
- No dice rolling logic in the LLM itself. If a roll is needed, the Edge Function rolls it deterministically and feeds the result back to the LLM for narration.

## Character System

### Classes (MVP — 6 classes)
Each class determines starting stats, HP, base element, resource type (MP for magic users, Stamina for physical), and starting skills.

| Class | Base Element | Resource | STR | DEX | CON | INT | WIS | CHA | HP | MP/Stam | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Warrior | Neutral | Stamina | 16 | 12 | 14 | 10 | 10 | 11 | 30 | 20 | Tank, melee |
| Rogue | Neutral | Stamina | 11 | 16 | 12 | 13 | 12 | 12 | 22 | 18 | Stealth, crit |
| Mage | Player picks: Fire/Water/Wind/Earth/Lightning/Dark | MP | 9 | 12 | 11 | 16 | 14 | 12 | 18 | 30 | Caster |
| Priest | Light | MP | 11 | 10 | 13 | 12 | 16 | 14 | 22 | 26 | Healer |
| Ranger | Wind | Stamina | 12 | 16 | 13 | 11 | 14 | 11 | 24 | 22 | Ranged |
| Blacksmith | Neutral | Stamina | 15 | 11 | 15 | 12 | 11 | 11 | 28 | 22 | Craft, durable |

For Mage, the player picks one of 6 sub-elements at creation. Light is exclusive to Priest. Neutral is for non-magical classes.

### Skill resource system (MP / Stamina)
- **MP-using classes** (Mage, Priest): every skill has an `mp_cost`. If MP < cost, the skill cannot be selected (button disabled). MP regenerates slowly out of combat (e.g., +5 per 3 turns of non-combat exploration) and a small amount on rest actions.
- **Stamina-using classes** (Warrior, Rogue, Ranger, Blacksmith): every skill has a `stamina_cost`. Same disable rule. Stamina regenerates faster than MP (e.g., +3 per turn out of combat, +1 per turn during combat for "catching breath" beats).
- Resource regen is server-side deterministic, not LLM-controlled.
- Basic attack costs 0 resource and is always available.

### Stats & modifiers
Standard D&D modifier formula: `modifier = floor((stat - 10) / 2)`. Modifiers apply to dice rolls, damage, and skill checks.

### Leveling
XP is earned from:
- **Killing monsters** — XP awarded by the DM in `state_changes` based on monster difficulty
- **Completing side missions** — fixed XP amount per side mission (e.g., 100 XP)

XP thresholds (flat curve for simplicity in MVP):
- Lvl 1 → 2: 100 XP
- Lvl 2 → 3: 250 XP
- Lvl 3 → 4: 500 XP
- Lvl 4 → 5: 900 XP
- Lvl 5 → 6: 1400 XP
- (cap at Lvl 10 for MVP, total ~5000 XP)

On level up: +5 HP, +1 to one stat (player picks via a level-up modal), and possibly a new skill (defined per class progression).

### Side missions
Max 2–3 side missions active per campaign run. Side missions are seeded per template (in a `template_side_missions` table) but **only triggered by player intent detection** — see Side Mission System.

## Element System

### Elements (7 total)
`Fire`, `Water`, `Wind`, `Earth`, `Lightning`, `Dark`, `Light`, plus `Neutral` for non-elemental.

### Damage modifiers (rock-paper-scissors style for the 6 base elements)

| Attacker → Defender | Multiplier |
|---|---|
| Fire → Wind | ×2.0 |
| Wind → Earth | ×2.0 |
| Earth → Lightning | ×2.0 |
| Lightning → Water | ×2.0 |
| Water → Fire | ×2.0 |
| Fire → Water | ×0.5 |
| Wind → Fire | ×0.5 |
| Earth → Wind | ×0.5 |
| Lightning → Earth | ×0.5 |
| Water → Lightning | ×0.5 |
| Same element (e.g., Fire → Fire) | ×0.5 |
| Any other matchup not listed | ×1.0 |

### Light vs Dark (special, milder than the rock-paper-scissors)
- `Light` → `Dark`: ×1.5
- `Dark` → `Light`: ×1.5
- `Light` → any non-Dark: ×1.0
- `Dark` → any non-Light: ×1.0

### Neutral
- `Neutral` → anything: ×1.0
- Anything → `Neutral`: ×1.0
- **Exception:** `Light` → `Neutral`: ×0.85 (slight penalty since Light is "anti-corruption" themed)

### Element source
Damage element is determined **per skill/spell**, not per character. A Fire Mage casting "Stone Spear" deals Earth damage. A Warrior with no element deals Neutral damage from a basic attack but can wield an enchanted sword that deals Fire damage. Each skill/spell has an `element` field.

### Where multipliers apply
Element multipliers are computed **server-side in the Edge Function** when resolving combat damage, never trusted from the LLM. The Edge Function:
1. Reads the skill's element
2. Reads the target monster's element (from monster definition)
3. Looks up multiplier in a constant table
4. Applies to base damage from dice roll
5. Sends the final damage number to LLM call #2 for narration

LLM is told the multiplier *result* in plain language ("super effective", "resisted", "normal"), not the math.

## Combat System

Combat uses **strict turn-based resolution** like classic D&D / JRPGs. The LLM does NOT decide turn order or whether enemies attack — server-side rules do.

### Turn structure

When combat starts (DM emits `combat_start` in state_changes with enemy info), the server initializes a `combat_encounter`:
- Roll initiative for player and each enemy: `d20 + DEX_modifier`
- Sort by initiative descending → that's the turn order
- `current_actor` = first in queue

### Player turn

Action options panel shows combat-specific options:
- **Attack** (basic, 0 resource) → triggers attack roll (d20 + STR or DEX modifier vs enemy AC) → if hit, damage roll
- **Use Skill** → opens a skill picker (only skills the player can afford with current MP/Stamina); locked skills shown grayed out with cost
- **Defend** (0 resource) → +2 AC and +25% damage resistance until next player turn
- **Use Item** → opens inventory filtered to consumables
- **Try to flee** → DEX check vs DC scaling with encounter difficulty (very hard by default, see Difficulty Philosophy)

After resolution, server advances `current_actor` to the next initiative slot.

### Enemy turn

Server runs deterministic enemy AI (no LLM call needed for routine attacks):
1. Pick action based on enemy archetype (`aggressive` always attacks, `tactical` may use skills, `boss` has scripted phase behavior)
2. Roll attack against player AC
3. Compute damage (with element multipliers)
4. Apply state changes
5. Generate narration: **for routine enemy attacks, use a static narration pool** (e.g., 5–8 phrasings per attack type). LLM is NOT called for routine combat — saves enormous tokens.
6. LLM is only called for combat narration when:
   - Boss does a scripted special move (`requires_llm_narration: true` on the move definition)
   - Enemy is defeated (death narration matters)
   - Player is defeated (game over narration matters)

### Critical hits & misses

- Natural 20 on attack roll → critical hit, damage rolled twice + narration tagged `critical_success`
- Natural 1 → critical miss, automatic miss + small narrative complication
- Element multipliers are applied AFTER critical multiplier

### Damage formula (server-side, deterministic)
```
attack_roll = d20 + stat_modifier
hit = attack_roll >= target.AC
if not hit: damage = 0
else:
  base_damage = roll_dice(skill.dice) + stat_modifier
  critical_multiplier = (raw_d20 == 20) ? 2.0 : 1.0
  elemental_multiplier = lookup(skill.element, target.element)  // see Element System
  final_damage = floor(base_damage * critical_multiplier * elemental_multiplier)
```

LLM never computes damage. Server sends LLM the result in plain language ("dealt 18 damage, super effective") for narration only.

### Combat ends when

- All enemies HP ≤ 0 → DM (LLM call) narrates victory, awards XP, possibly loot
- Player HP ≤ 0 → game over (see Death & Game Over)
- Player successfully flees → DM (LLM call) narrates escape, combat resolves with no rewards

### Database additions
- `combat_encounters` — id, campaign_id, status ('active'|'won'|'lost'|'fled'), turn_order (jsonb), current_actor_index, round_number, started_at, ended_at
- `combat_enemies` — id, encounter_id, name, archetype, element, hp, max_hp, ac, base_damage, skills (jsonb), is_boss, template_boss_id (nullable)

## Difficulty Philosophy

**There is no difficulty selection. Every campaign runs at "Very Hard" by default.** This is intentional:
- Player retention through challenge — players don't speedrun and abandon
- Token economy — campaigns last longer per dollar of API spend
- Stakes feel real — the game over threat is meaningful

### What "Very Hard" means concretely

- Enemy DCs and AC are tuned high (boss DC 18+, even small enemies DC 14+)
- Enemy damage is meaningful relative to player HP (small enemies hit for 4–6, mediums for 8–12, bosses for 15–25)
- Healing is scarce — potions are rare loot, Priest heal spells have meaningful MP cost
- No revives. No second chances mid-encounter.
- Critical fails on dice rolls have real consequences (weapon dropped, status applied, position lost)

### Server-side enforcement
Difficulty constants live in a single config file in the Edge Function. The LLM is NOT trusted to set DCs or damage values — it can only **suggest** a DC and the server clamps it to the configured difficulty range.

## Death & Game Over

When player HP reaches 0:
1. Server marks `combat_encounters.status = 'lost'` and `campaigns.status = 'failed'`
2. LLM is called once with a `death_narration` prompt: write a brief (max 150 tokens) ending describing the character's fall, in the tone of the campaign's template
3. Player sees a "Game Over" screen with the death narration, the character's final stats, and which boss/encounter killed them
4. The campaign is **archived** (read-only, can be viewed in a "Fallen heroes" section of campaigns list, but not resumed)
5. The character itself is **not deleted** from the profile roster — the player can use the same character in a new campaign, but starts fresh (no XP, no inventory carried over, since per-campaign snapshot was lost)

No revives, no checkpoints, no save scumming. Death is permanent for that campaign run.

## Avatar System

Each character has an avatar selected from a **predefined pool of pixel-art portraits** (no generator, no upload).

### How it works
- Seed a pool of avatars per class in the migration (e.g., 4–6 portraits per class = ~30 total for MVP)
- Each portrait stored as an asset bundled with the Flutter app (or in Supabase Storage with public URLs)
- During character creation, after picking class, show a horizontal carousel of avatars available for that class
- `characters.avatar_id` references the chosen portrait
- Avatars are static — no leveling animations, no equipment overlays in MVP

### Database
- `avatar_templates` — id, class_filter (jsonb array of class names that can use it), image_url, display_name, sort_order. Public-read, seeded.

## Branching Input System (token saver — important)

This is a key cost-control mechanism. Most turns, the player picks from 3 pre-generated action buttons instead of typing free text. Free text is reserved for moments where the player wants to do something unusual.

### How it works per turn

After every DM narration, the response includes 3 (sometimes 5) **action options**. The player can:
- Tap one of the options → resolve cheaply (see "Resolution paths" below)
- Or tap a "Custom action" button to type free text → always triggers a full LLM call

### How options are generated

**Hybrid template + LLM**, decided per turn:
1. Server classifies the situation (combat / dialog / exploration / transition — same classifier from the pacing system)
2. Server pulls **template common actions** for that situation type from a constant config:
   - `combat`: ["Attack with weapon", "Use a skill", "Defend", "Try to flee"]
   - `dialog`: ["Ask a question", "Agree", "Refuse", "Try to persuade"]
   - `exploration`: ["Look around", "Search for clues", "Move on", "Rest briefly"]
3. The LLM (in the same response that produced the narration) returns up to 3–5 **situational options** tailored to the current scene
4. Server merges: prioritize situational > template; cap at 3 (or 5 if the LLM flags `pivotal_moment: true`)
5. Each option has a `kind`: `template_common` | `situational` | `pivotal`

### Resolution paths (the cost saver)

When a player taps an option:

**Path A — Cheap resolve (no LLM call):**
- Triggered when `option.kind === "template_common"` AND no dice roll is required AND the situation is non-pivotal
- Server applies a deterministic outcome from a small rules table (e.g., "Defend" → +2 AC for next turn, narration pulled from a static pool of 3–5 phrasings)
- Persists messages, returns to client, no LLM tokens spent

**Path B — LLM resolve:**
- Triggered when `option.kind === "situational" | "pivotal"`, OR a dice roll is needed, OR free-text input
- Full `dm-turn` pipeline runs (LLM call, possibly + `resolve-roll`)

### When LLM "takes over" as DM (pivotal moments)

The LLM can flag a turn as pivotal in its structured output:
```json
{
  "pivotal_moment": true,
  "reason": "Player attempted unexpected social manipulation"
}
```

When this flag is true:
- Server expands options from 3 to 5
- All options are `kind: "pivotal"` (no cheap resolve)
- DM narration is allowed slightly more tokens (`max_tokens: combat budget` regardless of classification)

This is the "LLM jumps in and takes the wheel" moment you described — most turns are cheap, but when the player does something interesting, the LLM gets full control.

### Output schema additions

The `dm-turn` response is extended:
```json
{
  "narration": "...",
  "state_changes": [...],
  "requires_roll": null | { ... },
  "story_progress": { ... },
  "options": [
    { "id": "opt_1", "label": "Charge the orc head-on", "kind": "situational" },
    { "id": "opt_2", "label": "Aim a shot at the chandelier above", "kind": "situational" },
    { "id": "opt_3", "label": "Try to flee", "kind": "template_common" }
  ],
  "pivotal_moment": false,
  "side_quest_intent": null | { "trigger": "help_villager", "suggested_quest_id": "..." }
}
```

## Side Mission System

### Source
Side missions are **seeded per template** in a `template_side_missions` table:
- id, template_id, title, description, trigger_keywords (jsonb array), trigger_intent (text), reward_xp, reward_items (jsonb), required_phase, max_simultaneous

### How they trigger (intent detection)
The LLM detects intent from the player's action. In its structured output, it can emit:
```json
{
  "side_quest_intent": {
    "trigger": "help_villager",
    "confidence": "high"
  }
}
```

Server then:
1. Looks up template side missions matching that trigger that haven't been started yet
2. Validates: is the player in the right `phase`? Already at max active side missions (2–3)?
3. If valid, creates a `campaign_side_missions` row with status `active` and shows a small "New side quest!" toast in the UI

### Completion
LLM can also emit `side_quest_progress` events (`progress_step`, `complete`, `fail`) in `state_changes`. Server validates against the side mission's defined steps before applying.

## Dice System

The dice roll is a **two-call orchestration** per dice-required turn — this is intentional for game feel (the player physically rolls and sees suspense), and it's the part of the orchestration I most want to get right.

### Supported dice (MVP)
- `d20` — primary, used for skill checks, attacks, saves
- `d6` — used for damage, small chance rolls
- `d100` — used for percentage / loot rolls

That's it. No d4/d8/d10/d12 in MVP.

### Flow

**Turn N (player sends action):**
1. LLM call #1 with player's action + full context
2. LLM emits structured output. If a roll is needed:
   ```json
   {
     "narration": "You crouch low and approach the sleeping troll...",
     "requires_roll": {
       "dice": "d20",
       "purpose": "Stealth check",
       "dc": 14,
       "modifier_stat": "DEX"
     },
     "state_changes": []
   }
   ```
3. Server **persists this as a pending turn** (table: `pending_rolls`) and returns to client. No DM narration of outcome yet.
4. Flutter shows narration, then locks input and triggers the **3D dice animation overlay**.
5. Player taps the dice to roll. Flutter plays the animation (see below) but does NOT decide the result locally.
6. Flutter calls Edge Function `resolve-roll` with the pending turn id.
7. **Server rolls the dice deterministically** using a CSPRNG, computes total = roll + character's modifier, compares to DC, determines success/fail/critical.
8. Server returns the result to Flutter (which finishes the animation by landing on that face).
9. Server immediately makes **LLM call #2** with the roll result included, asking only for the outcome narration + any state_changes:
   ```
   The player rolled 17 (raw 14 + DEX +3) vs DC 14. SUCCESS.
   Narrate the outcome of the Stealth check in 1–2 sentences.
   ```
10. Server persists DM message + applies state_changes + returns narration to Flutter.

### Why server-side rolling
- Player can't cheat by tampering with the client.
- Roll result is logged in `dice_rolls` table for debugging and replay.
- The animation is purely visual — the result is decided before the dice "lands."

### 3D dice animation (Flutter)
- Use **flame_3d** or **flutter_cube** (whichever has better community support at build time — let me know your recommendation with reasoning).
- Pre-built dice meshes for d20, d6, d100 (the d100 can be two d10s visually for MVP — confirm with me).
- Animation: dice tumbles for ~1.5s with physics-feeling rotation, then settles on the face matching the server-determined result.
- **Critical:** animation duration is fixed regardless of network latency. If the server result arrives early, hold the animation for minimum dramatic time. If it arrives late, show a subtle "rolling..." loader and start animation when result arrives.
- Sound effect on settle is nice but optional for MVP.

### Database additions
- `pending_rolls` — id, campaign_id, dice, purpose, dc, modifier_stat, llm_call_1_response (jsonb), created_at, resolved_at
- `dice_rolls` — id, campaign_id, dice, raw_result, modifier, total, dc, outcome ('success' | 'fail' | 'critical_success' | 'critical_fail'), purpose, created_at

## Resources: MP & Stamina

Each class uses one resource type:

| Class | Resource | Max @ Lvl 1 |
|---|---|---|
| Warrior | Stamina | 30 |
| Rogue | Stamina | 25 |
| Mage | MP | 30 |
| Priest | MP | 25 |
| Ranger | Stamina | 25 |
| Blacksmith | Stamina | 35 |

- **Stamina** is consumed by physical skills (power attacks, special techniques)
- **MP** is consumed by spells
- Basic attacks cost nothing
- Each skill defines its `cost_type` ('mp' | 'stamina' | 'free') and `cost_amount`

### Regeneration — rest-only (THIS is the core "very hard" lever)
**MP, Stamina, AND HP do NOT regen per turn.** They only refill via:
- **Sleeping at night** (full restore) — narrative event; player must explicitly choose to rest, and the DM determines if it's safe. Sleeping in a dungeon = risky, may trigger ambush (server-rolled chance, narrated by LLM). Sleeping in an inn = safe but costs gold.
- **Resting briefly** at a campfire or sanctuary (50% restore, costs in-game time, may trigger random encounter at low chance)
- **Consumable items** (Healing Potion, Mana Potion, Stamina Draught — rare drops, never sold cheaply)
- **Priest healing skills** (cost MP, can heal in combat)

This is intentionally harsh. It forces players to:
- Manage resources tightly (no spamming spells)
- Make meaningful choices about when to push forward vs retreat to rest
- Treat rest as a strategic decision, not a free reset

This is the **biggest contributor to "very hard" difficulty** and a major token saver — players can't barrel through encounters, so campaigns naturally pace themselves.

### Server-side enforcement
- Skill use validates `current_resource >= cost_amount` before applying. LLM can suggest a skill but server rejects if not affordable.
- Rest actions are explicit `state_changes` of type `rest` with sub-type `night_sleep | brief_rest`. Server resolves regen based on safety check (passed in narration context).

## Pacing System

### Phases per campaign
Every campaign has a current `phase` field with one of:
- `intro` — establish world, character, hook (target: 3–5 turns)
- `rising` — encounter small bosses, build threats, gather resources (target: bulk of campaign)
- `climax` — face the big boss(es), high stakes (target: 3–8 turns)
- `resolution` — narrate the ending, wrap up loose threads (target: 1–2 turns), then mark campaign `completed`

### How phases drive the DM
Every turn, the system prompt includes:
```
CURRENT PHASE: rising
PHASE GUIDANCE: The player should encounter conflict and threat. Introduce small bosses or escalating dangers. Do not let the player rest in safe locations for more than 1 turn. Move the story toward bigger confrontations.
BOSSES DEFEATED: 2 / 5 small, 0 / 3 medium, 0 / 1 big
```

Each phase has hard-coded `phase_guidance` text in the Edge Function. This is what tells the DM "stop letting the player dawdle."

### Hybrid progress tracking
Each LLM call's structured output includes:
```json
{
  "story_progress": {
    "current_phase": "rising",
    "suggest_phase_advance": false,
    "reason": "Player still has 3 small bosses unencountered"
  }
}
```

The server validates the LLM's suggestion against hard rules:
- Cannot advance to `climax` until ≥ 60% of small bosses + ≥ 50% of medium bosses are defeated
- Cannot advance to `resolution` until the big boss is defeated
- Can advance to `rising` from `intro` after 3 turns OR if LLM strongly suggests it

If validation passes, server updates `campaigns.phase`. If not, server overrides the LLM's suggestion and logs the disagreement for debugging.

### Anti-loop mechanism
Track `turns_in_current_phase` and `turns_since_last_progress` (incremented when no boss state changes and no new significant location). If `turns_since_last_progress > 4`, inject into the system prompt:
```
URGENT PACING: Player has been stalling for 5 turns. In your next narration, force a story event: a new threat appears, an NPC arrives with urgent news, or the environment changes dramatically. Do not let the player continue the current loop.
```

This is the "anti-muter-muter" lever.

## Adaptive Token Budget

Every turn classifies the situation type before calling the LLM. This is done by the server, not the LLM, using simple heuristics on the player's action + current state:

- `dialog` — player is talking to an NPC. `max_tokens: 120`
- `exploration` — player is moving, looking around. `max_tokens: 180`
- `combat` — player is fighting, dice was just rolled, or boss is engaged. `max_tokens: 220`
- `transition` — phase change, boss defeat, scene shift. `max_tokens: 300`

Heuristics (in priority order):
1. If just resolved a `dice_roll` AND boss is engaged → `combat`
2. If player message starts with quotation or contains "say"/"ask"/"tell" → `dialog`
3. If a boss state changed last turn or phase just advanced → `transition`
4. Else → `exploration`

The system prompt also enforces brevity:
```
OUTPUT RULES:
- Respond in 1–3 short paragraphs MAX. Never longer.
- No meta-commentary, no recap of what the player said, no "as a Dungeon Master, I..."
- Every sentence must advance the story or describe what the player perceives.
- Do not list options for the player. They will decide their own action.
```

## AI Orchestration (this is what I want to learn)

Pipeline split across multiple Edge Functions for clarity. Each step is a separate testable function with structured logging (request_id, latency_ms, prompt_tokens, completion_tokens, classification, max_tokens).

### Edge Function: `dm-turn` (player action → DM response or roll request)

1. **Receive** player message + campaign_id (authenticated)
2. **Load context** from Postgres: character sheet, inventory, last 8 messages, `world_memory.summary`, `campaigns.phase`, boss states, template's world_setting + dm_guidance
3. **Classify situation type** (dialog / exploration / combat / transition) via heuristics → determines `max_tokens`
4. **Build prompt:** system prompt = template world + phase guidance + boss progress + character sheet + output rules. Messages = last 8 turns + current player action.
5. **Call GPT-4o** with strict JSON schema (OpenAI structured outputs):
   ```json
   {
     "narration": "string",
     "state_changes": [
       { "type": "inventory_add" | "inventory_remove" | "hp_delta" | "xp_add" | "level_up" | "status_add" | "status_remove" | "boss_status_change", "...": "..." }
     ],
     "requires_roll": null | { "dice": "d20"|"d6"|"d100", "purpose": "string", "dc": number, "modifier_stat": "STR"|"DEX"|"CON"|"INT"|"WIS"|"CHA"|null },
     "story_progress": { "current_phase": "string", "suggest_phase_advance": boolean, "reason": "string" }
   }
   ```
6. **Branch:**
   - If `requires_roll`: persist `pending_rolls` row + player message, return narration + roll request to client. Do NOT apply state_changes yet.
   - Else: apply state_changes in a transaction, validate phase advance against hard rules, persist DM message, return narration + state diff to client.
7. **Periodic summarization:** after every 12 messages, fire-and-forget call to `summarize-campaign`.

### Edge Function: `resolve-roll` (player tapped dice → outcome narration)

1. **Receive** `pending_roll_id`
2. **Load** pending roll + character + last messages
3. **Roll deterministically** with CSPRNG. Apply `modifier_stat` modifier. Compare to DC. Outcome = `critical_success` (nat 20) | `critical_fail` (nat 1) | `success` (≥ DC) | `fail` (< DC).
4. **Call GPT-4o (call #2)** with roll result baked into the prompt. Same JSON schema, but enforce `requires_roll === null`. `max_tokens` based on situation classification (usually `combat`).
5. **Apply state_changes**, persist `dice_rolls` row + DM message, mark `pending_rolls` as resolved.
6. **Return** `{ roll_result, narration, state_changes }` in a single response. Client kicks off the dice animation when response arrives, lands on the result face, then reveals narration.

   *(Single endpoint returning both keeps MVP simple. If LLM call #2 latency hurts UX later, split into two endpoints with the animation hiding the second call's latency.)*

### Edge Function: `summarize-campaign`

Compresses messages older than the last 8 into `world_memory.summary`. Use **gpt-4o-mini** (cheaper) with `max_tokens: 400`. Triggered every 12 messages. The summary should preserve: key NPCs met, locations visited, items gained/lost, bosses encountered, unresolved threads.

### Phase advance validation (in `dm-turn`, server-side hard rules)

LLM's `suggest_phase_advance` is only honored if:
- `intro` → `rising`: after ≥ 3 turns OR LLM strongly suggests
- `rising` → `climax`: ≥ 60% small bosses defeated AND ≥ 50% medium bosses defeated
- `climax` → `resolution`: big boss defeated
- `resolution` → campaign marked `completed` after 1–2 turns

If LLM's suggestion is rejected, log the disagreement (this is useful debug data).

### Anti-stall injection

If `turns_since_last_progress > 4` (no boss state change, no new significant location/NPC), inject the URGENT PACING block (defined in Pacing System section) into the next system prompt. This forces the DM to escalate.

## Database Schema (sketch — refine with me)

- `profiles` — user profile, links to auth.users
- `characters` — id, user_id, name, class, base_element, avatar_id, stats (jsonb), created_at, updated_at. **Max 3 per user enforced via DB trigger.**
- `class_definitions` — id, name, base_element_default, base_stats (jsonb), starting_hp, resource_type ('mp'|'stamina'), starting_resource, starting_skills (jsonb). Seeded.
- `skills` — id, name, element, dice (nullable), base_damage_or_effect, mp_cost, stamina_cost, description, available_to_classes (jsonb), required_level. Seeded.
- `avatar_templates` — id, class_filter (jsonb), image_url, display_name, sort_order. Public-read, seeded.
- `story_templates` — id, title, short_description, genre, world_setting, opening_scene, dm_guidance, cover_image_url, is_active. Public read, no client write. Seeded.
- `template_bosses` — id, template_id, name, description, tier ('small'|'medium'|'big'), element, hp, base_damage, order_index
- `template_side_missions` — id, template_id, title, description, trigger_intent, trigger_keywords (jsonb), reward_xp, reward_items (jsonb), required_phase, max_simultaneous
- `campaigns` — id, user_id, character_id, template_id, name, status ('active'|'completed'|'failed'), phase ('intro'|'rising'|'climax'|'resolution'), turns_in_current_phase, turns_since_last_progress, total_turns, created_at, last_played_at
- `campaign_characters` — id, campaign_id, character_id, level, xp, hp, max_hp, resource_type ('mp'|'stamina'), resource_current, resource_max, current_stats (jsonb), status_effects (jsonb), ac. **Per-campaign snapshot of character state.**
- `campaign_inventory` — id, campaign_id, name, qty, description, element, item_type ('weapon'|'armor'|'consumable'|'misc'), metadata (jsonb)
- `campaign_skills` — id, campaign_id, skill_id, learned_at_turn
- `campaign_bosses` — id, campaign_id, template_boss_id, status ('unencountered'|'encountered'|'defeated'), current_hp, defeated_at
- `campaign_side_missions` — id, campaign_id, template_side_mission_id, status ('active'|'completed'|'failed'), started_at, completed_at, current_step
- `combat_encounters` — id, campaign_id, status ('active'|'won'|'lost'|'fled'), turn_order (jsonb), current_actor_index, round_number, started_at, ended_at
- `combat_enemies` — id, encounter_id, name, archetype ('aggressive'|'tactical'|'boss'), element, hp, max_hp, ac, base_damage, skills (jsonb), is_boss, template_boss_id (nullable)
- `messages` — id, campaign_id, role ('player'|'dm'|'system'), content, situation_type, options (jsonb, the 3–5 buttons shown), selected_option_id, was_cheap_resolve (bool), prompt_tokens, completion_tokens, created_at
- `world_memory` — id, campaign_id, summary, covers_message_range, updated_at
- `pending_rolls` — id, campaign_id, dice, purpose, dc, modifier_stat, llm_call_1_response (jsonb), created_at, resolved_at
- `dice_rolls` — id, campaign_id, dice, raw_result, modifier, total, dc, outcome ('critical_success'|'success'|'fail'|'critical_fail'), purpose, created_at

RLS: every row scoped by user_id (directly or via campaign). `story_templates`, `template_bosses`, `template_side_missions`, `class_definitions`, `skills` are public-read for any authenticated user.

## Deliverables I want, in this order

1. **First:** ask me clarifying questions on anything ambiguous above. Do not start coding yet.
2. Repo structure (Flutter app + `supabase/` folder for migrations and Edge Functions)
3. Supabase migrations + RLS + seed migrations: 3–5 story templates with bosses + side missions, class definitions, skills catalog (with mp/stamina costs), avatar templates pool, element multiplier table, difficulty constants
4. Edge Function: `dm-turn` — pipeline with situation classification, adaptive max_tokens, options generation, pivotal moment detection, phase validation, anti-stall, side quest intent detection, structured logging
5. Edge Function: `resolve-roll` — server-side dice rolling, element multiplier, LLM call #2 for outcome narration
6. Edge Function: `cheap-resolve` — handles template_common option taps without LLM (deterministic rules + static narration pool)
7. Edge Function: `combat-action` — turn-based combat resolution: player attack/skill/defend/item/flee, deterministic enemy AI with static narration pool, calls LLM only for boss specials and victory/defeat moments
8. Edge Function: `summarize-campaign` — periodic compression with gpt-4o-mini
9. Flutter app:
   - Auth flow
   - Home / Characters roster (max 3, create/edit/delete, avatar carousel)
   - Campaigns list (active + completed + **fallen heroes** archive section)
   - Template picker
   - Character creation: pick class → see derived stats/element/resource type → pick avatar from class-filtered pool → name
   - **Game screen** with pixel-art retro UI: chat, action options panel, combat UI overlay (turn order indicator, enemy HP bars, skill picker showing locked/unlocked by resource cost), stats bottom sheet (with MP/Stamina bar), 3D dice overlay, phase indicator, side mission toast
   - Game over screen (death narration + final stats)
   - Riverpod providers wired to Supabase
7. README with local setup steps (supabase start, env vars, running the app)

## Conventions

- Strict null safety in Dart, no `dynamic` unless justified
- TypeScript strict mode in Edge Functions
- Every Edge Function: input validation with zod, typed errors, structured JSON logs
- No secrets in client code — Anthropic API key lives only in Edge Function env
- Small commits per logical chunk; explain what each chunk does before writing it

## Working style

- Walk me through your plan before writing a lot of code.
- After each major chunk, pause and let me try it before moving on.
- When you make a non-obvious tradeoff (e.g., how you structured the prompt, why you picked a context window strategy), tell me why in 2–3 sentences. I'm here to learn.
- If something I asked for is a bad idea, push back and explain.

Start by asking your clarifying questions.
