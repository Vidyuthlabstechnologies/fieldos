# Development Guide

## Prerequisites

- Python 3.12+
- Node.js 18+
- SQLite only — there is no PostgreSQL path; `requirements.txt` doesn't
  even declare a Postgres driver. This app is offline-first by design
  (see `docs/DEPLOYMENT.md`), not a client/server product.
- Flutter SDK (for the mobile app, `fieldos_mobile/`) + Android Studio if
  building for Android
- **Always use the repo's `.venv`, not a bare `python`/`pip` on PATH** —
  a global Python install can silently have different package versions
  (or be missing packages entirely) and give you false "it works"
  results. Confirm you're using the right one:
  `.venv\Scripts\python.exe -c "import fastapi; print(fastapi.__file__)"`
  should print a path inside this repo's `.venv`.

## Quick Start

### 1. Backend

```bash
cd C:\Users\varsh\OneDrive\Documents\0002construction

# Create venv (first time only)
python -m venv .venv

# Install deps
.venv\Scripts\python.exe -m pip install -r requirements.txt

# Run server -- api.py is the dev entrypoint (see its own docstring);
# fieldos/app.py exposes a factory function, not an ASGI app instance,
# so don't point uvicorn at it directly.
.venv\Scripts\python.exe -m uvicorn api:app --reload
```

API: http://localhost:8000
Docs: http://localhost:8000/docs

### 2. Frontend

```bash
cd C:\Users\varsh\OneDrive\Documents\0002construction\frontend

# Install deps
npm install

# Dev server
npm run dev

# Build for production (static export)
npm run build
# Output: frontend/out/
```

Frontend: http://localhost:3000

### 3. Mobile (Flutter)

The mobile app is a native Flutter app at `fieldos_mobile/` — a separate
project from `frontend/`, not a wrapper around it. (The old Capacitor wrapper (`frontend/android/`) was removed in November 2026 (issue #155).)

```bash
cd C:\Users\varsh\OneDrive\Documents\0002construction\fieldos_mobile

flutter pub get      # first time only
flutter analyze      # should report "No issues found!"
flutter test         # unit/widget test suite
flutter run          # launch on a connected device/emulator
```

See `docs/MOBILE_GUIDE.md` for the full picture, including an important
caveat: this app currently has no connection to the FastAPI backend at
all — it's a standalone offline app with its own local database.

## Environment Variables

### Backend (.env)

```bash
# Optional: Sarvam AI for voice DPR
SARVAM_API_KEY=sk_xxx

# Optional: Stripe billing
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
FRONTEND_URL=http://localhost:3000

# Database (default: SQLite file fieldos_dev.db -- this is the only
# supported database; there is no PostgreSQL driver in requirements.txt)
DATABASE_URL=sqlite:///fieldos_dev.db
```

### Frontend (.env.local)

```bash
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
```
This exact variable name matters — every file under `frontend/lib/` reads
`NEXT_PUBLIC_API_BASE_URL`. A differently-named variable (e.g.
`NEXT_PUBLIC_API_URL`) will silently be ignored and the app will fall back
to whatever hardcoded default that call site has.

## Database

### Migrations (Alembic)

The Alembic config file is `alembic.ini` at the **repo root** (not inside
`fieldos/`), and it points at migrations under `fieldos/alembic/versions/`.
Run these from the repo root, using the `.venv` python directly rather than
relying on shell activation:

```bash
cd C:\Users\varsh\OneDrive\Documents\0002construction

# Create migration
.venv\Scripts\python.exe -m alembic -c alembic.ini revision --autogenerate -m "description"

# Apply migrations
.venv\Scripts\python.exe -m alembic -c alembic.ini upgrade head
```

`fieldos/alembic/env.py` already imports `fieldos.models` and sets
`target_metadata = Base.metadata`, so autogenerate correctly detects new
tables/columns against everything defined in `fieldos/models.py` — but
always read the generated migration file before committing it; autogenerate
sometimes produces noisy false-positive FK-recreate diffs on unrelated
tables (a SQLite/Alembic batch-mode quirk) that should be pruned by hand.

### Models

See [DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md) for complete schema.

## API Conventions

### Authentication

- Session-based (Bearer token in Authorization header)
- Token from `/auth/login` or `/auth/register`
- 30-day TTL

### Error Format

```json
{
  "detail": "Error message"
}
```

### Pagination

Not yet implemented - all list endpoints return full results.

## Adding New Features

### 1. Backend Router

```python
# fieldos/routers/new_feature.py
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
    # ... implementation
```

### 2. Register Router

```python
# fieldos/app.py
from fieldos.routers import new_feature

app.include_router(new_feature.router)
```

### 3. Frontend API Client

```typescript
// frontend/lib/api.ts
export type NewFeature = { ... };

export function createNewFeature(projectId: string, data: NewFeatureCreate) {
  return apiFetch<NewFeature>(`/projects/${projectId}/new-feature`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}
```

### 4. Frontend Page

```tsx
// frontend/app/project/new-feature/page.tsx
"use client";
// ... component with MobileMenuButton, Sidebar
```

### 5. Add to Sidebar

```typescript
// frontend/components/Sidebar.tsx -- PROJECT_LINKS array, icons are plain
// Unicode glyphs (▣ ▲ ⚒ ⚙ ≡ ◆ ✓) matching the existing entries, not emoji
const PROJECT_LINKS = [
  // ...
  { href: "/project/new-feature", label: "New Feature", icon: "●" },
];
```

## Code Style

### Python

- Type hints required
- SQLAlchemy 2.0 style (Mapped, mapped_column)
- Decimal for money/quantities (never float)
- Pydantic v2 schemas

### TypeScript

- Strict mode
- Functional components with hooks
- Tailwind CSS for styling
- "use client" for interactive pages

## Testing

```bash
# Backend
cd C:\Users\varsh\OneDrive\Documents\0002construction
.venv\Scripts\python.exe -m pytest tests/

# Frontend
cd C:\Users\varsh\OneDrive\Documents\0002construction\frontend
npm test
```

## Common Commands

There is currently no linter, formatter, or type-checker configured for
either side of this project — no `ruff`/`mypy` config or installed package
for Python, no ESLint config for the frontend (`npx tsc --noEmit` for a
plain TypeScript compile check does work, since a `tsconfig.json` exists,
but nothing runs it automatically). If you want to add one, check it's
actually installed and configured before documenting it here — this
section previously listed five commands that would all fail immediately
on a clean checkout.

## Troubleshooting

### Backend won't start
- Check `.venv` is activated
- Verify `DATABASE_URL` in `.env`
- Run migrations: `alembic upgrade head`

### Frontend build fails
- Clear `.next` cache: `rm -rf .next`
- Reinstall: `rm -rf node_modules package-lock.json && npm install`

### Mobile app issues
- `cd fieldos_mobile && flutter clean && flutter pub get` for a clean slate
- If you touched `lib/data/tables.dart`, regenerate drift's generated code:
  `dart run build_runner build --delete-conflicting-outputs`

### WebSocket connection fails
- Ensure backend has `realtime.router` registered
- Check token in query param
- Verify CORS origins in `app.py`

## Portability (Export/Import)

```bash
# Export project (via API)
GET /projects/{id}/export

# Import project (via API)
POST /companies/{company_id}/import
```

Moves all project data between installations (user IDs remapped to importer).