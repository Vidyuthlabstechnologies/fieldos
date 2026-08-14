# FieldOS

Construction site management: projects, tasks, daily progress reports (DPR),
issues, dashboards, and BOQ/estimation.

## Setup (no Docker required)

FieldOS uses a local SQLite database by default and Supabase Cloud (free tier)
only for authentication — there's no local Postgres, Docker, or Supabase CLI
stack to run.

### Backend

```bash
pip install -r requirements.txt
cp .env.example .env
```

Edit `.env`:
- `DATABASE_URL` — leave as the SQLite default, or point at a Postgres instance
  (e.g. a Supabase Cloud project's connection string) if you want one.
- `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` — from a free project at
  [supabase.com](https://supabase.com) (Project Settings → API). Required for
  login to work; nothing else needs Supabase.

```bash
python -m alembic upgrade head
uvicorn api:app --reload
```

API docs at http://localhost:8000/docs.

### Frontend

```bash
cd frontend
npm install
cp .env.local.example .env.local
```

Edit `.env.local` with the same Supabase project's URL and anon key
(Project Settings → API → `anon` `public` key).

```bash
npm run dev
```

App at http://localhost:3000.

## Project layout

- `fieldos/` — backend: models, routers, auth, config (`fieldos/app.py` builds
  the FastAPI app; `api.py` is the run entrypoint)
- `frontend/` — Next.js app
- `tests/` — pytest suite (`pytest tests/`)
- `resources/`, `advanced_kb*`, `kb_search_api.py` — a separate, optional
  construction-codes search tool (requires chromadb + a local Ollama instance).
  Not part of FieldOS and not needed to run it.
