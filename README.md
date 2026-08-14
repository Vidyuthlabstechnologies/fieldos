# FieldOS

Construction site management: projects, tasks, daily progress reports (DPR),
issues, dashboards, and BOQ/estimation.

## Setup (fully offline, no Docker, no cloud account required)

FieldOS uses a local SQLite database and local username/password accounts.
Nothing talks to the internet — no Docker, no Supabase, no external service
of any kind.

### Backend

```bash
pip install -r requirements.txt
python -m alembic upgrade head
uvicorn api:app --reload
```

API docs at http://localhost:8000/docs. (`.env.example` documents the one
optional override, `DATABASE_URL`, if you want something other than the
default SQLite file.)

### Frontend

```bash
cd frontend
npm install
cp .env.local.example .env.local
npm run dev
```

App at http://localhost:3000. First run: create an account on the login
page, then create your company when prompted.

## Project layout

- `fieldos/` — backend: models, routers, auth, config (`fieldos/app.py` builds
  the FastAPI app; `api.py` is the run entrypoint)
- `frontend/` — Next.js app
- `tests/` — pytest suite (`pytest tests/`)
- `resources/`, `advanced_kb*`, `kb_search_api.py` — a separate, optional
  construction-codes search tool (requires chromadb + a local Ollama instance).
  Not part of FieldOS and not needed to run it.
