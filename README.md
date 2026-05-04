<div align="center">

# DungeonKu

**A solo-player DnD-style mobile RPG where the Dungeon Master is an LLM.**

Built with **Flutter** + **Supabase** (self-hosted) + **OpenAI GPT-4o**

<!-- badges -->
![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-Self--Hosted-3ECF8E?logo=supabase&logoColor=white)
![OpenAI](https://img.shields.io/badge/OpenAI-GPT--4o-412991?logo=openai&logoColor=white)
![Deno](https://img.shields.io/badge/Deno-Edge_Functions-000000?logo=deno&logoColor=white)
![License](https://img.shields.io/badge/License-Private-red)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Screenshots](#screenshots)
- [Tech Stack](#tech-stack)
- [Repo Structure](#repo-structure)
- [Architecture](#architecture)
- [Database Schema](#database-schema)
- [Edge Functions](#edge-functions)
- [Flutter App](#flutter-app)
- [Getting Started](#getting-started)
- [Deploying to Self-Hosted Supabase](#deploying-to-self-hosted-supabase)
- [Configuration Reference](#configuration-reference)
- [Design Tenets](#design-tenets)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Overview

DungeonKu is a mobile RPG where you create a character, pick a story campaign, and play through a procedurally narrated adventure. An AI Dungeon Master (GPT-4o) generates story beats, dialog options, and combat narration while the server enforces all game rules, dice rolls, damage calculations, and state transitions.

**Key features:**

- 6 character classes (Warrior, Mage, Rogue, Ranger, Priest, Bard) with unique skill trees
- 3 hand-crafted story campaigns with bosses, side missions, and phase-based pacing
- Server-side CSPRNG dice rolls with D&D-style modifiers and critical detection
- Turn-based combat with elemental damage multipliers and deterministic enemy AI
- Token-efficient LLM orchestration — most turns use zero LLM tokens
- Pixel-art retro UI with "Press Start 2P" and "VT323" fonts
- Permadeath per campaign, "Very Hard" difficulty by default

---

## Screenshots

> _TODO: Add screenshots of sign-in, character creation, campaign picker, game screen, combat, and game over._

---

## Tech Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| **Frontend** | Flutter 3.22+ | Cross-platform mobile app |
| **State Management** | Riverpod 2.x | Reactive providers + notifiers |
| **Routing** | go_router | Declarative auth-aware routing |
| **Backend** | Supabase (self-hosted Docker) | Postgres, Auth, Edge Functions |
| **Edge Functions** | Deno / TypeScript | Game logic orchestration |
| **AI** | OpenAI GPT-4o | Structured narrative generation |
| **AI (summary)** | GPT-4o-mini | Message history compression |
| **Validation** | Zod | Server-side schema validation |
| **UI Theme** | Google Fonts + custom widgets | Pixel-art retro aesthetic |

---

## Repo Structure

```
DungeonKu/
├── lib/                              # Flutter app source
│   ├── main.dart                     # Entry point, Supabase init
│   ├── core/
│   │   ├── env.dart                  # JSON config loader (supabase.json)
│   │   ├── router/app_router.dart    # go_router with auth redirect
│   │   ├── theme/
│   │   │   ├── app_theme.dart        # Pixel-art Material theme
│   │   │   └── pixel_colors.dart     # Color palette constants
│   │   └── widgets/
│   │       ├── pixel_panel.dart      # Double-bordered panel
│   │       ├── pixel_button.dart     # Chunky retro button
│   │       ├── pixel_progress_bar.dart
│   │       └── pixel_spinner.dart    # Rotating dots loader
│   ├── data/
│   │   ├── supabase_providers.dart   # Client + auth stream providers
│   │   ├── models/
│   │   │   ├── character.dart        # Character & CampaignCharacter
│   │   │   ├── campaign.dart         # Campaign, bosses, side missions, inventory
│   │   │   ├── messages.dart         # GameMessage, ChatOption, TurnResult
│   │   │   └── reference.dart        # ClassDef, Skill, AvatarTemplate, StoryTemplate
│   │   └── repositories/
│   │       ├── reference_repository.dart
│   │       ├── characters_repository.dart
│   │       ├── campaigns_repository.dart
│   │       └── game_repository.dart  # Edge Function call wrappers
│   └── features/
│       ├── auth/
│       │   ├── splash_screen.dart
│       │   └── sign_in_screen.dart
│       ├── characters/
│       │   ├── characters_screen.dart        # Roster (max 3)
│       │   └── character_creation_screen.dart # Class → element → avatar → name
│       ├── campaigns/
│       │   ├── campaigns_screen.dart         # Active / completed / fallen
│       │   └── template_picker_screen.dart   # Story selection + naming
│       ├── game/
│       │   ├── game_providers.dart           # GameNotifier (state machine)
│       │   ├── game_screen.dart              # Main gameplay screen
│       │   └── components/
│       │       ├── chat_view.dart            # Message history scroll
│       │       ├── action_panel.dart         # Option buttons
│       │       ├── dice_overlay.dart         # Roll animation + resolution
│       │       └── stats_sheet.dart          # Draggable character sheet
│       ├── game_over/
│       │   └── game_over_screen.dart
│       └── settings/
│           └── settings_screen.dart
│
├── supabase/
│   ├── migrations/
│   │   ├── 20260101000000_init_schema.sql          # 17 tables, indexes, triggers
│   │   ├── 20260101000001_init_rls.sql             # RLS policies
│   │   ├── 20260101000002_seed_class_definitions.sql
│   │   ├── 20260101000003_seed_skills.sql          # ~28 skills
│   │   ├── 20260101000004_seed_avatar_templates.sql # ~30 avatars
│   │   ├── 20260101000005_seed_story_templates.sql  # 3 campaigns
│   │   └── 20260101000006_seed_template_bosses_side_missions.sql
│   └── functions/
│       ├── deno.json                  # Import map
│       ├── _shared/                   # Shared modules (not HTTP-served)
│       │   ├── deps.ts                # Re-exports: zod, supabase-js, openai
│       │   ├── env.ts                 # Env var helpers
│       │   ├── cors.ts               # CORS headers + response helpers
│       │   ├── supabase.ts           # Service-role + user-auth clients
│       │   ├── logging.ts            # Structured JSON logger
│       │   ├── dice.ts               # CSPRNG dice rolling
│       │   ├── elements.ts           # Elemental multiplier table
│       │   ├── difficulty.ts         # DC clamping, XP curve, anti-stall
│       │   ├── classifier.ts         # Situation type heuristics
│       │   ├── phase_rules.ts        # Phase advance validation
│       │   ├── narration_pools.ts    # Static narration templates
│       │   ├── openai.ts            # GPT client wrapper (structured outputs)
│       │   ├── schemas.ts           # Zod + JSON schemas for LLM I/O
│       │   ├── context.ts           # Campaign context batch loader
│       │   ├── prompts.ts           # System prompt builder
│       │   └── state_changes.ts     # Server-side state applier
│       ├── dm-turn/index.ts          # Player action → DM response
│       ├── resolve-roll/index.ts     # Dice resolution + narration
│       ├── combat-action/index.ts    # Turn-based combat resolver
│       ├── cheap-resolve/index.ts    # Zero-LLM deterministic outcomes
│       └── summarize-campaign/index.ts
│
├── pubspec.yaml              # Flutter dependencies
├── analysis_options.yaml     # Dart lints
├── supabase.json             # Runtime config (gitignored)
├── .env.example              # Config template
├── dungeonku-prompt.md       # Full product specification
└── .gitignore
```

---

## Architecture

```
┌─────────────┐        HTTPS/WSS         ┌──────────────────────────────┐
│  Flutter App │ ◄──────────────────────► │   Supabase (self-hosted)     │
│              │    supabase_flutter       │                              │
│  Riverpod    │                          │  ┌─────────┐  ┌───────────┐ │
│  go_router   │                          │  │ GoTrue   │  │ Postgres  │ │
│              │                          │  │ (Auth)   │  │ (17 tbl)  │ │
└─────────────┘                          │  └─────────┘  └───────────┘ │
                                          │                              │
                                          │  ┌───────────────────────┐  │
                                          │  │   Edge Functions       │  │
                                          │  │   (Deno runtime)       │  │
                                          │  │                        │  │
                                          │  │  dm-turn ──────► OpenAI│  │
                                          │  │  resolve-roll ─► OpenAI│  │
                                          │  │  combat-action ► OpenAI│  │
                                          │  │  cheap-resolve  (no AI)│  │
                                          │  │  summarize ────► 4o-min│  │
                                          │  └───────────────────────┘  │
                                          └──────────────────────────────┘
```

### Request Flow (Player Turn)

1. Player taps an option in Flutter
2. Flutter calls an Edge Function via `supabase.functions.invoke()`
3. Edge Function loads full campaign context from Postgres
4. **Situation classifier** determines: `dialog` / `exploration` / `combat` / `transition`
5. For `template_common` options → **cheap-resolve** (zero tokens, static narration)
6. For rich options → **dm-turn** builds a system prompt and calls GPT-4o with structured outputs
7. If the LLM response includes `requires_roll` → persist a `pending_roll` and return to client
8. Client shows dice overlay → player taps → **resolve-roll** does CSPRNG + LLM call #2
9. Server applies validated `state_changes` (HP, XP, items, phase advances) to Postgres
10. Response returns to Flutter with narration + new options + updated stats

### Combat Flow

1. **dm-turn** triggers combat via `state_changes.start_combat`
2. Server creates `combat_encounters` + `combat_enemies` rows
3. Flutter switches to combat UI mode
4. Each turn → **combat-action** Edge Function handles:
   - Deterministic initiative ordering
   - Player attack/skill/defend/item/flee
   - Enemy AI (archetype-based: aggressive / tactical / boss)
   - Elemental damage multipliers
   - LLM narration only for boss specials, victory, defeat
5. Combat ends → server updates campaign state → return to exploration

---

## Database Schema

17 tables organized into 4 groups:

### Reference Data (public-read, seeded)
| Table | Description |
|-------|-------------|
| `class_definitions` | 6 classes with stats, skills, resource types |
| `skills` | ~28 skills with cost, dice, element, modifier |
| `avatar_templates` | ~30 avatars filtered by class |
| `story_templates` | 3 campaigns with world settings and DM guidance |
| `template_bosses` | Tiered bosses (small/medium/big) per template |
| `template_side_missions` | Trigger-based side quests per template |

### User Data
| Table | Description |
|-------|-------------|
| `profiles` | Auto-created on signup via trigger |
| `characters` | Max 3 per user, profile-level (reusable across campaigns) |

### Campaign State (per-run)
| Table | Description |
|-------|-------------|
| `campaigns` | Status, phase, turn counters |
| `campaign_characters` | Per-campaign snapshot: HP, MP/Stamina, level, XP, AC, stats |
| `campaign_inventory` | Items with type, element, quantity |
| `campaign_skills` | Learned skills per campaign |
| `campaign_bosses` | Boss encounter progress |
| `campaign_side_missions` | Side mission progress |

### Game Events
| Table | Description |
|-------|-------------|
| `messages` | Full conversation history with options and state changes |
| `world_memory` | Compressed summary of older messages |
| `combat_encounters` | Active/completed combats with turn order |
| `combat_enemies` | Enemy instances with HP, skills, archetype |
| `pending_rolls` | Awaiting player dice tap |
| `dice_rolls` | Completed roll audit log |

---

## Edge Functions

### `dm-turn` — Main Game Loop
The core orchestration pipeline. Handles player text/option input and returns DM narration with new options.

**Pipeline:** Auth → Context load → Classify situation → Build prompt → GPT-4o (structured output) → Validate & clamp → Apply state changes → Phase check → Side mission detection → Summarization trigger → Response

### `resolve-roll` — Dice Resolution
Called after the player taps the dice in the UI. Performs server-side CSPRNG roll, applies D&D-style modifiers, compares against DC, detects criticals, then calls GPT-4o for outcome narration.

### `combat-action` — Turn-Based Combat
Strict server-side combat. Handles initiative, player actions (attack/skill/defend/item/flee), enemy AI per archetype, elemental damage multipliers, status effects, and round progression. LLM only narrates boss signature moves, victory, and defeat scenes.

### `cheap-resolve` — Zero-Token Turns
Handles `template_common` option taps (Look around, Search, Move on, Rest, etc.) with deterministic rules and a static narration pool. No LLM call — keeps token costs near zero for routine exploration.

### `summarize-campaign` — Memory Compression
When message count exceeds threshold, compresses older messages into a `world_memory.summary` using GPT-4o-mini. This keeps the context window small while preserving narrative continuity.

---

## Flutter App

### State Management
- **Riverpod 2.x** with `StreamProvider` for auth state, `FutureProvider` for data fetching, and a custom `StateNotifier` (`GameNotifier`) for the game screen state machine.

### Routing
- **go_router** with auth-aware redirect. Unauthenticated users are always sent to `/sign-in`. Logged-in users at `/` or `/sign-in` are redirected to `/characters`.

### Screens
| Route | Screen | Description |
|-------|--------|-------------|
| `/` | Splash | Brief loading while auth resolves |
| `/sign-in` | Sign In | Email/password auth (sign up + sign in) |
| `/characters` | Characters | Roster of up to 3 characters |
| `/characters/new` | Character Creation | Class → element → avatar → name flow |
| `/campaigns` | Campaigns | Active, completed, and fallen campaigns |
| `/campaigns/new` | Template Picker | Story selection with optional run naming |
| `/game/:id` | Game | Main gameplay: chat, actions, dice, stats |
| `/game-over/:id` | Game Over | Final narration + character tombstone |
| `/settings` | Settings | Account info + sign out |

### UI Theme
Pixel-art retro aesthetic with:
- **Fonts:** "Press Start 2P" (headings, buttons), "VT323" (body text, chat)
- **Colors:** Parchment background, ink borders, gold accents, blood red for damage
- **Widgets:** `PixelPanel` (double-bordered frames), `PixelButton` (chunky with pressed state), `PixelProgressBar`, `PixelSpinner`

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Flutter SDK | ≥ 3.22 | [flutter.dev](https://flutter.dev) |
| Android Studio / Xcode | Latest | For emulators |
| OpenAI API key | — | [platform.openai.com](https://platform.openai.com) |

### 1. Clone the repo

```bash
git clone https://github.com/leykopin/DungeonKu.git
cd DungeonKu
```

### 2. Configure the app

```bash
cp .env.example supabase.json
```

Edit `supabase.json` with your Supabase instance details:

```json
{
  "SUPABASE_URL": "https://your-supabase-url.example.com",
  "SUPABASE_ANON_KEY": "eyJ..."
}
```

### 3. Install dependencies

```bash
flutter pub get
```

### 4. Run the database migrations

Open your Supabase **SQL Editor** and run each migration file in order:

1. `supabase/migrations/20260101000000_init_schema.sql`
2. `supabase/migrations/20260101000001_init_rls.sql`
3. `supabase/migrations/20260101000002_seed_class_definitions.sql`
4. `supabase/migrations/20260101000003_seed_skills.sql`
5. `supabase/migrations/20260101000004_seed_avatar_templates.sql`
6. `supabase/migrations/20260101000005_seed_story_templates.sql`
7. `supabase/migrations/20260101000006_seed_template_bosses_side_missions.sql`

All `CREATE TABLE` statements use `IF NOT EXISTS` so they are safe to re-run.

### 5. Deploy Edge Functions

```bash
rsync -avz supabase/functions/ user@your-server:~/supabase/docker/volumes/functions/
ssh user@your-server "cd ~/supabase/docker && docker compose restart functions"
```

Make sure the following environment variables are set for the functions runtime:
- `OPENAI_API_KEY`
- `OPENAI_MODEL` (default: `gpt-4o`)
- `OPENAI_MODEL_SUMMARY` (default: `gpt-4o-mini`)
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`

### 6. Run the app

```bash
flutter run --dart-define-from-file=supabase.json
```

---

## Deploying to Self-Hosted Supabase

This project is designed for a **self-hosted Supabase** running via Docker.

### Database

Paste migration SQL files into the **SQL Editor** in your Supabase dashboard. Run them in order (0000 → 0006).

### Edge Functions

```bash
# Sync function files to server
rsync -avz supabase/functions/ user@server:~/supabase/docker/volumes/functions/

# Restart the functions container
ssh user@server "cd ~/supabase/docker && docker compose restart functions"
```

### Flutter App

Build for release:

```bash
flutter build apk --dart-define-from-file=supabase.json
# or
flutter build ios --dart-define-from-file=supabase.json
```

---

## Configuration Reference

### `supabase.json` (Flutter app — gitignored)

```json
{
  "SUPABASE_URL": "https://your-instance.example.com",
  "SUPABASE_ANON_KEY": "eyJhbGciOiJIUzI1NiIs..."
}
```

This file is loaded as a Flutter asset at runtime and provides the Supabase connection details.

### Edge Function Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENAI_API_KEY` | Yes | OpenAI API key |
| `OPENAI_MODEL` | No | Model for dm-turn/resolve-roll/combat (default: `gpt-4o`) |
| `OPENAI_MODEL_SUMMARY` | No | Model for summarize-campaign (default: `gpt-4o-mini`) |
| `SUPABASE_URL` | Yes | Internal Supabase URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Service role key (bypasses RLS) |

---

## Design Tenets

- **Token economy first.** Most turns are cheap-resolved or use static narration. The LLM is a scarce resource called only for moments that matter.
- **Server is the source of truth.** Dice, damage, element multipliers, phase advancement, resource regen — all server-side. The LLM can *suggest* (e.g., a DC), but the server clamps and validates.
- **The world is re-asserted every turn.** The system prompt re-injects the template's `world_setting`, `dm_guidance`, current phase, and boss progress, so we don't need long message history to keep the DM on rails.
- **Very Hard by default.** No difficulty selector. Resources don't regen except on rest. No revives. Permadeath per campaign.
- **Structured outputs, not prompt engineering.** All LLM calls use OpenAI's structured output mode with JSON schemas, eliminating fragile "respond in JSON" prompt hacks.

---

## Troubleshooting

### App stuck on splash screen
The router redirect had a bug where unauthenticated users at `/` stayed on splash. This is fixed — unauthenticated users now go directly to `/sign-in`.

### `Unable to load asset: "supabase.json"`
Make sure `supabase.json` exists in the project root and is listed in `pubspec.yaml` under `flutter.assets`.

### RLS errors (`42501: new row violates row-level security policy`)
The campaign creation flow inserts into `campaign_characters`, `campaign_skills`, `campaign_bosses`, and `messages`. Make sure the INSERT policies exist (see migration `0001`).

### IDE shows hundreds of lint errors
This is **expected** before running `flutter pub get`. The Dart analyzer can't resolve packages until `.dart_tool/package_config.json` exists. For Supabase functions, install the [Deno VS Code extension](https://marketplace.visualstudio.com/items?itemName=denoland.vscode-deno).

### RenderFlex overflow warnings
Pixel fonts are wider than proportional fonts. Some layouts may show yellow/black overflow stripes on small screens. These are cosmetic and will be addressed in UI polish passes.

---

## License

Private — All rights reserved.

---

<div align="center">

Created by **Dio Pratama** — **TemanLabs**

</div>

---

<div align="center">

_See `dungeonku-prompt.md` for the full product specification._

</div>
