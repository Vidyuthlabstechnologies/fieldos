# AGENTS.md - AI Agent Instructions for FieldOS

## Project Context

FieldOS is a fully offline construction site management platform (desktop
+ mobile, no server/cloud for the core product — see `docs/DEPLOYMENT.md`
before assuming otherwise) with:
- **Backend**: FastAPI (Python 3.12), SQLAlchemy 2.0, SQLite only. Packaged
  via PyInstaller as a sidecar process inside a Tauri desktop shell.
- **Frontend**: Next.js 16 (App Router, static export), React, TypeScript,
  Tailwind CSS
- **Mobile**: Flutter, native, fully offline with its own local database —
  see `fieldos_mobile/` and `docs/MOBILE_GUIDE.md`. (The old Capacitor
  wrapper was removed in November 2026, issue #155.)
- **Real-time**: WebSocket per-project rooms (desktop app only; the Flutter
  mobile app has no connection to the backend at all yet)
- **Voice AI**: Sarvam AI for Indic language voice DPR, only when the
  phone's own recognizer can't do the language. On mobile it goes through
  the `ai-assistant` Supabase edge function with one shared key; users never
  enter a key.
- **AI assistant (mobile)**: "Ask FieldOS" on Home. Claude runs behind the
  `ai-assistant` edge function (`supabase/functions/ai-assistant/`, keys are
  function secrets, plan + a monthly ₹ cap per person checked there; Claude
  Haiku, with DeepSeek on Sarvam as the backup); the actions run on the
  phone (`lib/agents/assistant_tools.dart`) and every change waits on a
  confirm card. Tool names in `tools.ts` and `assistant_tools.dart` must
  match (a test checks). See `docs/AI_ASSISTANT.md`.

- **Company plans**: builder firms pay by GST invoice outside the stores;
  the team switches a plan on in Supabase and it covers everyone in the
  company, up to a number of active sites. The apps must never show its
  price or a way to buy it. See `docs/COMPANY_PLANS.md`.

## Code Style Rules

### Python (Backend)
- Type hints **required** on all functions
- SQLAlchemy 2.0: `Mapped`, `mapped_column`
- Decimal for money/quantities (never float)
- Pydantic v2 schemas with `ConfigDict(from_attributes=True)`
- Async/await for I/O (FastAPI native)

### TypeScript (Frontend)
- Strict mode enabled
- Functional components + hooks
- "use client" for interactive pages
- Tailwind CSS utility-first
- Mobile-first responsive (`sm:`, `lg:`)

### General
- No comments that just restate what the code does. But this codebase
  consistently uses short comments to record the WHY behind a non-obvious
  decision -- a hidden constraint, a past incident, a security rationale
  (see `fieldos/app.py`'s CORS allowlist comment, `fieldos/permissions.py`'s
  `require_any_owner_role` docstring, `importers/narapally_boq.py`'s
  reconciliation comments). Match that: skip comments that narrate, keep
  ones that explain why a future reader would otherwise get it wrong.
- Concise, direct code
- Follow existing patterns in codebase

## Common Patterns

### Adding a New Backend Router

```python
# 1. Create fieldos/routers/new_feature.py
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.permissions import require_project_access
from fieldos.schemas import NewFeatureCreate, NewFeatureOut

router = APIRouter(tags=["new_feature"])

@router.post("/projects/{project_id}/new-feature", response_model=NewFeatureOut)
def create_new_feature(
    project_id: str,
    body: NewFeatureCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    # implementation
```

```python
# 2. Register in fieldos/app.py
from fieldos.routers import new_feature
app.include_router(new_feature.router)
```

### Adding a New Frontend Page

```tsx
// app/project/new-page/page.tsx
"use client";

import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Sidebar } from "@/components/Sidebar";
import { apiFunction } from "@/lib/api";

function NewPage({ projectId }: { projectId: string }) {
  // State, effects, handlers
  return (
    <div className="flex min-h-screen">
      <Sidebar />
      <main className="ml-56 flex-1 p-6">
        {/* Content */}
      </main>
    </div>
  );
}

function NewPageGate() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get("id");
  if (!projectId) return <main>No project selected.</main>;
  return <NewPage projectId={projectId} />;
}

export default function NewPageRoute() {
  return (
    <Suspense fallback={<main>Loading...</main>}>
      <NewPageGate />
    </Suspense>
  );
}
```

```tsx
// Add to components/Sidebar.tsx
const PROJECT_LINKS = [
  // ...
  { href: "/project/new-page", label: "New Page", icon: "🔧" },
];
```

### API Client Pattern

```typescript
// lib/api.ts
export type NewFeature = { id: string; name: string; ... };

export function createNewFeature(projectId: string, data: NewFeatureCreate) {
  return apiFetch<NewFeature>(`/projects/${projectId}/new-feature`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

// For multipart uploads
export async function uploadNewFeaturePhoto(projectId: string, file: File) {
  const form = new FormData();
  form.append("file", file);
  const token = getToken();
  const res = await fetch(`${API_BASE_URL}/projects/${projectId}/new-feature/photos`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  if (!res.ok) throw new Error(`Upload failed: ${res.status}`);
  return res.json();
}
```

### Real-time WebSocket

```typescript
// lib/realtime.ts - useProjectWebSocket hook
const { connected, send } = useProjectWebSocket(projectId, {
  task_update: (msg) => refreshTasks(),
  material_update: (msg) => refreshMaterials(),
  "*": (msg) => console.log("WS:", msg),
});

// Backend broadcast (in routers)
await manager.broadcast(project_id, {
  "type": "task_update",
  "payload": task_data,
}, exclude_user=actor_id);
```

## Database Conventions

### Models
```python
class NewModel(Base):
    __tablename__ = "new_models"
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), index=True)
    name: Mapped[str] = mapped_column(String(200))
    amount: Mapped[Decimal] = mapped_column(Numeric(14, 2))  # Money
    quantity: Mapped[Decimal] = mapped_column(Numeric(14, 3))  # Quantity
    created_at: Mapped[datetime] = mapped_column(DateTime, default=_utcnow)
```

### Schemas
```python
class NewModelCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    amount: Decimal
    quantity: Decimal

class NewModelOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    name: str
    amount: Decimal
    quantity: Decimal
    created_at: datetime
```

### Mobile (Drift) schema changes
- Every `schemaVersion` bump needs an `if (from < N)` step that leaves an upgraded phone with exactly a fresh install's schema. `test/shipped_schema_upgrade_test.dart` checks this from every shipped schema (v9, v14, v32).
- When a release ships with a new `schemaVersion`, add its fixture as `tool/upgrade_fixtures/README.md` describes.
- When a server change would break older app builds, raise the minimum build instead of letting them sync wrongly: `update public.app_config set min_build_android = <build>, min_build_ios = <build>, message = '<short reason>';` (service role, SQL editor). Phones below it stop syncing and show an Update banner on Home; their work stays on the phone (`lib/sync/app_version_gate.dart`). Set it back to 0 to switch it off.

## Repo rules (FieldOS team)
- **No GitHub Actions runs without the owner's OK.** Every workflow is `workflow_dispatch` only (issue #149). Run the checks locally instead: `flutter analyze` and `flutter test` in `fieldos_mobile/`, `deno test` in each `supabase/functions/*`, `pytest`, and the SQL tests in `supabase/tests/` against a local Postgres.
- **Production migrations get one line in issue #132**, never a new issue. Apply them with the `supabase-deploy` workflow (owner's OK), then `isolation-check`.
- **Supabase and RevenueCat setup work is assigned to `bahumanyarg11`** on GitHub.
- **Legal texts have one source:** `website/privacy-policy.html` and `website/terms-of-use.html`. The app's copy (`fieldos_mobile/lib/features/legal/legal_texts.dart`) must say the same; `docs/store/` only points there. Never describe them as lawyer-reviewed.

## Testing Requirements

### Backend
```bash
# Run all
pytest

# With coverage
pytest --cov=fieldos
```

### Frontend
```bash
# Typecheck
npx tsc --noEmit

# Build
npm run build
```

## Documentation Updates

When adding features, update:
1. `docs/API_REFERENCE.md` - New endpoints
2. `docs/DATABASE_SCHEMA.md` - New tables/columns
3. `docs/FRONTEND_ARCHITECTURE.md` - New patterns
4. `docs/MOBILE_GUIDE.md` - Mobile considerations

## Forbidden Patterns

- ❌ Float for money/quantities
- ❌ JWT tokens (use sessions)
- ❌ Global mutable state
- ❌ Raw SQL (use SQLAlchemy ORM)
- ❌ `any` type in TypeScript
- ❌ Missing error handling
- ❌ Hardcoded URLs (use `API_BASE_URL`)

## Required Checks Before Commit

```bash
# Backend
ruff check .
ruff format .
mypy fieldos
pytest

# Frontend
cd frontend
npm run lint
npm run build
```

## File Structure Reference

```
fieldos/
├── fieldos/                 # Backend
│   ├── routers/            # API endpoints
│   ├── models.py           # SQLAlchemy models
│   ├── schemas.py          # Pydantic schemas
│   ├── auth.py             # Authentication
│   ├── permissions.py      # RBAC
│   ├── estimation_calc.py  # BOQ engine
│   ├── sarvam.py           # Voice AI
│   └── app.py              # App factory
├── frontend/               # Frontend
│   ├── app/                # Next.js App Router
│   │   └── project/        # Project-scoped pages
│   ├── components/         # Reusable UI
│   ├── lib/                # API, auth, pdf, realtime
│   ├── public/             # PWA assets
├── fieldos_mobile/         # Native Flutter mobile app (canonical mobile strategy)
├── src-tauri/              # Desktop shell (Rust/Tauri) -- packages the installer
├── importers/              # One-off scripts: real client Excel BOQ -> FieldOS project-export JSON
├── resources/              # Real client source data (gitignored, local-only -- see below)
└── docs/                   # Documentation
```

## Client reference data (`resources/`)

`resources/` holds Protek Consult's actual BOQ/estimation source files for
three real projects. It is gitignored (`.gitignore`: "Real client
project/financial data (BOQ estimates, rates) — local only") and must
never be committed, logged, or quoted with real figures in any file that
gets committed (including this one) -- describe structure, not numbers.

| Project | Files | Sheets | Imported? |
|---|---|---|---|
| Narapally | `NARAPALLY MASONRY ESTIMATION.xlsx`, `NARAPALLY.pdf` | RATE EST, BOQ, SHUTTERING AREA, COMMON AREA BRICK WORK (SFT) | Yes -- `importers/narapally_boq.py` parses the brick-work BOQ (both flats, both wall thicknesses) into a FieldOS project-export JSON, importable via the app's "Import project" button. Reconciles every computed quantity against the sheet's own stated totals; refuses to write output on any mismatch. |
| Thumukunta | `THUMUKUNTA EST.xlsx`, `THUMUKUNTA.pdf` | SLAB/BEAM/COLUMN REINFORCEMENT, STIRRUPS, CONCRETE ESTIMATION, BRICK WORK, PLASTERING, FLOORING, BOQ | Partial -- `importers/brick_and_concrete_boq.py` (a general importer for this sheet-layout convention, not Thumukunta-specific) covers BRICK WORK and CONCRETE ESTIMATION (excavation/PCC/RCC/columns/beams/slabs; over a third of Thumukunta's stated cost), reconciled against both each sheet's own per-category totals and the BOQ abstract's independently-stated RCC/brick-work/earth-filling lines. SLAB/BEAM/COLUMN REINFORCEMENT, STIRRUPS (steel_weight), PLASTERING, FLOORING (area) are NOT covered yet -- different sheet layouts, follow the same file's pattern to extend it. |
| Vidyanagar | `VIDYANAGAR CONCRETE ESTIMATION.xlsx` (DETAILED, ABSTRACT), `VIDYANAGAR STEEL ESTIMATION.xlsx` (BEAMS, SLABS), `VIDYANAGAR.pdf` | -- | **No importer yet.** Split across two workbooks (concrete and steel are separate files, unlike the other two projects). |

`importers/brick_and_concrete_boq.py` is general-purpose, not tied to one
client: it targets any workbook with sheets literally named "BRICK WORK"
and/or "CONCRETE ESTIMATION" laid out per that file's own module docstring
(single sequential column, TOTAL/DEDUCTIONS markers), and takes
`--project-name` as a required CLI argument rather than assuming a
default. Thumukunta's file is just the one real example currently checked
into `resources/` and golden-tested against
(`tests/test_brick_concrete_boq_import.py`). If you're asked to extend
Thumukunta's coverage (reinforcement/stirrups as steel_weight cost heads,
plastering/flooring as area cost heads) or build Vidyanagar's importer,
follow `importers/narapally_boq.py` or
`importers/brick_and_concrete_boq.py`'s pattern exactly: parse, then
reconcile every computed figure against the sheet's own stated
subtotal/total before writing anything -- refuse output on any mismatch
rather than silently shipping a wrong number to a real client's estimate.
Each project's `.pdf` is the companion reference document (open it to
check, don't assume its contents match what this file states, since it
wasn't inspected in detail when this section was written).

## Environment Variables

```bash
# Backend .env (all optional -- sane defaults exist for local/offline use)
DATABASE_URL=sqlite:///./fieldos_dev.db   # dev default; packaged app uses fieldos/paths.py instead
SARVAM_API_KEY=sk_xxx                     # optional -- only voice-to-DPR needs this
STRIPE_SECRET_KEY=sk_live_xxx             # optional -- billing isn't wired to any UI yet
STRIPE_WEBHOOK_SECRET=whsec_xxx

# Frontend .env.local
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
```
Note the frontend env var is `NEXT_PUBLIC_API_BASE_URL`, not
`NEXT_PUBLIC_API_URL` -- every file in `frontend/lib/` reads that exact
name; a typo'd variant here silently falls back to a wrong default.

## Quick Commands

```bash
# Backend (from repo root; api.py is the dev entrypoint)
.venv\Scripts\python.exe -m uvicorn api:app --reload

# Frontend
cd frontend && npm run dev

# Mobile (Flutter)
cd fieldos_mobile && flutter run

# Tests
.venv\Scripts\python.exe -m pytest tests/   # Backend (pytest) -- use the repo's .venv, not a bare `python`
cd frontend && npm test -- --run            # Frontend (vitest)
```