# DungeonKu — Story Engine Redesign

> **Status**: Design — not yet implemented.
> **Last updated**: 2026-05-10
> **Decision**: AI roles **A + B + C + D** (see §3). Role E deferred.

This document is the single source of truth for migrating DungeonKu from
"AI-as-DM" (where the LLM generates story per turn) to **"scripted story
graph + AI flavor"** (where the story is a finite-state machine and the
LLM is invoked only at strategic moments).

The next coding agent / IDE session should read this doc end-to-end
before touching code. Everything you need — schema, prompts, file
list, phasing — is in here.

---

## 1. Why this redesign

Field-test feedback from the project owner (2026-05-10):

> "ternyata tokennya boros sekali. Tiap story harusnya tetap punya cerita
> lengkap sekali, opsi lengkap sekali, tiap tindakan punya alur sendiri
> — tidak full mengandalkan AI dan tidak muter-muter."

Concretely, today's `dm-turn` calls OpenAI on **every** player turn,
rebuilding ~3000-token system prompts to ask the model to (re)derive the
world, the plot, and the available options. That's expensive **and**
unreliable: the LLM occasionally loops, contradicts itself, or fails to
advance the story.

Proper game design = the story and its branching are **authored
ahead of time** as data; the engine traverses them deterministically;
the LLM is only used to make narration interesting, not to make
decisions.

---

## 2. Token budget — before vs. after

| Scenario | Tokens / turn | Tokens / 30-turn session |
|---|---|---|
| **Today** (LLM-as-DM, every turn) | ~3000 in + ~400 out = **~3400** | ~102,000 |
| **Phase 1 only** (state machine, no AI) | 0 | 0 |
| **Phase 2** (+ reskinner, ~5 pivotal nodes/session) | avg ~40 | ~1,150 |
| **Phase 3** (+ free-text, capped 5/session) | avg ~80 | ~2,300 |
| **Phase 4** (+ NPC voice + roll narrator) | avg ~110 | ~3,300 |
| **Full A+B+C+D** | — | **~3,300** |

**Reduction: ~97%** vs. today, while gameplay becomes deterministic and
finishable. The LLM still shows up at the moments that matter.

---

## 3. The four AI roles (A + B + C + D)

| Role | Trigger | In tokens | Out tokens | Frequency |
|---|---|---|---|---|
| **A. Flavor Reskinner** | Node entry, if node.ai_reskin_policy fires | ~150 | ~80 | ~5 / session (pivotal nodes only) |
| **B. Free-Text Intent Mapper** | Player types instead of clicks | ~200 | ~30 | ≤5 / session (rate-limited) |
| **C. NPC Voice Rewriter** | Dialog node entry | ~100 | ~50 | ~3-6 / session |
| **D. Roll-Result Narrator** | Dice roll nat 1, nat 20, or margin > threshold | ~100 | ~80 | ~2-4 / session |

Roles E (session summarizer) and F (offline authoring tool) are deferred.

### 3.1 Toggleable per user

Each role gets a row in a new `user_settings` table (or in `profiles`):

```
ai_role_reskinner_enabled  bool default true
ai_role_intent_mapper_enabled bool default true
ai_role_npc_voice_enabled  bool default true
ai_role_roll_narrator_enabled  bool default true
```

A user with a tight token budget can disable any subset — the engine
gracefully falls back to deterministic text.

---

## 4. Architecture overview

```
┌──────────────────────────────────────────────────────────────┐
│                     CLIENT (Flutter)                         │
│  GameScreen renders:                                         │
│    • Current node body (already-reskinned text from server)  │
│    • Options list (filtered by `requires` gates server-side) │
│    • Free-text input (toggle, sends to /intent-map)          │
└──────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                  EDGE FUNCTIONS (Deno)                       │
│                                                              │
│  dm-turn (refactored)                                        │
│    1. Load campaign_node_state.current_node_id               │
│    2. Load node + outgoing edges                             │
│    3. Apply on_enter_actions (grant_item, start_combat, etc) │
│    4. If reskin policy matches → call ROLE A                 │
│    5. If node.type=dialog → call ROLE C (replaces body)      │
│    6. Insert dm message; return narration + options          │
│                                                              │
│  player-action (new)                                         │
│    1. Validate option_id against current node's edges        │
│    2. Apply edge.consumes (deduct resources, set flags)      │
│    3. Set current_node_id = edge.to_node_id                  │
│    4. Trigger dm-turn for the new node                       │
│                                                              │
│  intent-map (new, ROLE B)                                    │
│    in:  { campaign_id, free_text }                           │
│    out: { option_id | null, reason }                         │
│                                                              │
│  resolve-roll (modified)                                     │
│    Existing dice math + outcome text.                        │
│    If crit/fumble → ROLE D narrator overrides outcome text.  │
│                                                              │
│  combat-action (unchanged)                                   │
│    Already deterministic. Story-engine wraps it via          │
│    on_enter_actions[start_combat] when entering combat node. │
└──────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│                   POSTGRES (Supabase)                        │
│                                                              │
│  story_nodes ───┐    (text, type, body, on_enter_actions)    │
│                 │                                            │
│  story_edges ───┤    (from_node, option_id, to_node,         │
│                 │     requires, consumes)                    │
│                 │                                            │
│  campaign_node_state                                         │
│    • current_node_id                                         │
│    • visited_node_ids                                        │
│    • flags                                                   │
│                                                              │
│  story_templates.root_node_id ── new FK ──→ story_nodes      │
└──────────────────────────────────────────────────────────────┘
```

**Important**: combat, dice, inventory, skills, avatar lore, signature
skills — **all existing systems remain intact**. The story graph is a
new layer that decides *what scene we're in*, while combat/dice/skills
decide *what happens within a scene*.

---

## 5. Database schema (full SQL)

File: `supabase/migrations/20260511000000_story_node_graph.sql`

```sql
set search_path to dungeonku, public;

-- 5.1 Nodes ----------------------------------------------------------
create table if not exists story_nodes (
  id text primary key,                          -- e.g. "ember_outpost__intro"
  template_id text not null
    references story_templates(id) on delete cascade,

  type text not null check (type in (
    'scene',         -- ambient narration; just a paragraph + options
    'dialog',        -- NPC line + reply options (role C may rewrite)
    'choice',        -- pure branching, minimal narration
    'combat',        -- on_enter starts a combat encounter
    'outcome',       -- terminal-ish: success/failure scene
    'transition'     -- bridging beat; usually pivotal_only reskin
  )),

  body text not null default '',                -- dry, finishable narration
  speaker text,                                 -- dialog: NPC name
  speaker_profile jsonb default '{}'::jsonb,    -- NPC tone tags, mood
  tags jsonb default '[]'::jsonb,               -- ['pivotal','first_visit',...]

  on_enter_actions jsonb default '[]'::jsonb,
  -- list of {kind, payload}, applied server-side when node is entered:
  --   { kind: "grant_item",     payload: { item_id, qty } }
  --   { kind: "grant_skill",    payload: { skill_id } }
  --   { kind: "set_flag",       payload: { key, value } }
  --   { kind: "start_combat",   payload: { boss_id|enemy_set_id } }
  --   { kind: "damage_player",  payload: { dice, element } }
  --   { kind: "heal_player",    payload: { dice } }
  --   { kind: "change_phase",   payload: { to_phase } }
  --   { kind: "end_campaign",   payload: { outcome:"success"|"failure" } }

  ai_reskin_policy text not null default 'pivotal_only'
    check (ai_reskin_policy in ('always','pivotal_only','never')),

  sort_order int default 0,
  created_at timestamptz default now()
);

create index if not exists idx_story_nodes_template
  on story_nodes(template_id, sort_order);


-- 5.2 Edges ----------------------------------------------------------
create table if not exists story_edges (
  id text primary key,                          -- e.g. "ember_outpost__intro:enter_left"
  from_node_id text not null
    references story_nodes(id) on delete cascade,
  option_id text not null,                      -- short, unique within from_node
  option_label text not null,                   -- visible on the option button

  to_node_id text not null
    references story_nodes(id) on delete restrict,

  requires jsonb default '{}'::jsonb,
  -- gating predicate. ALL listed conditions must hold for the edge to be
  -- offered. Missing keys = unconditional.
  --   { class:        ["warrior","rogue"]   }   any-of
  --   { skill:        ["sig_vanish"]         }   any-of, must be in campaign_skills
  --   { stat:         { INT: ">=12" }        }   per-stat gate
  --   { item:         ["rope"]               }   any-of, in campaign_inventory
  --   { flag:         ["saved_villager"]     }   all-of, in campaign_node_state.flags
  --   { not_flag:     ["betrayed_npc"]       }   all-of, must NOT be set
  --   { hp_pct_above: 0.5                    }
  --   { hp_pct_below: 0.25                   }

  consumes jsonb default '[]'::jsonb,
  -- list of side-effects when this edge is taken (similar shape to
  -- on_enter_actions; common ones):
  --   { kind:"set_flag",      payload:{key:"saved_villager", value:true} }
  --   { kind:"consume_item",  payload:{item_id:"rope", qty:1} }
  --   { kind:"cost_resource", payload:{amount:5} }

  sort_order int default 0,

  unique (from_node_id, option_id)
);

create index if not exists idx_story_edges_from
  on story_edges(from_node_id, sort_order);


-- 5.3 Per-campaign cursor + flags ------------------------------------
create table if not exists campaign_node_state (
  campaign_id uuid primary key
    references campaigns(id) on delete cascade,

  current_node_id text references story_nodes(id),
  visited_node_ids jsonb default '[]'::jsonb,   -- array of node ids
  flags jsonb default '{}'::jsonb,              -- arbitrary kv set by edges/nodes

  updated_at timestamptz default now()
);

-- RLS: same pattern as other campaign-scoped tables.
alter table campaign_node_state enable row level security;
create policy "owners read"   on campaign_node_state for select
  using (exists (select 1 from campaigns c
                 where c.id = campaign_id and c.user_id = auth.uid()));
create policy "owners write"  on campaign_node_state for all
  using (exists (select 1 from campaigns c
                 where c.id = campaign_id and c.user_id = auth.uid()));


-- 5.4 Wire root onto template ---------------------------------------
alter table story_templates
  add column if not exists root_node_id text
    references story_nodes(id) on delete set null;

-- 5.5 User settings for AI role toggles ------------------------------
-- (We add to profiles; a dedicated user_settings table would also be fine.)
alter table profiles
  add column if not exists ai_role_reskinner_enabled bool default true,
  add column if not exists ai_role_intent_mapper_enabled bool default true,
  add column if not exists ai_role_npc_voice_enabled bool default true,
  add column if not exists ai_role_roll_narrator_enabled bool default true;
```

---

## 6. Action / requires / consumes spec

### 6.1 `on_enter_actions` and `consumes`

| `kind` | `payload` shape | Effect |
|---|---|---|
| `grant_item` | `{ item_id, qty }` | insert into `campaign_inventory` |
| `grant_skill` | `{ skill_id }` | insert into `campaign_skills` |
| `set_flag` | `{ key, value }` | merge into `campaign_node_state.flags` |
| `consume_item` | `{ item_id, qty }` | decrement / delete from `campaign_inventory` |
| `cost_resource` | `{ amount }` | deduct from `campaign_characters.resource_current` |
| `start_combat` | `{ boss_id }` or `{ enemy_set_id }` | call existing combat engine; node should also have `type='combat'` |
| `damage_player` | `{ dice: "d6", element: "fire" }` | apply via existing damage function |
| `heal_player` | `{ dice: "d6" }` | apply via existing heal function |
| `change_phase` | `{ to_phase: "climax" }` | update `campaigns.phase` |
| `end_campaign` | `{ outcome: "success"\|"failure", summary_seed }` | mark campaign complete |

### 6.2 `requires` predicate

Every key in the JSON object is ANDed; multi-value arrays are ANY-OF.

```json
{
  "class":  ["warrior","blacksmith"],
  "skill":  ["sig_anvil_skin"],
  "stat":   { "STR": ">=14", "WIS": ">=10" },
  "item":   ["forge_hammer"],
  "flag":   ["completed_tutorial"],
  "not_flag": ["betrayed_smith"],
  "hp_pct_above": 0.5
}
```

Server filters edges before sending to client. Client may *display*
locked edges greyed-out for transparency (UX choice — see §9).

---

## 7. Edge functions

### 7.1 `dm-turn` (refactored)

Pseudocode:

```ts
async function handler(req) {
  const { campaign_id } = parseRequest(req);
  const sb = createClient(...);

  // 1. Load state
  let state = await sb.from('campaign_node_state')
    .select('*').eq('campaign_id', campaign_id).maybeSingle();

  if (!state.data?.current_node_id) {
    // Initialize from template root
    const tpl = await sb.from('story_templates')
      .select('root_node_id').eq('id', campaign.template_id).single();
    state = await initializeNodeState(sb, campaign_id, tpl.root_node_id);
  }

  // 2. Load node + outgoing edges
  const node = await sb.from('story_nodes')
    .select('*').eq('id', state.current_node_id).single();
  const allEdges = await sb.from('story_edges')
    .select('*').eq('from_node_id', node.id).order('sort_order');

  // 3. Apply on_enter_actions (only on first visit unless tagged 'replayable')
  if (!state.visited_node_ids.includes(node.id) ||
      node.tags.includes('replayable_actions')) {
    await applyActions(sb, campaign_id, node.on_enter_actions);
    await sb.from('campaign_node_state')
      .update({ visited_node_ids: [...state.visited_node_ids, node.id] })
      .eq('campaign_id', campaign_id);
  }

  // 4. Render body — possibly with AI reskin
  let narration = node.body;
  const userSettings = await loadUserAiSettings(sb, campaign.user_id);

  const shouldReskin =
    userSettings.ai_role_reskinner_enabled && (
      node.ai_reskin_policy === 'always' ||
      (node.ai_reskin_policy === 'pivotal_only' && node.tags.includes('pivotal'))
    );
  if (shouldReskin) {
    narration = await reskinNarration(node, avatarFlavor); // ROLE A
  }

  if (node.type === 'dialog' && userSettings.ai_role_npc_voice_enabled) {
    narration = await rewriteNpcLine(node, avatarFlavor);  // ROLE C
  }

  // 5. Filter edges by `requires`
  const ctx = await loadGatingContext(sb, campaign_id); // class, skills, items, flags, stats, hp
  const offered = allEdges.data
    .map(e => ({ ...e, locked: !checkRequires(e.requires, ctx) }))
    .filter(e => !e.locked || node.tags.includes('show_locked'));

  // 6. Persist DM message, return
  await sb.from('messages').insert({
    campaign_id, role: 'dm', content: narration,
    requires_roll: null,
  });

  return Response.json({
    narration,
    options: offered.map(e => ({
      id: e.option_id,
      label: e.option_label,
      locked: e.locked,
    })),
    node_type: node.type,
    node_id: node.id,
  });
}
```

Total tokens for a non-pivotal scene node: **0**.
Total tokens for a pivotal scene node: ~230.
Total tokens for a dialog node: ~150.

### 7.2 `player-action` (new endpoint)

```ts
async function handler(req) {
  const { campaign_id, option_id } = parseRequest(req);
  const sb = createClient(...);

  const state = await loadNodeState(sb, campaign_id);
  const edge = await sb.from('story_edges')
    .select('*')
    .eq('from_node_id', state.current_node_id)
    .eq('option_id', option_id)
    .maybeSingle();

  if (!edge.data) return error(400, 'invalid option');

  // Re-validate gating (defence in depth — client may have stale data)
  const ctx = await loadGatingContext(sb, campaign_id);
  if (!checkRequires(edge.data.requires, ctx)) {
    return error(403, 'requires not met');
  }

  // Apply edge consumes
  await applyActions(sb, campaign_id, edge.data.consumes);

  // Transition
  await sb.from('campaign_node_state')
    .update({ current_node_id: edge.data.to_node_id, updated_at: 'now()' })
    .eq('campaign_id', campaign_id);

  // Insert player choice as message (mirrors current behavior)
  await sb.from('messages').insert({
    campaign_id, role: 'player', content: edge.data.option_label,
  });

  // Trigger next dm-turn
  return await dmTurnHandler({ campaign_id });
}
```

### 7.3 `intent-map` (new endpoint, ROLE B)

```ts
async function handler(req) {
  const { campaign_id, free_text } = parseRequest(req);
  const sb = createClient(...);

  // Rate limit (per-session counter on campaign_node_state.flags)
  const state = await loadNodeState(sb, campaign_id);
  const usedCount = (state.flags?.intent_map_used ?? 0);
  if (usedCount >= 5) return error(429, 'free-text limit reached');

  // Load current edges
  const edges = await sb.from('story_edges')
    .select('*').eq('from_node_id', state.current_node_id);

  // Filter by gating to avoid suggesting locked options
  const ctx = await loadGatingContext(sb, campaign_id);
  const open = edges.data.filter(e => checkRequires(e.requires, ctx));

  // Call OpenAI
  const prompt = buildIntentPrompt(open, free_text);  // ROLE B prompt
  const result = await openai.chatCompletion({
    model: 'gpt-4o-mini',
    messages: prompt,
    response_format: { type: 'json_schema', json_schema: INTENT_SCHEMA },
    max_tokens: 60,
  });

  const parsed = JSON.parse(result.choices[0].message.content);
  // parsed = { option_id: "..." | null, reason: "..." }

  // Increment counter
  await sb.from('campaign_node_state')
    .update({ flags: { ...state.flags, intent_map_used: usedCount + 1 } })
    .eq('campaign_id', campaign_id);

  if (!parsed.option_id) {
    // Append a small "you can't do that" beat as a system message
    await sb.from('messages').insert({
      campaign_id, role: 'system',
      content: `(That can't be done here: ${parsed.reason})`,
    });
    return Response.json({ matched: false, reason: parsed.reason });
  }

  // Forward to player-action
  return await playerActionHandler({ campaign_id, option_id: parsed.option_id });
}
```

### 7.4 `resolve-roll` (modified)

After existing dice math:

```ts
const isCrit = d20 === 20;
const isFumble = d20 === 1;
const margin = total - dc;

const userSettings = await loadUserAiSettings(sb, campaign.user_id);

if (userSettings.ai_role_roll_narrator_enabled &&
    (isCrit || isFumble || Math.abs(margin) >= 10)) {
  outcomeText = await narrateRoll({  // ROLE D
    nodeBody: node.body,
    skillName: skill?.name,
    rolled: d20,
    total,
    dc,
    margin,
    isCrit,
    isFumble,
  });
}
// else: outcome text comes from existing skill.base_damage_or_effect or
//       a node-level outcome_text field
```

---

## 8. AI prompt templates

All four use small, structured prompts and JSON-schema-constrained output
where possible.

### 8.1 ROLE A — Flavor Reskinner

```
SYSTEM:
You are a prose stylist for a retro pixel-art TTRPG. You will receive a
dry narration paragraph and rewrite it in 2-3 sentences, preserving every
fact and named entity exactly. Do NOT add new facts, NPCs, or plot beats.
Keep the tone consistent with the supplied voice tags.

USER (JSON):
{
  "node_body": "<dry text>",
  "voice_tags": ["stoic","weary","loyal"],
  "avatar_origin": "<one-sentence backstory>",
  "scene_type": "scene|dialog|combat|choice|outcome|transition"
}

ASSISTANT (JSON, schema-constrained):
{ "rewritten": "..." }
```

Token budget: ~150 in, ~80 out. Model: `gpt-4o-mini`.

### 8.2 ROLE B — Free-Text Intent Mapper

```
SYSTEM:
The player typed a free-text action. Map it to ONE of the listed valid
options. If none reasonably match, return null and explain briefly why.
Do not invent new options.

USER (JSON):
{
  "free_text": "aku coba menyuap penjaga dengan sepotong emas",
  "current_scene": "<short summary>",
  "options": [
    {"id":"opt_attack",  "label":"Attack the guard"},
    {"id":"opt_sneak",   "label":"Slip past in the shadows"},
    {"id":"opt_talk",    "label":"Talk your way through"}
  ]
}

ASSISTANT (JSON, schema-constrained):
{ "option_id": "opt_talk" | null, "reason": "..." }
```

Token budget: ~200 in, ~30 out. Model: `gpt-4o-mini`.

### 8.3 ROLE C — NPC Voice Rewriter

```
SYSTEM:
Rewrite the NPC's line to fit their voice and current mood. Preserve the
information content exactly. Output 1-2 sentences max.

USER (JSON):
{
  "npc_name": "Old Smith",
  "npc_tone": ["gruff","weary","fair"],
  "npc_mood": "suspicious",   // computed from flags or node tags
  "raw_line": "I won't let you have the hammer.",
  "player_voice_tags": ["charming","direct"]
}

ASSISTANT:
{ "rewritten": "..." }
```

Token budget: ~100 in, ~50 out. Model: `gpt-4o-mini`.

### 8.4 ROLE D — Roll-Result Narrator

```
SYSTEM:
A dice roll just happened. Narrate the outcome in 1-2 short sentences.
Do not change facts. Critical fail → vivid mishap. Critical success →
vivid triumph. Otherwise stay grounded.

USER (JSON):
{
  "scene": "<one-line scene summary>",
  "skill_or_check": "Persuasion",
  "rolled": 20,
  "total": 24,
  "dc": 14,
  "margin": 10,
  "is_crit": true,
  "is_fumble": false
}

ASSISTANT:
{ "narration": "..." }
```

Token budget: ~100 in, ~80 out. Model: `gpt-4o-mini`.

---

## 9. Flutter changes

### 9.1 New / changed files

| Path | Status | Purpose |
|---|---|---|
| `lib/data/models/story_node.dart` | NEW | `StoryNode` model |
| `lib/data/models/story_option.dart` | NEW | `StoryOption` w/ `locked` flag |
| `lib/data/repositories/story_engine_repository.dart` | NEW | Wraps `dm-turn`, `player-action`, `intent-map` calls |
| `lib/features/game/components/scripted_options.dart` | NEW | Option list w/ locked state |
| `lib/features/game/components/free_text_input.dart` | NEW | Toggleable free-text row, calls `intent-map` |
| `lib/features/game/game_screen.dart` | CHANGED | Use scripted options + free-text instead of LLM-driven options |
| `lib/data/repositories/campaigns_repository.dart` | CHANGED | After `campaigns` insert, also insert `campaign_node_state` with `current_node_id = template.root_node_id` |
| `lib/features/settings/ai_roles_screen.dart` | NEW | Toggle screen for the four AI roles (writes to `profiles`) |

### 9.2 Locked-option UX

When an option's `locked: true` (because `requires` failed), render it
greyed-out with a small icon and a tooltip / tap-toast that explains
*why* (e.g., "Need: STR ≥ 14"). This makes character-build choices feel
meaningful — players see options they would have unlocked.

A node opting into this behaviour must set `tags: ["show_locked"]` so
the server includes locked edges in the response.

### 9.3 Free-text input

Bottom of the chat panel gets a small "type instead" toggle. When
expanded, a text field + send button POST to `intent-map`. Show
remaining-uses counter (e.g., "3/5 free-text turns left this campaign").

---

## 10. Demo template — "Ember Outpost" (~25 nodes)

Ship one fully-authored template with the migration so the engine can be
exercised end-to-end. Concrete sketch (write the SQL in
`supabase/migrations/20260511000100_seed_demo_ember_outpost.sql`):

```
ember_outpost__intro              [scene, pivotal]
  → enter_outpost  → ember_outpost__gate
  → circle_around  → ember_outpost__back_path  (requires: skill=[sig_one_with_trees])

ember_outpost__gate               [dialog, pivotal]
  speaker: "Watch Sergeant"
  → bribe          → ember_outpost__bribed   (consumes: cost_resource{amount:5})
  → bluff          → ember_outpost__bluffed  (requires: stat{CHA:">=12"})
  → fight          → ember_outpost__combat_gate
  → leave          → ember_outpost__intro

ember_outpost__combat_gate        [combat]
  on_enter: [{kind:"start_combat", payload:{enemy_set_id:"gate_guards"}}]
  → win_combat     → ember_outpost__courtyard
  → flee           → ember_outpost__intro

...

ember_outpost__final_door         [choice, pivotal]
  → smith_route    → ember_outpost__forge_finale  (requires: class=["blacksmith"] OR flag=["forge_friend"])
  → mage_route     → ember_outpost__library_finale (requires: class=["mage"] OR stat{INT:">=14"})
  → brute_route    → ember_outpost__roof_finale

ember_outpost__forge_finale       [outcome]
  on_enter: [{kind:"end_campaign", payload:{outcome:"success", summary_seed:"You forged the answer."}}]
```

All node bodies are written as plain prose. Pivotal ones get reskinned
by ROLE A at runtime; the rest are shown verbatim — costing zero tokens.

---

## 11. Migration strategy for existing campaigns

Existing campaigns have **no** `current_node_id` because the templates
they reference don't have node graphs yet.

**Recommendation: lock legacy campaigns to read-only.**

```sql
alter table campaigns
  add column if not exists is_legacy bool default false;

-- Backfill: any campaign created before 20260511 is legacy
update campaigns
  set is_legacy = true
  where created_at < '2026-05-11';
```

Flutter:
- Legacy campaigns appear in the campaigns list with a "Legacy" tag.
- Tapping them opens a read-only history view of past messages.
- New campaigns force the player onto a node-graph-equipped template.

This lets us ship the redesign without rewriting old story content.

---

## 12. Phased implementation plan

**Status as of 2026-05-10**

| Phase | Status | Notes |
|---|---|---|
| 1 — Foundation (no AI, deterministic FSM)            | ✅ **DONE** | Demo: Ember Outpost (75 nodes, ~115 edges, 5 endings) |
| 2 — Role A (Reskinner) + Role C (NPC Voice)          | ✅ **DONE** | Toggleable per-user, default off |
| 3 — Role B (Free-Text Intent Mapper)                 | ✅ **DONE** | Rate-limited 5/campaign |
| 1.5 — Combat ↔ story engine flag handshake           | ✅ **DONE** | combat-action writes `combat_won/fled/lost`; StoryCombatScreen routes combat nodes |
| 4 — Role D (Roll Narrator)                           | ✅ **DONE** | crit/fumble/margin≥10; replaces narration in resolve-roll |
| 5 — Migrate / deprecate old templates                | ⏳ pending  | already partially done: legacy campaigns flagged |
| 6 — Authoring tool                                   | 📦 future   | admin-only LLM-assisted node graph drafter |

### Phase 1 — Foundation (no AI, deterministic) — ✅ DONE
- [x] Migration `20260511000000_story_node_graph.sql` — schema (§5) + `campaigns.is_legacy` + `profiles.ai_role_*_enabled`
- [x] Migrations `20260511000100/200/300_seed_ember_*.sql` — demo template split into 3 parts
  (75 nodes, ~115 edges, 5 endings: hero / mercy / pyrrhic / antihero / failure)
- [x] Helper module `supabase/functions/_shared/story_engine.ts`:
  - `loadGatingContext(sb, campaign_id)`, `checkRequires(predicate, ctx)`,
    `applyActions(sb, campaign_id, actions[])`, `loadNodeState`,
    `ensureNodeStateInitialized`, `loadNode`, `loadOutgoingEdges`,
    `markNodeVisited`, `transitionTo`, `renderNodePayload`, `takeOption`
- [x] **Deviation from original plan**: did NOT refactor `dm-turn`. Instead
  shipped two new endpoints (`story-turn`, `player-action`) and left the
  legacy DM endpoint untouched. The router dispatches based on
  `campaigns.is_legacy`, so old campaigns keep working unchanged.
- [x] `story-turn/index.ts` — render current node + options
- [x] `player-action/index.ts` — validate option, apply consumes,
  transition cursor, render new node
- [x] **Skipped**: `campaigns_repository.dart` change. Server-side
  `ensureNodeStateInitialized` self-seeds on first `/story-turn` call,
  so no Flutter-side change was needed.
- [x] Flutter `StoryNode` + `StoryOption` + `EndedCampaign` models
  (single file: `lib/data/models/story_node.dart`)
- [x] Flutter `story_engine_repository.dart`
- [x] **Deviation**: instead of touching `game_screen.dart`, shipped a
  new `lib/features/story/story_screen.dart` and routed `is_legacy=false`
  campaigns to it. Legacy campaigns still use `game_screen.dart`.
- [x] **Acceptance met**: a fresh Ember Outpost campaign with all four
  AI toggles off plays to a `success` ending with **0 OpenAI tokens**.

### Phase 2 — ROLE A + ROLE C (cheap, in-place) — ✅ DONE
- [x] `_shared/reskin.ts` — prompt + caller (§8.1). gpt-4o-mini, ~150in/80out
- [x] `_shared/npc_voice.ts` — prompt + caller (§8.3). gpt-4o-mini, ~100in/50out
- [x] `_shared/profile_context.ts` — small loader for AI toggles + avatar voice tags
- [x] Wired into `story_engine.ts:renderNodePayload` (NOT `dm-turn`):
  - Role C runs first on dialog nodes with a speaker
  - Role A runs second when Role C didn't fire AND policy allows
  - `ai_role_used: 'reskinner'|'npc_voice'|null` returned to client
  - Both fail-safe to dry authored body on null
  - Ending nodes are skipped to preserve crafted prose
- [x] User settings toggles in `profiles` (4 booleans) +
  `ai_roles_screen.dart` + `profiles_repository.dart` +
  Settings panel summary + `/settings/ai-roles` route
- [x] StoryScreen renders ✨ "AI VOICE"/"AI FLAVOR" badge with tooltip
- [x] **Acceptance met**: pivotal scenes vary per playthrough when
  reskinner is on; dialog lines vary when NPC voice is on; everything
  works with all roles off (zero tokens).

### Phase 3 — ROLE B (free-text) — ✅ DONE
- [x] `_shared/intent_mapper.ts` — prompt + caller (§8.2). gpt-4o-mini, ~200in/30out
- [x] New `intent-map/index.ts` endpoint (§7.3) with:
  - Per-user toggle check (`409 intent_map_disabled` if off)
  - Server-side gating pre-filter (LLM only sees legal options)
  - Defensive id validation (rejects hallucinated option ids)
  - Rate limit 5/campaign via `campaign_node_state.flags.intent_map_count`
- [x] Flutter `_FreeTextPanel` widget inside `story_screen.dart`
  (rather than separate `free_text_input.dart` file). Shows remaining
  counter, last reason, chains into `/player-action` on success.
- [x] Rate limit increments even on no-match to prevent abuse
- [x] Removed "SOON" tag from Role B in `ai_roles_screen.dart`
- [x] **Acceptance met**: "I bribe the guard" → maps to bribe option;
  "I dance the polka" → returns null + explanation; counter visible;
  cap enforced at 5.

### Phase 1.5 — Combat integration — ✅ DONE
- [x] `combat-action/index.ts`: `writeCombatOutcomeFlag()` writes
  `combat_won/combat_lost/combat_fled` + clears `pending_combat_id`
  on encounter resolution (win, player death, flee).
- [x] `story_engine.ts:actStartCombat`: batch-clears stale outcome flags
  when a new combat starts (single DB write instead of 4 separate calls).
- [x] Migration `20260511000400_fix_story_combat_edges.sql`: gates all
  Ember Outpost win edges behind `requires:{flag:["combat_won"]}`; adds
  flee edges for all four combat nodes gated on `combat_fled`.
- [x] `lib/features/story/story_combat_screen.dart` (NEW): simple combat
  screen loading from `combat_enemies` + `campaign_characters`; shows
  HP bars, combat log, Attack/Defend/Flee/Skill buttons; pops on resolve.
- [x] Router: `/story-combat/:campaignId` route added.
- [x] `StoryScreen._maybeHandleEndState`: pushes `/story-combat` when
  `pendingCombatId != null`; calls `_bootstrap()` on pop to re-render
  the node with unlocked combat-result edges.

### Phase 4 — ROLE D (roll narrator) — ✅ DONE
- [x] `_shared/roll_narrator.ts` — prompt + `narrateRoll()` caller (§8.4).
  gpt-4o-mini, ~100in/80out, fail-safe to null.
- [x] `resolve-roll/index.ts`: after main LLM call, checks
  `profiles.ai_role_roll_narrator_enabled`; if crit/fumble/|margin|≥10,
  calls `narrateRoll()` and replaces `dm.narration` with the vivid result.
- [x] `ai_roles_screen.dart`: removed "SOON" badge + stub flag from
  Role D tile. `_RoleTile` simplified (stub param deleted).

### Phase 5 — Migrate / deprecate old templates (optional) — ⏳ partial
- [x] Schema-side legacy lock done: `campaigns.is_legacy` defaults to
  `false`; existing pre-redesign campaigns were marked `true` in
  migration 20260511000000.
- [x] Router dispatches legacy campaigns to `GameScreen` (LLM DM) and
  graph campaigns to `StoryScreen`.
- [ ] Decide whether to author additional templates (Whispering Wood,
  Forgotten Crypt, etc.) as node graphs.
- [ ] If yes: one migration per template, ~30-80 nodes each.

### Phase 6 — Authoring tool (optional, future) — 📦 future
- [ ] Admin-only Flutter screen + edge function that takes a brief
  ("dark forest, missing child, 25 nodes") and emits a draft node graph
  via OpenAI for human review.

### Polish backlog (post-Phase 4)
- [ ] **Reskin caching** — currently re-rendering the same node
  re-pays tokens. Cache `body` per `(campaign_id, node_id)` in a new
  column or in `flags.__reskin_cache`.
- [ ] **Token attribution** — log per-role token usage to
  `request_logs` so the dashboard can show "this campaign used
  N tokens: reskinner X, npc_voice Y, intent_map Z".
- [ ] **`renderNodePayload` parallelization** — reskin + voice are
  sequential today; could be parallel since they target different
  node types.

---

## 13. Risks & open questions

1. **Authoring volume.** A good template is 25-80 nodes. Mitigation:
   ship one strong demo (Ember Outpost) and let players opt-in to it
   first; build authoring tool (Phase 6) before scaling content.
2. **Locked-option discoverability.** Showing every locked option could
   spoiler the content. Default `tags=["show_locked"]` only on key
   junctions, not every scene.
3. **Avatar lore relevance.** Already wired (migration 20260510). The
   reskinner uses avatar `voice_tags` and `backstory` as input; the
   signature-skill `requires.skill` gates avatar-specific edges. Both
   carry over cleanly.
4. **Combat integration.** Existing combat engine is untouched; story
   nodes of `type='combat'` invoke it via `on_enter_actions`. Combat
   completion writes back via a `flag` (`combat_won` / `combat_lost`)
   that the next edge can branch on.
5. **Resilience to OpenAI outages.** All four roles must degrade
   gracefully: if the API errors, fall back to deterministic body /
   outcome / option_id=null. *Never block the turn on the LLM.*
6. **Migration of in-flight sessions.** See §11. Lock legacy.
7. **Token attribution / metering.** Add per-call logging to
   `request_logs` (existing table) tagging which role consumed tokens
   so the dashboard can show "you used 1.2k tokens this campaign:
   reskinner 800, npc_voice 400".

---

## 14. Files / directories the next agent should touch

**Schema**
- `supabase/migrations/20260511000000_story_node_graph.sql` (NEW)
- `supabase/migrations/20260511000100_seed_demo_ember_outpost.sql` (NEW)

**Edge functions — shared**
- `supabase/functions/_shared/story_engine.ts` (NEW; gating + action applier)
- `supabase/functions/_shared/reskin.ts` (NEW; ROLE A)
- `supabase/functions/_shared/intent_mapper.ts` (NEW; ROLE B)
- `supabase/functions/_shared/npc_voice.ts` (NEW; ROLE C)
- `supabase/functions/_shared/roll_narrator.ts` (NEW; ROLE D)
- `supabase/functions/_shared/context.ts` (CHANGED; add node-state load helper)
- `supabase/functions/_shared/prompts.ts` (LIKELY DEPRECATED for non-combat; keep around for legacy mode)

**Edge functions — endpoints**
- `supabase/functions/dm-turn/index.ts` (REFACTORED per §7.1)
- `supabase/functions/player-action/index.ts` (NEW per §7.2)
- `supabase/functions/intent-map/index.ts` (NEW per §7.3)
- `supabase/functions/resolve-roll/index.ts` (CHANGED per §7.4)
- `supabase/functions/combat-action/index.ts` (UNCHANGED)

**Flutter**
- `lib/data/models/story_node.dart` (NEW)
- `lib/data/models/story_option.dart` (NEW)
- `lib/data/repositories/story_engine_repository.dart` (NEW)
- `lib/data/repositories/campaigns_repository.dart` (CHANGED — seed node state)
- `lib/features/game/game_screen.dart` (CHANGED — scripted options renderer)
- `lib/features/game/components/scripted_options.dart` (NEW)
- `lib/features/game/components/free_text_input.dart` (NEW)
- `lib/features/settings/ai_roles_screen.dart` (NEW)

**Existing systems left alone**
- All combat code (`combat-action`, combat repository, combat UI).
- All dice / skill resolution math (`dice.ts`, skills_repository, skill UIs).
- Avatar templates + signature skills (migration 20260510 already shipped).
- Codex, character creation, campaign list/picker, BGM, retro UI shell.

---

## 15. Glossary / quick reference

- **Node** — one beat of story. Has dry body text + entry actions.
- **Edge** — one option leading from a node to another, optionally gated.
- **Pivotal** — a node tagged for AI reskinning (rare; ~30% of nodes).
- **Flag** — boolean/typed value in `campaign_node_state.flags`, set
  by edges or actions, queried by `requires`.
- **Locked option** — an edge whose `requires` failed; may or may not
  be shown to player depending on node tags.
- **Voice tags** — adjectives from the chosen avatar template
  (`personality_tags`), fed to the reskinner so prose stays in character.
- **AI role** — one of A/B/C/D. Each toggleable per user.

---

## 16. Decision log

| Date | Decision | By |
|---|---|---|
| 2026-05-10 | Adopt scripted story graph + AI flavor; pick A+B+C+D | project owner |
| 2026-05-10 | Defer Role E (session summarizer) and Role F (authoring tool) | project owner |
| 2026-05-10 | Lock legacy campaigns rather than rewrite legacy templates | drafted; to confirm |
| 2026-05-10 | Default reskin policy = `pivotal_only` | drafted |
| 2026-05-10 | Free-text rate limit = 5 / campaign | drafted |

---

*End of document. Begin implementation at Phase 1, §12.*
