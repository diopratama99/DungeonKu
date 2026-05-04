# DungeonKu — Supabase backend

## Layout

```
supabase/
├── config.toml
├── .env.example                    # OPENAI_API_KEY, OPENAI_MODEL, OPENAI_MODEL_SUMMARY
├── migrations/
│   ├── 20260101000000_init_schema.sql       # Tables, indexes, triggers
│   ├── 20260101000001_init_rls.sql          # RLS policies
│   ├── 20260101000002_seed_class_definitions.sql
│   ├── 20260101000003_seed_skills.sql
│   ├── 20260101000004_seed_avatar_templates.sql
│   ├── 20260101000005_seed_story_templates.sql
│   └── 20260101000006_seed_template_bosses_side_missions.sql
└── functions/
    ├── _shared/                    # Shared utils (no HTTP entry)
    ├── dm-turn/                    # Player action → DM response or roll request
    ├── resolve-roll/               # Player tapped dice → outcome narration (LLM call #2)
    ├── cheap-resolve/              # template_common option tap → static narration, no LLM
    ├── combat-action/              # Turn-based combat resolver
    └── summarize-campaign/         # gpt-4o-mini compression of message history
```

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
