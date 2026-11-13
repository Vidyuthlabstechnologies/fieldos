# FieldOS

Construction site management for Protek Consult, built by Predictera Pvt
Ltd, ultimately for sale to construction companies in India. Two real
products, not a demo: an **offline Windows desktop app** (Tauri + a
PyInstaller-bundled FastAPI backend) and a **native Android mobile app**
(Flutter, `fieldos_mobile/`) that additionally syncs across every
employee's phone via a self-hosted-free Supabase backend — no paid server,
no cloud instance the user has to cover. `fieldos_mobile/` is where nearly
all active development happens today; the desktop app is feature-complete-ish
and comparatively static. See [docs/PROJECT_OVERVIEW.md](docs/PROJECT_OVERVIEW.md)
for prose detail and [docs/README.md](docs/README.md) for the full
documentation index.

> **If you're an AI agent picking this project up**: read
> [docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md) first (absolute rules,
> exact current architecture, known gotchas, the entity-sync recipe), then
> [docs/COMPLETION_PLAN.md](docs/COMPLETION_PLAN.md) (verified ground
> truth, what's done/partial/not-started, a suggested execution order).
> Both stay current; this README's job is orientation and setup commands,
> not the living state of the project.

## Features

**Desktop** (`fieldos/` + `frontend/`, offline, no cloud): projects, tasks
(Kanban), daily progress reports with voice-to-DPR (Sarvam AI), issues,
dashboards, BOQ/estimation (cost heads, measurement/steel entries, PDF
export), materials tracking with photo evidence, workers & attendance,
versioned documents, the full procurement chain (vendor → requisition →
RFQ → quote → PO → GRN), equipment & machinery logs, inspections & quality
checklists, multi-level approvals, per-project WebSocket real-time
collaboration, project export/import for cross-laptop portability. Billing
(Stripe) exists in code but is deliberately unwired to any UI.

**Mobile** (`fieldos_mobile/`, native Flutter, Android-only, offline-first):
every module above except billing/WebSocket-realtime (Supabase Realtime
instead — see below), plus:
- **Cross-device cloud sync** — a hand-rolled transactional outbox syncs
  18 of ~20 syncable tables against a real Postgres backend (Supabase:
  Auth + Postgres + Realtime + Storage + RLS), with a manual "Sync now", a
  periodic background trigger, live Realtime updates on the highest-traffic
  screens, and visible sync status (pending count, last-synced time) in
  Settings. Documents sync their actual file bytes through Supabase
  Storage, not just a metadata row.
- **The BOQ calc engine exists twice, cross-checked**: a pure-Dart port for
  every screen, and the desktop's exact `estimation_calc.py` embedded
  on-device via Chaquopy for the one calculation where floating-point
  precision matters — a 241-case differential test proves the two agree to
  a documented tolerance.
- **Camera-first photo capture** for DPR entries (`image_picker`);
  inspections/materials still use a generic file picker (see
  `docs/COMPLETION_PLAN.md`).
- Local pbkdf2 auth, bridged to a real Supabase Auth session only when
  cloud sync is enabled.

**Not yet built, on either platform**: chat/team messaging, a map view,
push notifications. See "Reference apps" below and
`docs/COMPLETION_PLAN.md` for what closing these would take.

## Architecture

```
Desktop (shipped product):
  Tauri shell -> frontend/out (Next.js static export)
    + a PyInstaller-bundled FastAPI backend, spawned as a loopback-only
      sidecar process -> SQLite (local file, OS app-data directory)
  No server, no Postgres, no cloud dependency of any kind.

Mobile (fieldos_mobile/, native Flutter, the active development target):
  Local: Riverpod + drift/SQLite, own local pbkdf2 auth -- fully
    functional with zero network connection.
  Cloud sync (optional, user-enabled): a transactional outbox
    (lib/sync/) pushes/pulls against Supabase -- Postgres + Auth +
    Realtime + Storage, every table behind row-level security. Today
    that's a local Docker dev stack; docs/SUPABASE_PRODUCTION_RUNBOOK.md
    covers the (mostly configuration-only) cutover to a real project.
  Mobile has NO connection to the desktop's FastAPI backend or its
  SQLite database -- syncing is mobile-device-to-mobile-device via
  Supabase, not mobile-to-desktop.
```

See `docs/FRONTEND_ARCHITECTURE.md` (Next.js) and
`docs/AGENT_HANDOFF.md`'s "fieldos_mobile/ architecture" and "Cloud sync"
sections for the full depth on each side.

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
flutter analyze     # clean except one pre-existing, unrelated warning (see "Tests")
flutter test        # unit/widget test suite
flutter run
```

**Mobile has no connection to the desktop's FastAPI backend** — it never
reads or writes the desktop app's SQLite database, and there's no plan to
unify them. It **does** sync mobile-device-to-mobile-device via a
self-hosted-free Supabase backend — see "Architecture" above and
[docs/AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md) for the current entity
coverage and exact mechanism. To exercise that locally you'll also need
the Supabase CLI and Docker running (`supabase start` from the repo root)
— see "Tests" below.

(The old Capacitor wrapper (`frontend/android/`) was removed in November 2026 (issue #155).)

## Tests

A change isn't done until the relevant suite below is green — an agent
picking up work here should run the matching suite before calling
anything finished, not just `flutter analyze`/`tsc` and assume the rest.

```bash
# Backend (3 test files, tests/) -- offline, no setup beyond the venv above
.venv\Scripts\python.exe -m pytest tests/          # Windows
.venv/bin/python -m pytest tests/                  # macOS/Linux

# Frontend (11 test files) -- offline
cd frontend && npm test

# Mobile (28 test files, ~303 individual tests) -- see below before running
cd fieldos_mobile && flutter analyze && flutter test
```

Backend and frontend suites are fully offline and should just pass on a
clean checkout. **Mobile is different on purpose**: every sync-layer test
hits a real local Supabase stack — no mocks — because that discipline has
caught real bugs (an RLS policy silently no-op'ing an update, a Realtime
publication starting empty, a concurrency race that poisoned the outbox)
that a mocked suite provably would have missed. Before trusting a mobile
test run:

```bash
docker ps                # confirm Docker Desktop is running
supabase start            # from the repo root -- first time, or if stopped
supabase db reset          # after pulling any change to supabase/migrations/
```

Tests self-skip (report as passed, not failed) if the stack isn't
reachable — a green run with Docker down proves nothing. `flutter analyze`
should report clean except one pre-existing, unrelated deprecation warning
in `labour_screen.dart`. One test
(`test/sync_engine_realtime_test.dart`) can fail exactly once right after
the Supabase stack restarts (the Realtime container needs a moment to warm
up) — re-run it alone before treating that specific failure as real; see
`docs/AGENT_HANDOFF.md`'s gotchas for the full list of known-flaky-vs-real
failure patterns. CI (`.github/workflows/mobile.yml`) runs this exact
sequence on every push.

There is currently no linter/formatter/type-checker configured for either
the Python or TypeScript side (`npx tsc --noEmit` does work as a plain
compile check, since a `tsconfig.json` exists, but nothing runs it
automatically) — see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) before
assuming a `ruff`/`eslint` setup exists.

## Reference apps

Real competitors, fact-checked against primary sources rather than taken
on faith — see [docs/MARKET_UX_RESEARCH.md](docs/MARKET_UX_RESEARCH.md)
for the full research pass, citations, and UI/UX findings. Useful as
benchmarks for scoping feature-breadth work, not as a checklist to blindly
match feature-for-feature.

| App | What it actually is | Relevant to FieldOS |
|---|---|---|
| [Kraaft](https://kraaft.co) | "7-in-1 app" positioned as an augmented WhatsApp for construction: chat, maps, voice reports, folders, planning, AI agents, integrations. 30,000+ users, VINCI/Bouygues as real customers. | The chat/messaging gap — FieldOS has nothing here today. Its Realtime-backed sync layer is architecturally the right foundation for one. |
| [Onsite](https://onsiteteams.com) | Hybrid mobile+desktop ERP: sales & tendering, design management, planning & budgeting, progress tracking, material & inventory, labour & salaries, subcontractor management, assets & equipment, procurement, BOQ & billing, quality management, finance & accounts. | The broadest module-for-module comparison — FieldOS's own module list (Features, above) tracks closely against this one already. |
| [Fieldwire](https://www.fieldwire.com) (Hilti) | Field-first, genuinely offline-capable jobsite management: plans, tasks, punch lists, custom forms. Free tier + paid per-user. | The closest reference for "offline-first, field-worker-facing" execution quality — worth studying its actual UI (not just marketing) for the punch-list/task-board pattern. |
| [Procore](https://www.procore.com) | GC-focused: financials, contracts, RFIs, change orders. Sales-only pricing, enterprise-oriented. | Less relevant to FieldOS's SMB/field-crew focus — a reference for what NOT to prioritize (heavy financial/contract tooling) before the core workflows are solid. |
| [Buildertrend](https://buildertrend.com) | Residential-focused: scheduling, client portals, estimating. | A reference for client-facing portals specifically, if that's ever scoped — not otherwise close to FieldOS's target user. |
| [SiteVoice](https://sitevoice.app) | UK voice-first inspection/snagging tool: hold-to-talk, live waveform, AI-extracted structured defect cards, mandatory review step before save. | The direct reference for FieldOS's own voice-to-DPR pattern — independently confirmed to already match this app's shape; the one improvement identified and not yet built is showing the interim transcript live during recording. |

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
- `frontend/` — Next.js app (static export), the desktop app's UI.
- `fieldos_mobile/` — native Flutter mobile app, the active development
  target. Fully offline-capable with its own local auth/database; never
  connects to the FastAPI backend, but does sync device-to-device via
  Supabase (see `docs/AGENT_HANDOFF.md`).
- `supabase/` — Postgres schema + RLS policies for mobile's cross-device
  sync (`supabase/migrations/`), plus a local Docker dev stack config.
  No production Supabase project exists yet — see
  `docs/SUPABASE_PRODUCTION_RUNBOOK.md`.
- `.github/` — CI/CD: `workflows/mobile.yml` (starts a real local Supabase
  stack, runs `flutter analyze` + the full mobile test suite),
  `workflows/backend.yml` (pytest), `workflows/frontend.yml` (`tsc`,
  vitest, the static export build) all run on every push/PR touching
  their area. `workflows/release.yml` builds the signed mobile
  APK/AAB and the desktop installer and drafts a GitHub Release when
  a `v*` tag is pushed (needs `ANDROID_KEYSTORE_BASE64` +
  `ANDROID_KEY_ALIAS`/`ANDROID_KEY_PASSWORD`/`ANDROID_STORE_PASSWORD`
  repo secrets for real signing; builds debug-signed and says so in
  the release notes otherwise). `dependabot.yml` covers pub/npm/pip/
  Actions. **Branch protection isn't available on this repo's current
  plan** (private repo, free tier) — nothing blocks a merge
  automatically, so a green check on a PR is informational, not
  enforced; see `.github/pull_request_template.md`'s checklist for
  the actual gate until that changes.
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
  project overview, testing, troubleshooting, market/competitor research,
  plus [AGENT_HANDOFF.md](docs/AGENT_HANDOFF.md) and
  [COMPLETION_PLAN.md](docs/COMPLETION_PLAN.md) for an AI agent picking up
  the project. Start at [docs/README.md](docs/README.md).
- `AGENTS.md` — conventions and quick commands for AI coding agents working
  in this repo.
- `resources/`, `advanced_kb*`, `kb_search_api.py` — a separate, optional
  construction-codes RAG search tool (requires chromadb + a local Ollama
  instance). Not part of FieldOS and not needed to run it — see the comment
  at the top of `kb_search_api.py`.
