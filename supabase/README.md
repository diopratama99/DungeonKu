# DungeonKu — Supabase backend

All app tables live in a dedicated **`dungeonku`** schema so DungeonKu can
coexist with other apps on the same self-hosted Supabase. The Flutter client
and every Edge Function go through a schema-scoped client (`db.schema =
"dungeonku"`), so app code never has to qualify table names.

## Layout

```
supabase/
├── config.toml
├── .env.example                    # OPENAI_API_KEY, OPENAI_MODEL, OPENAI_MODEL_SUMMARY
├── migrations/
│   ├── 20260101000000_init_schema.sql               # Tables, indexes, triggers (created in public)
│   ├── 20260101000001_init_rls.sql                  # RLS policies
│   ├── 20260101000002_seed_class_definitions.sql
│   ├── 20260101000003_seed_skills.sql
│   ├── 20260101000004_seed_avatar_templates.sql
│   ├── 20260101000005_seed_story_templates.sql
│   ├── 20260101000006_seed_template_bosses_side_missions.sql
│   ├── 20260507000000_move_to_dungeonku_schema.sql  # public → dungeonku schema move
│   ├── 20260507001000_use_local_avatar_assets.sql   # avatar_templates.image_url → assets/images/avatars/...
│   └── 20260507002000_use_local_campaign_cover_assets.sql  # story_templates.cover_image_url → assets/images/campaigns/covers/...
└── functions/
    ├── _shared/                    # Shared utils (no HTTP entry)
    ├── dm-turn/                    # Player action → DM response or roll request
    ├── resolve-roll/               # Player tapped dice → outcome narration (LLM call #2)
    ├── cheap-resolve/              # template_common option tap → static narration, no LLM
    ├── combat-action/              # Turn-based combat resolver
    └── summarize-campaign/         # gpt-4o-mini compression of message history
```

## Schema migration (`20260507000000_move_to_dungeonku_schema.sql`)

Idempotent forward migration. Highlights:

- Creates schema `dungeonku`.
- `ALTER TABLE ... SET SCHEMA dungeonku` for every app table (RLS, indexes,
  constraints, and table-level triggers move automatically).
- `dungeonku.profiles` is created fresh + backfilled so it can coexist with a
  shared `public.profiles` from another app on the same Supabase instance.
- App functions (`is_campaign_owner`, `enforce_character_limit`,
  `handle_new_user`, `touch_updated_at`) recreated in `dungeonku` with explicit
  `search_path`. RLS policies are recreated to call `dungeonku.is_campaign_owner`.
- `auth.users` trigger renamed to `on_auth_user_created_dungeonku` so multiple
  apps' signup hooks can coexist on the same `auth.users`.
- Grants + default privileges for `anon`, `authenticated`, `service_role`.

Re-running is safe — every step is wrapped in existence checks / `IF NOT
EXISTS` / `DROP ... IF EXISTS` + `CREATE`.

## Local asset migrations

The two `2026050700{1,2}000_use_local_*.sql` files rewrite stored URLs from
`placehold.co` placeholders to local Flutter asset paths so the client renders
real PNGs from `assets/images/...` after the user drops art into the project.

- `avatar_templates.image_url` → `assets/images/avatars/<id>.png`
- `story_templates.cover_image_url` → `assets/images/campaigns/covers/<id>.png`

Both target either `dungeonku.*` or fall back to `public.*`, so they're safe to
run before or after the schema move.

## Run locally

```bash
supabase start
supabase functions serve --env-file .env
```

## Deploy

```bash
supabase db push --linked
supabase functions deploy dm-turn
supabase functions deploy resolve-roll
supabase functions deploy combat-action
supabase functions deploy cheap-resolve
supabase functions deploy summarize-campaign
```

## Edge Function client conventions

`functions/_shared/supabase.ts` exposes:

- `getServiceClient()` — service-role client (bypasses RLS) used to mutate
  game state. Pre-configured with `db: { schema: "dungeonku" }`.
- `getAuthenticatedUser(req)` — user-scoped client, only used to verify the
  caller's JWT; also pinned to the `dungeonku` schema for any incidental
  `.from()` call.
- `assertCampaignOwner(campaignId, userId)` — defense-in-depth ownership check
  using the service client.

Every `.from("...")` and `.rpc("...")` call inside `functions/**` therefore
targets the `dungeonku` schema without needing schema qualification in code.
