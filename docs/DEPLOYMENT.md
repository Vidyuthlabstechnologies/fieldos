# Deployment Guide

FieldOS ships as an **offline Windows desktop application** — there is no
server to deploy, no database to provision, and no cloud infrastructure of
any kind for the core product. This is a deliberate design choice: the app
must run on a construction site laptop with no internet connection. The
one optional exception is voice-to-DPR (Sarvam AI), which needs internet
only when that specific feature is used.

If you're looking for a cloud/SaaS deployment guide (Nginx, PostgreSQL,
Redis, S3, load balancers) — that does not describe this product. Don't
follow that pattern here; it will not work against this codebase.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              User's Windows laptop (offline)             │
│                                                            │
│   Tauri desktop shell (WebView2)                          │
│     ├─ loads frontend/out/  (Next.js static export)       │
│     └─ spawns backend sidecar process on launch,          │
│        kills it on window close                           │
│                    │                                      │
│                    ▼                                      │
│   FieldOS-backend.exe (PyInstaller-bundled FastAPI)        │
│     ├─ binds to loopback only (127.0.0.1)                 │
│     ├─ self-migrates its SQLite DB on first run            │
│     └─ CORS allowlist: tauri://localhost,                 │
│        http://tauri.localhost, https://tauri.localhost     │
│                    │                                      │
│                    ▼                                      │
│   SQLite DB — OS-appropriate app-data directory            │
│     (see fieldos/paths.py — Windows: %LOCALAPPDATA%)       │
└─────────────────────────────────────────────────────────┘
                     │
                     │ (only when voice-to-DPR is used,
                     │  and only if a Sarvam API key is
                     │  configured in-app under Settings)
                     ▼
              api.sarvam.ai (STT + LLM)
```

Everything else — projects, tasks, DPR, issues, BOQ/estimation, auth — is
100% local, 100% offline, always.

## Building and packaging (what "deployment" means for this app)

"Deploying" FieldOS means producing an installer (`.exe`/`.msi`) and
handing it to the client. Full step-by-step build instructions live in the
root [`README.md`](../README.md) — this section is a summary; treat the
README as the source of truth if they ever disagree.

### 1. Backend → single executable (PyInstaller)

```bash
pip install -r requirements-build.txt
pyinstaller desktop_app.spec
```

Produces `dist/FieldOS-backend.exe`. On first run on the end user's
machine, it self-migrates its SQLite database into the OS app-data
directory (`fieldos/paths.py`) — no separate install/setup step, no DB
server to stand up.

### 2. Frontend → static export

```bash
cd frontend && npm run build
```

Produces `frontend/out/`, a fully static site (`output: "export"` in
`next.config.mjs`). Because it's a static export, dynamic routes use
query-param-based routing (`/project?id=...`) rather than `[id]`-style
segments — static export can't pre-render an unbounded set of runtime IDs.

### 3. Installer (Tauri)

```bash
npm install
mkdir -p src-tauri/binaries
cp dist/FieldOS-backend.exe src-tauri/binaries/FieldOS-backend-x86_64-pc-windows-msvc.exe
npx tauri build
```

Produces `src-tauri/target/release/bundle/nsis/FieldOS_<version>_x64-setup.exe`
and the equivalent `.msi`. The sidecar binary's filename must end with the
exact Rust target triple (`rustc --print host-tuple`) or Tauri won't find it.

Install mode is `currentUser` (see `src-tauri/tauri.conf.json`) — the
installer does **not** require admin rights or UAC elevation. This was a
deliberate fix (see git history: "per-user NSIS install mode — no admin
rights required"); don't change it back to a machine-wide install without
a specific reason, since it breaks on locked-down client machines.

## What there is no deployment story for (and why that's correct)

- **No server/hosting**: nothing runs anywhere except the client's own
  laptop. There is no `api.fieldos.example.com` to stand up.
- **No database server**: SQLite, file-based, lives in the app-data
  directory. No PostgreSQL, no connection string to manage in production.
- **No Redis**: sessions are DB-backed (see `fieldos/auth.py`), not
  cache/pub-sub backed. There is no session/cache infrastructure to run.
- **No CDN/object storage**: uploaded files (documents, inspection/material
  photos) are written to the local app-data directory (`fieldos/paths.py`'s
  `uploads_dir()`), not to S3 or equivalent.
- **No CI/CD pipeline to a live environment**: there's nothing to
  continuously deploy to. "Shipping" is building an installer and handing
  it to the client (or, eventually, an internal release process for
  pushing a new installer/update — not yet built).

## Billing (Stripe) — present in code, not currently wired to anything real

`fieldos/routers/billing.py` exists and expects `STRIPE_SECRET_KEY` /
`STRIPE_WEBHOOK_SECRET` environment variables, but as of this writing
nothing in the frontend calls any billing endpoint, and there's no live
Stripe account/webhook configured anywhere. If/when a paid-subscription
model is actually adopted, this is where that config goes — but doing so
means this specific offline-first laptop process would need outbound
internet access for that feature, exactly like the Sarvam voice-DPR
exception above. Until that's a real product decision, leave
`STRIPE_SECRET_KEY` unset; billing endpoints will correctly return 503.

## Updating this document

If you're about to write "the server" or "production database" anywhere in
this file, stop — that's very likely describing a different product than
this one. Cross-check against the root `README.md` and `fieldos/app.py`'s
CORS allowlist (which only permits the Tauri app and the local dev server —
nothing else could reach this backend even if it were somehow exposed)
before adding deployment instructions here.
