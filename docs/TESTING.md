# Testing Guide

## Overview

| Layer | Framework | Real count (21 Aug 2026) |
|-------|-----------|---------------------------|
| Backend | pytest | 161 passing (0 failing) |
| Frontend | Vitest + React Testing Library | 19 passing (0 failing) |
| Mobile (Flutter) | `flutter test` | 27 passing (0 failing) |
| Frontend E2E | none set up | — |
| CI/CD | none set up | — |

All three suites are automated and green on a clean checkout. There's no
CI pipeline running them automatically yet — see "CI/CD" at the bottom for
what that would take, not what exists today.

## Backend Testing

### Run tests

```bash
cd C:\Users\varsh\OneDrive\Documents\0002construction

# All tests
.venv\Scripts\python.exe -m pytest tests/

# Verbose, one specific file
.venv\Scripts\python.exe -m pytest tests/fieldos/test_estimation_calc.py -v
```

Always run through `.venv`, not a bare `python` — a differently-versioned
global install can silently skip or misreport tests. There's no
`pytest-cov`/coverage tooling configured; `--cov` will just fail.

### Real test file list (`tests/`, `tests/fieldos/`)

```
tests/
├── test_narapally_boq_import.py     # real client BOQ spreadsheet import + reconciliation
└── fieldos/
    ├── conftest.py                  # db_session + build_client fixtures (see below)
    ├── test_app_integration.py      # confirms every router is actually mounted
    ├── test_auth.py, test_auth_api.py
    ├── test_billing_api.py
    ├── test_companies_api.py
    ├── test_dashboard_api.py
    ├── test_db.py
    ├── test_desktop_app.py
    ├── test_documents_api.py
    ├── test_dpr_api.py
    ├── test_equipment_api.py
    ├── test_estimation_api.py, test_estimation_boq_rollup.py, test_estimation_calc.py
    ├── test_inspections_api.py
    ├── test_issues_api.py
    ├── test_materials_api.py
    ├── test_models_company.py, test_models_dpr.py, test_models_estimation.py,
    │   test_models_project.py, test_models_task.py
    ├── test_paths.py
    ├── test_permissions.py
    ├── test_portability.py
    ├── test_procurement_api.py
    ├── test_projects_api.py
    ├── test_realtime_api.py         # WebSocket, via TestClient.websocket_connect
    ├── test_sarvam.py
    ├── test_settings_api.py
    ├── test_tasks_api.py
    └── test_workers_api.py
```

### The real fixtures (`tests/fieldos/conftest.py`)

```python
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import fieldos.models  # noqa: F401  ensures all models are registered on Base.metadata
from fieldos.db import Base


@pytest.fixture()
def db_session():
    # StaticPool is required here: FastAPI's TestClient runs sync endpoints in a
    # worker thread, and without a shared connection, SQLite's `:memory:` DB would
    # be a fresh empty database per thread/connection ("no such table: ..." errors).
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(engine)


from fastapi.testclient import TestClient
from fieldos.app import create_fieldos_app
from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db


def build_client(db_session, user_id="test-user-1"):
    app = create_fieldos_app()

    def override_get_db():
        yield db_session

    def override_get_current_user():
        return CurrentUser(id=user_id, username=user_id)

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user
    return TestClient(app)
```

`build_client` stubs `get_current_user` to a fixed identity — no real
register/login flow needed for most tests. The exceptions are tests that
need a **real** session token (auth flow tests, and the WebSocket route,
which authenticates via a raw DB session-token lookup rather than the
`get_current_user` dependency): those use `build_real_auth_client` from
`tests/fieldos/test_auth_api.py` instead, which only overrides `get_db`.

### The actual test pattern in use

```python
# tests/fieldos/test_issues_api.py -- representative of the whole suite
from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_only_owner_or_pm_can_resolve_an_issue(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    issue = owner_client.post(
        f"/projects/{project['id']}/issues", json={"description": "Blocked access road"}
    ).json()

    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.add(ProjectMember(project_id=project["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()
    engineer_client = build_client(db_session, user_id="engineer-1")

    denied = engineer_client.patch(f"/projects/{project['id']}/issues/{issue['id']}/resolve")
    assert denied.status_code == 403

    allowed = owner_client.patch(f"/projects/{project['id']}/issues/{issue['id']}/resolve")
    assert allowed.status_code == 200
```

**One gotcha worth knowing**: `POST /companies` already auto-assigns the
creating user as `owner` (see `fieldos/routers/companies.py`), and
`require_project_access` grants any company owner access automatically —
so don't manually insert a `CompanyMember`/`ProjectMember` row for the
user who *created* the company/project, only for a second, different-role
user you're adding to the test. Doing it for the creator hits a real
`UNIQUE constraint failed` (this bit a batch of new test files during
development — see git history around 21 Aug 2026 if you want the story).

### File-upload endpoints: query params, not form fields

`documents.py`, `materials.py`, and `inspections.py`'s photo/document
upload endpoints take `category`/`caption`/`notes` as plain `str`
parameters alongside an `UploadFile` — FastAPI treats those as **query
parameters**, not multipart form fields, since they aren't wrapped in
`Form(...)`. The real frontend (`frontend/lib/api.ts`) already calls them
this way. In tests, that means:

```python
# CORRECT -- category/caption go in the URL, not `data=`
client.post(
    f"/projects/{project_id}/documents?category=drawing",
    files={"file": ("plan.pdf", b"...", "application/pdf")},
)

# WRONG -- data={"category": ...} is silently ignored; category falls
# back to its default and the assertion on it will fail
client.post(
    f"/projects/{project_id}/documents",
    files={"file": ("plan.pdf", b"...", "application/pdf")},
    data={"category": "drawing"},
)
```

### Decimal/Numeric fields render at their column's declared scale

`Numeric(precision, scale)` columns serialize to the exact scale declared
in `fieldos/models.py`, not however many digits you typed in the request.
`quantity` on `MaterialEntry` is `Numeric(14, 3)` — send `"50"`, get back
`"50.000"`. Check the model before asserting an exact string.

## Frontend Testing

Vitest + React Testing Library (`frontend/vitest.config.ts`, real and
working — this is not Jest, despite what an earlier draft of this file
claimed).

```bash
cd frontend
npm test              # runs `vitest run` once
```

Existing component/lib tests: `BOQTable`, `CostHeadForm`, `DashboardWidget`,
`DPRForm`, `MeasurementEntryForm`, `NewProjectForm`, `ProjectCard`,
`SteelEntryForm`, `TaskList`, `lib/api.ts`, `app/login/page.tsx`.

**Known gap**: none of the 6 newer pages (`documents`, `equipment`,
`inspections`, `materials`, `procurement`, `workers`), `Sidebar.tsx`,
`lib/pdf.ts`, or `lib/realtime.ts` have any test coverage yet. This is real,
not an oversight to paper over — worth closing in a future session.

## Mobile Testing (Flutter)

```bash
cd fieldos_mobile
flutter test
```

This is a real, automated suite (27 tests as of 21 Aug 2026) — not a manual
device checklist. It covers: offline auth (register → login → session
resolution, duplicate-username rejection), labour geofencing math, the
full procurement chain (RFQ → PO → GRN), the estimation → BOQ → actuals →
dashboard pipeline (including an overrun-status test), subcontractor CRUD,
and Sarvam response parsing.

For actual device/emulator manual verification (camera, GPS, real voice
recording — things a unit test can't exercise), see
[docs/MOBILE_GUIDE.md](MOBILE_GUIDE.md).

## CI/CD Pipeline

**Doesn't exist yet.** No `.github/workflows/` directory, no automated run
on push/PR. All three suites above are run manually by whoever's making the
change. If you're setting this up, a reasonable starting point:

```yaml
# .github/workflows/test.yml -- NOT YET CREATED, sketch only
name: Test
on: [push, pull_request]
jobs:
  backend:
    runs-on: windows-latest   # match the real dev/target platform
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install -r requirements.txt
      - run: python -m pytest tests/

  frontend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "20" }
      - run: cd frontend && npm ci
      - run: cd frontend && npm test
      - run: cd frontend && npm run build

  mobile:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: cd fieldos_mobile && flutter pub get
      - run: cd fieldos_mobile && flutter analyze
      - run: cd fieldos_mobile && flutter test
```

## Manual QA Checklist

Before each release, on the actual packaged installer (not just `npm run
dev`/`uvicorn --reload`):

- [ ] Register/Login flow
- [ ] Create company + project
- [ ] Dashboard: tasks, DPR (voice + manual), feed
- [ ] Materials: add entry, upload photo, summary
- [ ] Equipment: add, change status, log usage/maintenance/fuel
- [ ] Procurement: vendor → requisition → RFQ → quote → PO → GRN
- [ ] Inspections: create, checklist, photos, complete (pass/fail/conditional)
- [ ] Documents: upload, version increment, category filter
- [ ] Workers: add/edit/deactivate (owner/PM only), daily attendance
- [ ] Estimations: BOQ with volume/area/steel, reconciliation against a real source spreadsheet
- [ ] Settings: Sarvam key, project export/import
- [ ] Mobile (Flutter): install, register, and exercise the same feature set standalone (remember: it does not sync with the desktop app's data — see docs/MOBILE_GUIDE.md)
- [ ] Full installer re-verification: install the packaged `.exe`/`.msi` fresh and confirm the new migration + all 8 newer routers work against a real, freshly-provisioned database (this has NOT been re-verified since the materials/workers/documents/procurement/equipment/inspections/realtime/billing routers and their migration landed — see project history)
