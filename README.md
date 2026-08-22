# FieldOS

Construction site management for Protek Consult, built by Predictera Pvt
Ltd: projects, tasks, daily progress reports (DPR), issues, dashboards,
BOQ/estimation, materials, workers & attendance, documents, procurement
(vendor → requisition → RFQ → quote → PO → GRN), equipment & machinery,
inspections & quality checklists, and per-project real-time collaboration.
Voice-to-DPR is powered by Sarvam AI.

Ships two ways: an **offline Windows desktop app** (Tauri + a
PyInstaller-bundled FastAPI backend — the primary, shipped product) and a
**native offline mobile app** (Flutter, `fieldos_mobile/`). See
[docs/PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md) for the full feature
list and [docs/README.md](docs/README.md) for the complete documentation
index — this file covers day-to-day setup and building; `docs/` has the
depth (API reference, database schema, deployment, troubleshooting).

## Setup (fully offline, no Docker, no cloud account required)

FieldOS uses a local SQLite database and local username/password accounts.
Nothing talks to the internet — no Docker, no Postgres, no external service
of any kind — except two specifically optional features: voice-to-DPR
(Sarvam AI) and billing (Stripe, not currently wired to any UI). Everything
else works with the network off.

### Backend

```bash
python -m venv .venv                          # first time only

# Windows
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe -m alembic -c alembic.ini upgrade head
.venv\Scripts\python.exe -m uvicorn api:app --reload

# macOS/Linux
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python -m alembic -c alembic.ini upgrade head
.venv/bin/python -m uvicorn api:app --reload
```

Always run through `.venv`, not a bare `python`/`pip` on PATH — a global
install can have different (or missing) package versions and will give you
misleading results, especially for test runs.

API docs at http://localhost:8000/docs. (`.env.example` documents the
optional overrides — `DATABASE_URL` if you want a different SQLite file
path, `SARVAM_API_KEY` for voice-to-DPR, `STRIPE_SECRET_KEY`/
`STRIPE_WEBHOOK_SECRET` for billing.) Note `alembic.ini` lives at the repo
root, not inside `fieldos/` — always pass `-c alembic.ini` explicitly.

### Frontend

```bash
cd frontend
npm install
cp .env.local.example .env.local
npm run dev
```

App at http://localhost:3000. First run: create an account on the login
page, then create your company when prompted. The frontend reads
`NEXT_PUBLIC_API_BASE_URL` (default `http://localhost:8000`) — that exact
variable name matters; every file under `frontend/lib/` reads it, and a
differently-named variable is silently ignored.

### Mobile app (Flutter)

The mobile app is a separate, native Flutter project at `fieldos_mobile/`
— not a wrapper around the web frontend. It's fully offline with its own
local auth and local (drift/SQLite) database.

```bash
cd fieldos_mobile
flutter pub get
flutter analyze     # should report "No issues found!"
flutter test        # unit/widget test suite
flutter run
```

**Known gap:** as of this writing, the mobile app has no connection to the
FastAPI backend at all — it's a standalone data silo, not a client of the
same server the desktop app uses. See
[docs/MOBILE_GUIDE.md](docs/MOBILE_GUIDE.md) for the full picture,
including why, and what a real sync layer would need.

(An earlier Capacitor-based wrapper around the Next.js frontend also exists
at `frontend/android/` — it's deprecated in favor of the native Flutter
app; see [frontend/MOBILE.md](frontend/MOBILE.md) for details. Don't build
on it.)

### Running tests

```bash
# Backend
.venv\Scripts\python.exe -m pytest tests/          # Windows
.venv/bin/python -m pytest tests/                  # macOS/Linux

# Frontend
cd frontend && npm test

# Mobile
cd fieldos_mobile && flutter test
```

All three suites are green on a clean checkout. There is currently no
linter/formatter/type-checker configured for either the Python or
TypeScript side (`npx tsc --noEmit` does work as a plain compile check,
since a `tsconfig.json` exists, but nothing runs it automatically) — see
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) before assuming a `ruff`/`eslint`
setup exists.

## Building the desktop app

FieldOS also ships as a standalone offline desktop app (no Docker, no cloud,
no Python/Node install required on the end user's machine). Three pieces:

1. **Backend** — bundled into a single native executable with PyInstaller:

   ```bash
   pip install -r requirements-build.txt
   pyinstaller desktop_app.spec
   ```

   Produces `dist/FieldOS-backend.exe`. It self-migrates its database into
   the OS-appropriate app-data directory on first run (see
   [fieldos/paths.py](fieldos/paths.py)) — no separate install step. The
   spec bundles the entire `fieldos/alembic/versions/` directory, so new
   migrations are picked up automatically on the next build with no spec
   changes needed.

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
   target triple (`rustc --print host-tuple`) or Tauri won't find it. Install
   mode is `currentUser` (no admin/UAC elevation required) — this was a
   deliberate fix for locked-down client machines; don't change it back to
   a machine-wide install without a specific reason.

   The backend's CORS allowlist (`fieldos/app.py`) only permits
   `tauri://localhost` / `http://tauri.localhost` / `https://tauri.localhost`
   (Windows/WebView2 specifically needs the `http://` scheme, not `https://`
   — a past incident, see git history) and `http://localhost:3000` for the
   dev server. Nothing else can reach this backend even if it were somehow
   network-exposed.

## Mobile app packaging (Flutter)

```bash
cd fieldos_mobile
flutter build apk --release        # or: flutter build appbundle --release
```

See [docs/MOBILE_GUIDE.md](docs/MOBILE_GUIDE.md) for the full picture.

## Project layout

- `fieldos/` — backend: models, routers, auth, config (`fieldos/app.py`
  builds the FastAPI app; `api.py` is the dev entrypoint, `desktop_app.py`
  the packaged-app entrypoint). `fieldos/routers/` covers auth, companies,
  projects, tasks, dpr, issues, dashboard, estimation, settings, portability,
  materials, workers (+ attendance), documents, procurement, equipment,
  inspections, realtime (WebSocket), and billing (Stripe, unwired to any UI
  yet).
- `fieldos/alembic/` — migrations. Config file is `alembic.ini` at the repo
  root, not inside this directory — always run with `-c alembic.ini`.
- `frontend/` — Next.js app (static export), the desktop app's UI. Also
  contains a deprecated Capacitor Android wrapper (`frontend/android/`,
  `capacitor.config.ts`) — see `frontend/MOBILE.md`.
- `fieldos_mobile/` — native Flutter mobile app, the maintained mobile
  strategy. Fully offline with its own local auth/database; not yet
  connected to the FastAPI backend (see `docs/MOBILE_GUIDE.md`).
- `src-tauri/` — desktop shell (Rust/Tauri); launches the PyInstaller
  backend as a sidecar and loads `frontend/out`.
- `importers/` — one-off scripts that turn a real client Excel BOQ sheet
  into a FieldOS project-export JSON, importable via the app's own "Import
  project" button. See `importers/narapally_boq.py` for the pattern:
  parse, then reconcile every figure against the sheet's own stated totals
  before writing anything — refuses to produce output on any mismatch.
- `tests/` — pytest suite (`pytest tests/`).
- `docs/` — the full documentation set: API reference, database schema,
  deployment, development workflow, frontend architecture, mobile guide,
  project overview, testing, troubleshooting. Start at
  [docs/README.md](docs/README.md).
- `AGENTS.md` — conventions and quick commands for AI coding agents working
  in this repo.
- `resources/`, `advanced_kb*`, `kb_search_api.py` — a separate, optional
  construction-codes RAG search tool (requires chromadb + a local Ollama
  instance). Not part of FieldOS and not needed to run it — see the comment
  at the top of `kb_search_api.py`.
