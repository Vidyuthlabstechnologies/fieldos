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

## Building the desktop app

FieldOS also ships as a standalone offline desktop app (no Docker, no cloud,
no Python/Node install required on the end user's machine). Two pieces:

1. **Backend** — bundled into a single native executable with PyInstaller:

   ```bash
   pip install -r requirements-build.txt
   pyinstaller desktop_app.spec
   ```

   Produces `dist/FieldOS-backend.exe`. It self-migrates its database into
   the OS-appropriate app-data directory on first run (see
   [fieldos/paths.py](fieldos/paths.py)) — no separate install step.

2. **Frontend** — static export, built once:

   ```bash
   cd frontend && npm run build
   ```

   Produces `frontend/out/`, a fully static site. The project/estimation
   detail routes are query-param based (`/project?id=...`, not
   `/projects/[id]`) rather than `[id]`-style dynamic segments, since static
   export can't pre-render routes with unbounded runtime IDs.

3. **Installer** — Tauri wraps both into one `.exe`/`.msi`. It loads
   `frontend/out` directly and launches the backend as a background sidecar
   process (`src-tauri/src/lib.rs`); killed automatically when the window
   closes.

   ```bash
   npm install                                    # once, installs the Tauri CLI
   mkdir -p src-tauri/binaries
   cp dist/FieldOS-backend.exe src-tauri/binaries/FieldOS-backend-x86_64-pc-windows-msvc.exe
   npx tauri build
   ```

   Produces `src-tauri/target/release/bundle/nsis/FieldOS_<version>_x64-setup.exe`
   and the equivalent `.msi`. `tauri build` also runs the frontend build for
   you (see `beforeBuildCommand` in `src-tauri/tauri.conf.json`), so step 2
   above is only needed standalone if you want to preview `frontend/out` on
   its own. The sidecar binary's filename must end with the exact Rust
   target triple (`rustc --print host-tuple`) or Tauri won't find it.

## Project layout

- `fieldos/` — backend: models, routers, auth, config (`fieldos/app.py` builds
  the FastAPI app; `api.py` is the dev entrypoint, `desktop_app.py` the
  packaged-app entrypoint)
- `frontend/` — Next.js app
- `src-tauri/` — desktop shell (Rust/Tauri); launches the PyInstaller
  backend as a sidecar and loads `frontend/out`
- `importers/` — one-off scripts that turn a real client Excel BOQ sheet
  into a FieldOS project-export JSON, importable via the app's own "Import
  project" button. See `importers/narapally_boq.py` for the pattern:
  parse, then reconcile every figure against the sheet's own stated totals
  before writing anything — refuses to produce output on any mismatch.
- `tests/` — pytest suite (`pytest tests/`)
- `resources/`, `advanced_kb*`, `kb_search_api.py` — a separate, optional
  construction-codes search tool (requires chromadb + a local Ollama instance).
  Not part of FieldOS and not needed to run it.
