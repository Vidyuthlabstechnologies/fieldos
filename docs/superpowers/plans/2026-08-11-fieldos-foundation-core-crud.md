# FieldOS Foundation — Core CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working, deployable FieldOS web app covering authentication, multi-tenant companies, projects, tasks, manual Daily Progress Report (DPR) entries with photos, issues, a site activity feed, and a basic dashboard — the online-only, typed-input foundation that the voice/agent flow (Plan 2) and offline sync (Plan 3) will layer on top of later.

**Architecture:** One FastAPI service (extends the existing `api.py`) with SQLAlchemy 2.0 models. Unit tests run against an in-memory SQLite database for speed and zero external dependencies; Alembic migrates the same models onto Supabase Postgres for real deployments. Supabase Auth issues JWTs; the backend verifies them server-side via the Supabase client (no manual JWT-signature handling). The Next.js frontend consumes this API and uploads DPR photos directly to Supabase Storage, then registers the resulting URL with the backend.

**Tech Stack:** Python 3.11+, FastAPI, SQLAlchemy 2.0, Alembic, pytest, httpx, `supabase-py`, pydantic-settings — Supabase (Postgres + Auth + Storage) — Next.js 14 (App Router), TypeScript, Tailwind CSS, Vitest + React Testing Library.

**Testing note:** Backend business logic (models, permissions, every endpoint) is TDD'd against SQLite in-memory — no Docker/Postgres needed to run the test suite. Frontend components get real Vitest/RTL tests for logic-bearing code (the API client, forms, permission-sensitive rendering); presentational pieces are verified by a manual smoke-test pass in Task 20, called out explicitly rather than skipped silently.

---

## File Structure

**Backend (new):**
- `requirements.txt` — Python dependencies
- `.env.example` — required backend env vars
- `fieldos/__init__.py`
- `fieldos/config.py` — `Settings` (env-driven)
- `fieldos/db.py` — SQLAlchemy engine/session/`Base`
- `fieldos/models.py` — all ORM models
- `fieldos/permissions.py` — role/company/project access checks
- `fieldos/auth.py` — Supabase JWT verification, `get_current_user` dependency
- `fieldos/schemas.py` — Pydantic request/response models
- `fieldos/app.py` — assembles a standalone FieldOS `FastAPI` app (used by tests and importable for local running)
- `fieldos/routers/__init__.py`
- `fieldos/routers/companies.py`
- `fieldos/routers/projects.py`
- `fieldos/routers/tasks.py`
- `fieldos/routers/dpr.py`
- `fieldos/routers/issues.py`
- `fieldos/routers/dashboard.py`
- `fieldos/alembic/` — migration environment + versions
- `alembic.ini`

**Backend (modified):**
- `api.py` — mount the FieldOS routers onto the existing RAG `app`

**Backend tests (new):**
- `tests/fieldos/__init__.py`
- `tests/fieldos/conftest.py`
- `tests/fieldos/test_db.py`
- `tests/fieldos/test_models_company.py`
- `tests/fieldos/test_models_project.py`
- `tests/fieldos/test_permissions.py`
- `tests/fieldos/test_models_task.py`
- `tests/fieldos/test_models_dpr.py`
- `tests/fieldos/test_auth.py`
- `tests/fieldos/test_companies_api.py`
- `tests/fieldos/test_projects_api.py`
- `tests/fieldos/test_tasks_api.py`
- `tests/fieldos/test_dpr_api.py`
- `tests/fieldos/test_issues_api.py`
- `tests/fieldos/test_dashboard_api.py`
- `tests/fieldos/test_app_integration.py`

**Frontend (new):**
- `frontend/package.json`, `tsconfig.json`, `next.config.mjs`, `tailwind.config.ts`, `postcss.config.js`, `vitest.config.ts`, `vitest.setup.ts`, `.env.local.example`
- `frontend/app/layout.tsx`, `frontend/app/globals.css`, `frontend/app/page.tsx`
- `frontend/lib/supabaseClient.ts`
- `frontend/lib/api.ts` (+ `frontend/lib/api.test.ts`)
- `frontend/app/login/page.tsx` (+ test)
- `frontend/app/projects/page.tsx`, `frontend/components/ProjectCard.tsx` (+ test), `frontend/components/NewProjectForm.tsx` (+ test)
- `frontend/app/projects/[id]/page.tsx`, `frontend/components/TaskList.tsx` (+ test), `frontend/components/DPRForm.tsx` (+ test), `frontend/components/IssueList.tsx`, `frontend/components/SiteFeed.tsx`, `frontend/components/DashboardWidget.tsx` (+ test)

---

## Task 1: Backend scaffold — config, DB session, test infra

**Files:**
- Create: `requirements.txt`
- Create: `.env.example`
- Create: `fieldos/__init__.py`
- Create: `fieldos/config.py`
- Create: `fieldos/db.py`
- Create: `fieldos/models.py` (empty shell — models arrive in later tasks)
- Create: `tests/fieldos/__init__.py`
- Create: `tests/fieldos/conftest.py`
- Test: `tests/fieldos/test_db.py`

This task is infrastructure, not business logic, so there's no meaningful "red" state to force — the verification step is simply confirming the scaffold works end-to-end.

- [ ] **Step 1: Create `requirements.txt`**

```
fastapi>=0.115
uvicorn[standard]>=0.30
sqlalchemy>=2.0
alembic>=1.13
pydantic>=2.7
pydantic-settings>=2.3
supabase>=2.5
pytest>=8.2
httpx>=0.27
python-dotenv>=1.0
```

- [ ] **Step 2: Install dependencies**

Run: `pip install -r requirements.txt`
Expected: all packages install without error.

- [ ] **Step 3: Create `.env.example`**

```
DATABASE_URL=postgresql+psycopg://postgres:postgres@localhost:54322/postgres
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

- [ ] **Step 4: Write `fieldos/__init__.py`**

```python
```

(empty — marks `fieldos` as a package)

- [ ] **Step 5: Write `fieldos/config.py`**

```python
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "sqlite:///./fieldos_dev.db"
    supabase_url: str = ""
    supabase_service_role_key: str = ""

    class Config:
        env_file = ".env"


settings = Settings()
```

- [ ] **Step 6: Write `fieldos/db.py`**

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

from fieldos.config import settings

connect_args = (
    {"check_same_thread": False} if settings.database_url.startswith("sqlite") else {}
)
engine = create_engine(settings.database_url, connect_args=connect_args)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

- [ ] **Step 7: Write `fieldos/models.py` (empty shell)**

```python
from fieldos.db import Base  # noqa: F401  re-exported so `import fieldos.models` registers all tables
```

- [ ] **Step 8: Write `tests/fieldos/__init__.py`**

```python
```

- [ ] **Step 9: Write `tests/fieldos/conftest.py`**

```python
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import fieldos.models  # noqa: F401  ensures all models are registered on Base.metadata
from fieldos.db import Base


@pytest.fixture()
def db_session():
    engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    session = TestingSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(engine)
```

- [ ] **Step 10: Write `tests/fieldos/test_db.py`**

```python
def test_db_session_fixture_provides_a_working_session(db_session):
    assert db_session.is_active
```

- [ ] **Step 11: Run the test**

Run: `pytest tests/fieldos/test_db.py -v`
Expected: PASS

- [ ] **Step 12: Commit**

```bash
git add requirements.txt .env.example fieldos/ tests/fieldos/
git commit -m "chore: scaffold FastAPI config, DB session, and test infra"
```

---

## Task 2: Company & CompanyMember models

**Files:**
- Modify: `fieldos/models.py`
- Test: `tests/fieldos/test_models_company.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_models_company.py
from fieldos.models import Company, CompanyMember


def test_creating_a_company_persists_it(db_session):
    company = Company(name="Bhavya Developers")
    db_session.add(company)
    db_session.commit()

    fetched = db_session.query(Company).filter_by(name="Bhavya Developers").one()
    assert fetched.id == company.id
    assert fetched.created_at is not None


def test_company_member_links_a_user_to_a_company_with_a_role(db_session):
    company = Company(name="Reidus Infra")
    db_session.add(company)
    db_session.flush()

    membership = CompanyMember(company_id=company.id, user_id="user-1", role="owner")
    db_session.add(membership)
    db_session.commit()

    fetched = db_session.query(CompanyMember).filter_by(user_id="user-1").one()
    assert fetched.company_id == company.id
    assert fetched.role == "owner"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_models_company.py -v`
Expected: FAIL with `ImportError: cannot import name 'Company' from 'fieldos.models'`

- [ ] **Step 3: Implement the models**

```python
# fieldos/models.py
import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from fieldos.db import Base


def gen_uuid() -> str:
    return str(uuid.uuid4())


class Company(Base):
    __tablename__ = "companies"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    members: Mapped[list["CompanyMember"]] = relationship(back_populates="company")


class CompanyMember(Base):
    __tablename__ = "company_members"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    company_id: Mapped[str] = mapped_column(String(36), ForeignKey("companies.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(String(64), nullable=False)
    role: Mapped[str] = mapped_column(String(30), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    company: Mapped["Company"] = relationship(back_populates="members")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/fieldos/test_models_company.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add fieldos/models.py tests/fieldos/test_models_company.py
git commit -m "feat: add Company and CompanyMember models"
```

---

## Task 3: Project & ProjectMember models + permissions helper

**Files:**
- Modify: `fieldos/models.py`
- Create: `fieldos/permissions.py`
- Test: `tests/fieldos/test_models_project.py`
- Test: `tests/fieldos/test_permissions.py`

- [ ] **Step 1: Write the failing model test**

```python
# tests/fieldos/test_models_project.py
from datetime import date

from fieldos.models import Company, Project, ProjectMember


def test_creating_a_project_under_a_company(db_session):
    company = Company(name="Cfolios Design & Construction")
    db_session.add(company)
    db_session.flush()

    project = Project(
        company_id=company.id,
        name="Skyline Towers",
        client_name="Acme Developers",
        location_lat=12.9716,
        location_lng=77.5946,
        geofence_radius_m=200,
        start_date=date(2026, 1, 1),
        end_date=date(2026, 12, 31),
        status="planning",
    )
    db_session.add(project)
    db_session.commit()

    fetched = db_session.query(Project).filter_by(name="Skyline Towers").one()
    assert fetched.company_id == company.id
    assert fetched.status == "planning"


def test_project_member_links_a_user_to_a_project_with_a_role(db_session):
    company = Company(name="HEM Engineers")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Transmission Line 4", status="active")
    db_session.add(project)
    db_session.flush()

    member = ProjectMember(project_id=project.id, user_id="user-2", role="site_engineer")
    db_session.add(member)
    db_session.commit()

    fetched = db_session.query(ProjectMember).filter_by(user_id="user-2").one()
    assert fetched.project_id == project.id
    assert fetched.role == "site_engineer"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_models_project.py -v`
Expected: FAIL with `ImportError: cannot import name 'Project' from 'fieldos.models'`

- [ ] **Step 3: Implement the models (append to `fieldos/models.py`)**

```python
from datetime import date  # add to existing datetime import line -> `from datetime import date, datetime`
from sqlalchemy import Date, Float, Integer  # add to existing sqlalchemy import line


class Project(Base):
    __tablename__ = "projects"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    company_id: Mapped[str] = mapped_column(String(36), ForeignKey("companies.id"), nullable=False)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    client_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    location_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    location_lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    geofence_radius_m: Mapped[int | None] = mapped_column(Integer, nullable=True)
    start_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="planning")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class ProjectMember(Base):
    __tablename__ = "project_members"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False)
    user_id: Mapped[str] = mapped_column(String(64), nullable=False)
    role: Mapped[str] = mapped_column(String(30), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
```

Note the two added import lines go at the top of `fieldos/models.py` alongside the existing `datetime` and `sqlalchemy` imports (merge them, don't duplicate the `from datetime import ...` line).

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/fieldos/test_models_project.py -v`
Expected: PASS

- [ ] **Step 5: Write the failing permissions test**

```python
# tests/fieldos/test_permissions.py
import pytest
from fastapi import HTTPException

from fieldos.models import Company, CompanyMember, Project, ProjectMember
from fieldos.permissions import (
    ROLE_OWNER,
    ROLE_PM,
    ROLE_SITE_ENGINEER,
    get_company_role,
    require_company_role,
    require_project_access,
)


def _seed_company_and_project(db_session, owner_id="owner-1"):
    company = Company(name="Dfine Homes")
    db_session.add(company)
    db_session.flush()
    db_session.add(CompanyMember(company_id=company.id, user_id=owner_id, role=ROLE_OWNER))
    project = Project(company_id=company.id, name="Villa 12", status="active")
    db_session.add(project)
    db_session.commit()
    return company, project


def test_get_company_role_returns_none_for_non_member(db_session):
    company, _ = _seed_company_and_project(db_session)
    assert get_company_role(db_session, company.id, "stranger") is None


def test_require_company_role_raises_403_when_role_not_allowed(db_session):
    company, _ = _seed_company_and_project(db_session)
    db_session.add(CompanyMember(company_id=company.id, user_id="engineer-1", role=ROLE_SITE_ENGINEER))
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        require_company_role(db_session, company.id, "engineer-1", {ROLE_OWNER, ROLE_PM})

    assert exc_info.value.status_code == 403


def test_require_project_access_allows_company_owner_without_explicit_membership(db_session):
    company, project = _seed_company_and_project(db_session)
    result = require_project_access(db_session, project.id, "owner-1")
    assert result.id == project.id


def test_require_project_access_denies_non_member_non_owner(db_session):
    company, project = _seed_company_and_project(db_session)
    db_session.add(CompanyMember(company_id=company.id, user_id="pm-1", role=ROLE_PM))
    db_session.commit()

    with pytest.raises(HTTPException) as exc_info:
        require_project_access(db_session, project.id, "pm-1")

    assert exc_info.value.status_code == 403


def test_require_project_access_allows_explicit_project_member(db_session):
    company, project = _seed_company_and_project(db_session)
    db_session.add(CompanyMember(company_id=company.id, user_id="pm-1", role=ROLE_PM))
    db_session.add(ProjectMember(project_id=project.id, user_id="pm-1", role=ROLE_PM))
    db_session.commit()

    result = require_project_access(db_session, project.id, "pm-1")
    assert result.id == project.id


def test_require_project_access_raises_404_for_missing_project(db_session):
    with pytest.raises(HTTPException) as exc_info:
        require_project_access(db_session, "does-not-exist", "owner-1")
    assert exc_info.value.status_code == 404
```

- [ ] **Step 6: Run test to verify it fails**

Run: `pytest tests/fieldos/test_permissions.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'fieldos.permissions'`

- [ ] **Step 7: Implement `fieldos/permissions.py`**

```python
from fastapi import HTTPException
from sqlalchemy.orm import Session

from fieldos.models import CompanyMember, Project, ProjectMember

ROLE_OWNER = "owner"
ROLE_PM = "project_manager"
ROLE_SITE_ENGINEER = "site_engineer"


def get_company_role(db: Session, company_id: str, user_id: str) -> str | None:
    member = (
        db.query(CompanyMember)
        .filter(CompanyMember.company_id == company_id, CompanyMember.user_id == user_id)
        .first()
    )
    return member.role if member else None


def require_company_role(db: Session, company_id: str, user_id: str, allowed: set[str]) -> str:
    role = get_company_role(db, company_id, user_id)
    if role is None or role not in allowed:
        raise HTTPException(status_code=403, detail="Not authorized for this company")
    return role


def get_project_or_404(db: Session, project_id: str) -> Project:
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project


def require_project_access(db: Session, project_id: str, user_id: str) -> Project:
    project = get_project_or_404(db, project_id)
    company_role = get_company_role(db, project.company_id, user_id)
    if company_role == ROLE_OWNER:
        return project
    is_member = (
        db.query(ProjectMember)
        .filter(ProjectMember.project_id == project_id, ProjectMember.user_id == user_id)
        .first()
    )
    if not is_member:
        raise HTTPException(status_code=403, detail="Not a member of this project")
    return project
```

- [ ] **Step 8: Run test to verify it passes**

Run: `pytest tests/fieldos/test_permissions.py -v`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add fieldos/models.py fieldos/permissions.py tests/fieldos/test_models_project.py tests/fieldos/test_permissions.py
git commit -m "feat: add Project/ProjectMember models and permission helpers"
```

---

## Task 4: Task model

**Files:**
- Modify: `fieldos/models.py`
- Test: `tests/fieldos/test_models_task.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_models_task.py
from datetime import date

from fieldos.models import Company, Project, Task


def test_creating_a_task_defaults_to_todo_status(db_session):
    company = Company(name="Shivam Developers")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Highway Segment 7", status="active")
    db_session.add(project)
    db_session.flush()

    task = Task(project_id=project.id, title="Pour footing F12", due_date=date(2026, 9, 1))
    db_session.add(task)
    db_session.commit()

    fetched = db_session.query(Task).filter_by(title="Pour footing F12").one()
    assert fetched.status == "todo"
    assert fetched.assignee_id is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_models_task.py -v`
Expected: FAIL with `ImportError: cannot import name 'Task' from 'fieldos.models'`

- [ ] **Step 3: Implement the model (append to `fieldos/models.py`)**

```python
class Task(Base):
    __tablename__ = "tasks"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    assignee_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="todo")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow
    )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/fieldos/test_models_task.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add fieldos/models.py tests/fieldos/test_models_task.py
git commit -m "feat: add Task model"
```

---

## Task 5: DPREntry, DPRPhoto, and Issue models

**Files:**
- Modify: `fieldos/models.py`
- Test: `tests/fieldos/test_models_dpr.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_models_dpr.py
from datetime import date

from fieldos.models import Company, DPREntry, DPRPhoto, Issue, Project


def _seed_project(db_session):
    company = Company(name="Onsite AI Test Co")
    db_session.add(company)
    db_session.flush()
    project = Project(company_id=company.id, name="Test Site", status="active")
    db_session.add(project)
    db_session.commit()
    return project


def test_dpr_entry_defaults_to_confirmed_manual(db_session):
    project = _seed_project(db_session)
    entry = DPREntry(
        project_id=project.id,
        created_by="engineer-1",
        entry_date=date(2026, 8, 11),
        work_summary="Poured 50 cum concrete on footing F12",
        manpower_count=8,
    )
    db_session.add(entry)
    db_session.commit()

    fetched = db_session.query(DPREntry).one()
    assert fetched.status == "confirmed"
    assert fetched.source == "manual"


def test_dpr_photo_links_to_a_dpr_entry(db_session):
    project = _seed_project(db_session)
    entry = DPREntry(
        project_id=project.id,
        created_by="engineer-1",
        entry_date=date(2026, 8, 11),
        work_summary="Steel fixing at column C4",
        manpower_count=5,
    )
    db_session.add(entry)
    db_session.flush()

    photo = DPRPhoto(dpr_entry_id=entry.id, photo_url="https://example.com/photo.jpg")
    db_session.add(photo)
    db_session.commit()

    fetched = db_session.query(DPRPhoto).one()
    assert fetched.dpr_entry_id == entry.id


def test_issue_defaults_to_open_medium_severity(db_session):
    project = _seed_project(db_session)
    issue = Issue(project_id=project.id, description="Cement delivery delayed by 2 days")
    db_session.add(issue)
    db_session.commit()

    fetched = db_session.query(Issue).one()
    assert fetched.status == "open"
    assert fetched.severity == "medium"
    assert fetched.resolved_at is None
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_models_dpr.py -v`
Expected: FAIL with `ImportError: cannot import name 'DPREntry' from 'fieldos.models'`

- [ ] **Step 3: Implement the models (append to `fieldos/models.py`)**

```python
from sqlalchemy import Text  # add to existing sqlalchemy import line


class DPREntry(Base):
    __tablename__ = "dpr_entries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False)
    created_by: Mapped[str] = mapped_column(String(64), nullable=False)
    entry_date: Mapped[date] = mapped_column(Date, nullable=False)
    work_summary: Mapped[str] = mapped_column(Text, nullable=False)
    manpower_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    weather: Mapped[str | None] = mapped_column(String(50), nullable=True)
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="confirmed")
    source: Mapped[str] = mapped_column(String(20), nullable=False, default="manual")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class DPRPhoto(Base):
    __tablename__ = "dpr_photos"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    dpr_entry_id: Mapped[str] = mapped_column(String(36), ForeignKey("dpr_entries.id"), nullable=False)
    photo_url: Mapped[str] = mapped_column(String(500), nullable=False)
    caption: Mapped[str | None] = mapped_column(String(200), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)


class Issue(Base):
    __tablename__ = "issues"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=gen_uuid)
    project_id: Mapped[str] = mapped_column(String(36), ForeignKey("projects.id"), nullable=False)
    dpr_entry_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("dpr_entries.id"), nullable=True
    )
    description: Mapped[str] = mapped_column(Text, nullable=False)
    severity: Mapped[str] = mapped_column(String(20), nullable=False, default="medium")
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="open")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    resolved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/fieldos/test_models_dpr.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add fieldos/models.py tests/fieldos/test_models_dpr.py
git commit -m "feat: add DPREntry, DPRPhoto, and Issue models"
```

---

## Task 6: Auth — Supabase token verification

**Files:**
- Create: `fieldos/auth.py`
- Test: `tests/fieldos/test_auth.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_auth.py
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from fieldos.auth import verify_token


class FakeAuth:
    def __init__(self, user):
        self._user = user

    def get_user(self, token):
        if token == "valid-token":
            return SimpleNamespace(user=self._user)
        return SimpleNamespace(user=None)


class FakeSupabase:
    def __init__(self, user):
        self.auth = FakeAuth(user)


def test_verify_token_returns_current_user_for_valid_token():
    fake_user = SimpleNamespace(id="user-123", email="pm@site.com", phone=None)
    supabase = FakeSupabase(fake_user)

    current_user = verify_token("valid-token", supabase)

    assert current_user.id == "user-123"
    assert current_user.email == "pm@site.com"


def test_verify_token_raises_401_for_invalid_token():
    supabase = FakeSupabase(user=None)

    with pytest.raises(HTTPException) as exc_info:
        verify_token("bad-token", supabase)

    assert exc_info.value.status_code == 401
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_auth.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'fieldos.auth'`

- [ ] **Step 3: Implement `fieldos/auth.py`**

```python
from fastapi import Depends, Header, HTTPException
from supabase import Client, create_client

from fieldos.config import settings


def get_supabase_admin() -> Client:
    return create_client(settings.supabase_url, settings.supabase_service_role_key)


class CurrentUser:
    def __init__(self, id: str, email: str | None, phone: str | None):
        self.id = id
        self.email = email
        self.phone = phone


def verify_token(token: str, supabase) -> CurrentUser:
    resp = supabase.auth.get_user(token)
    if resp is None or resp.user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    u = resp.user
    return CurrentUser(id=u.id, email=u.email, phone=u.phone)


def get_current_user(
    authorization: str | None = Header(default=None),
    supabase: Client = Depends(get_supabase_admin),
) -> CurrentUser:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    return verify_token(token, supabase)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/fieldos/test_auth.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add fieldos/auth.py tests/fieldos/test_auth.py
git commit -m "feat: verify Supabase auth tokens and expose get_current_user dependency"
```

---

## Task 7: FieldOS app shell + Companies API

**Files:**
- Create: `fieldos/schemas.py`
- Create: `fieldos/routers/__init__.py`
- Create: `fieldos/routers/companies.py`
- Create: `fieldos/app.py`
- Modify: `tests/fieldos/conftest.py` (add `build_client` helper)
- Test: `tests/fieldos/test_companies_api.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_companies_api.py
from tests.fieldos.conftest import build_client


def test_create_company_makes_creator_the_owner(db_session):
    client = build_client(db_session, user_id="owner-1")

    response = client.post("/companies", json={"name": "Bhavya Developers"})

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Bhavya Developers"

    from fieldos.models import CompanyMember

    membership = db_session.query(CompanyMember).filter_by(company_id=body["id"]).one()
    assert membership.user_id == "owner-1"
    assert membership.role == "owner"


def test_list_my_companies_returns_only_companies_the_user_belongs_to(db_session):
    client_a = build_client(db_session, user_id="owner-a")
    client_b = build_client(db_session, user_id="owner-b")

    client_a.post("/companies", json={"name": "Company A"})
    client_b.post("/companies", json={"name": "Company B"})

    response = client_a.get("/companies/mine")

    assert response.status_code == 200
    names = [c["name"] for c in response.json()]
    assert names == ["Company A"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_companies_api.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'fieldos.app'`

- [ ] **Step 3: Create `fieldos/schemas.py`**

```python
from datetime import date, datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


# Companies
class CompanyCreate(BaseModel):
    name: str


class CompanyOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    name: str
    created_at: datetime
```

- [ ] **Step 4: Create `fieldos/routers/__init__.py`**

```python
```

- [ ] **Step 5: Create `fieldos/routers/companies.py`**

```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Company, CompanyMember
from fieldos.schemas import CompanyCreate, CompanyOut

router = APIRouter(prefix="/companies", tags=["companies"])


@router.post("", response_model=CompanyOut, status_code=201)
def create_company(
    body: CompanyCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    company = Company(name=body.name)
    db.add(company)
    db.flush()

    db.add(CompanyMember(company_id=company.id, user_id=current_user.id, role="owner"))
    db.commit()
    db.refresh(company)
    return company


@router.get("/mine", response_model=list[CompanyOut])
def list_my_companies(
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    memberships = db.query(CompanyMember).filter(CompanyMember.user_id == current_user.id).all()
    company_ids = [m.company_id for m in memberships]
    if not company_ids:
        return []
    return db.query(Company).filter(Company.id.in_(company_ids)).all()
```

- [ ] **Step 6: Create `fieldos/app.py`**

```python
from fastapi import FastAPI

from fieldos.routers import companies


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.include_router(companies.router)
    return app
```

- [ ] **Step 7: Add `build_client` helper to `tests/fieldos/conftest.py`**

```python
# append to tests/fieldos/conftest.py
from fastapi.testclient import TestClient

from fieldos.app import create_fieldos_app
from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db


def build_client(db_session, user_id="test-user-1"):
    app = create_fieldos_app()

    def override_get_db():
        yield db_session

    def override_get_current_user():
        return CurrentUser(id=user_id, email=f"{user_id}@example.com", phone=None)

    app.dependency_overrides[get_db] = override_get_db
    app.dependency_overrides[get_current_user] = override_get_current_user
    return TestClient(app)
```

- [ ] **Step 8: Run test to verify it passes**

Run: `pytest tests/fieldos/test_companies_api.py -v`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add fieldos/schemas.py fieldos/routers/ fieldos/app.py tests/fieldos/conftest.py tests/fieldos/test_companies_api.py
git commit -m "feat: add FieldOS app shell and Companies API"
```

---

## Task 8: Projects API

**Files:**
- Modify: `fieldos/schemas.py`
- Create: `fieldos/routers/projects.py`
- Modify: `fieldos/app.py`
- Test: `tests/fieldos/test_projects_api.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_projects_api.py
from tests.fieldos.conftest import build_client


def _create_company(client, name="Reidus Infra"):
    return client.post("/companies", json={"name": name}).json()


def test_owner_can_create_a_project(db_session):
    client = build_client(db_session, user_id="owner-1")
    company = _create_company(client)

    response = client.post(
        "/projects",
        json={"company_id": company["id"], "name": "Skyline Towers", "client_name": "Acme"},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Skyline Towers"
    assert body["status"] == "planning"


def test_site_engineer_cannot_create_a_project(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company = _create_company(owner_client)

    from fieldos.models import CompanyMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    engineer_client = build_client(db_session, user_id="engineer-1")
    response = engineer_client.post(
        "/projects", json={"company_id": company["id"], "name": "Should Fail"}
    )

    assert response.status_code == 403


def test_list_projects_scopes_to_company_membership(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company = _create_company(owner_client)
    owner_client.post("/projects", json={"company_id": company["id"], "name": "Project 1"})
    owner_client.post("/projects", json={"company_id": company["id"], "name": "Project 2"})

    response = owner_client.get(f"/projects?company_id={company['id']}")

    assert response.status_code == 200
    assert len(response.json()) == 2


def test_get_project_denies_non_member(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company = _create_company(owner_client)
    project = owner_client.post(
        "/projects", json={"company_id": company["id"], "name": "Private Project"}
    ).json()

    stranger_client = build_client(db_session, user_id="stranger-1")
    response = stranger_client.get(f"/projects/{project['id']}")

    assert response.status_code == 403
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_projects_api.py -v`
Expected: FAIL with 404 (no `/projects` route registered yet)

- [ ] **Step 3: Add Project schemas (append to `fieldos/schemas.py`)**

```python
class ProjectCreate(BaseModel):
    company_id: str
    name: str
    client_name: Optional[str] = None
    location_lat: Optional[float] = None
    location_lng: Optional[float] = None
    geofence_radius_m: Optional[int] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None


class ProjectOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    company_id: str
    name: str
    client_name: Optional[str]
    location_lat: Optional[float]
    location_lng: Optional[float]
    geofence_radius_m: Optional[int]
    start_date: Optional[date]
    end_date: Optional[date]
    status: str
    created_at: datetime


class ProjectMemberAdd(BaseModel):
    user_id: str
    role: str


class ProjectMemberOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    user_id: str
    role: str
```

- [ ] **Step 4: Create `fieldos/routers/projects.py`**

```python
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Project, ProjectMember
from fieldos.permissions import (
    ROLE_OWNER,
    ROLE_PM,
    ROLE_SITE_ENGINEER,
    get_project_or_404,
    require_company_role,
    require_project_access,
)
from fieldos.schemas import ProjectCreate, ProjectMemberAdd, ProjectMemberOut, ProjectOut

router = APIRouter(prefix="/projects", tags=["projects"])


@router.post("", response_model=ProjectOut, status_code=201)
def create_project(
    body: ProjectCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    creator_role = require_company_role(db, body.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    project = Project(
        company_id=body.company_id,
        name=body.name,
        client_name=body.client_name,
        location_lat=body.location_lat,
        location_lng=body.location_lng,
        geofence_radius_m=body.geofence_radius_m,
        start_date=body.start_date,
        end_date=body.end_date,
        status="planning",
    )
    db.add(project)
    db.flush()

    db.add(ProjectMember(project_id=project.id, user_id=current_user.id, role=creator_role))
    db.commit()
    db.refresh(project)
    return project


@router.get("", response_model=list[ProjectOut])
def list_projects(
    company_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    role = require_company_role(
        db, company_id, current_user.id, {ROLE_OWNER, ROLE_PM, ROLE_SITE_ENGINEER}
    )
    query = db.query(Project).filter(Project.company_id == company_id)
    if role != ROLE_OWNER:
        member_project_ids = [
            m.project_id
            for m in db.query(ProjectMember).filter(ProjectMember.user_id == current_user.id).all()
        ]
        query = query.filter(Project.id.in_(member_project_ids))
    return query.all()


@router.get("/{project_id}", response_model=ProjectOut)
def get_project(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return require_project_access(db, project_id, current_user.id)


@router.post("/{project_id}/members", response_model=ProjectMemberOut, status_code=201)
def add_project_member(
    project_id: str,
    body: ProjectMemberAdd,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    member = ProjectMember(project_id=project_id, user_id=body.user_id, role=body.role)
    db.add(member)
    db.commit()
    db.refresh(member)
    return member
```

- [ ] **Step 5: Mount the router in `fieldos/app.py`**

```python
from fastapi import FastAPI

from fieldos.routers import companies, projects


def create_fieldos_app() -> FastAPI:
    app = FastAPI(title="FieldOS")
    app.include_router(companies.router)
    app.include_router(projects.router)
    return app
```

- [ ] **Step 6: Run test to verify it passes**

Run: `pytest tests/fieldos/test_projects_api.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add fieldos/schemas.py fieldos/routers/projects.py fieldos/app.py tests/fieldos/test_projects_api.py
git commit -m "feat: add Projects API with role-based access control"
```

---

## Task 9: Tasks API

**Files:**
- Modify: `fieldos/schemas.py`
- Create: `fieldos/routers/tasks.py`
- Modify: `fieldos/app.py`
- Test: `tests/fieldos/test_tasks_api.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_tasks_api.py
from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_owner_can_create_a_task(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(f"/projects/{project['id']}/tasks", json={"title": "Pour footing F12"})

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "todo"


def test_site_engineer_can_update_task_status_but_not_create(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    task = owner_client.post(f"/projects/{project['id']}/tasks", json={"title": "Steel fixing"}).json()

    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.add(ProjectMember(project_id=project["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    engineer_client = build_client(db_session, user_id="engineer-1")

    create_response = engineer_client.post(
        f"/projects/{project['id']}/tasks", json={"title": "Should fail"}
    )
    assert create_response.status_code == 403

    update_response = engineer_client.patch(
        f"/projects/{project['id']}/tasks/{task['id']}", json={"status": "in_progress"}
    )
    assert update_response.status_code == 200
    assert update_response.json()["status"] == "in_progress"


def test_update_task_status_rejects_invalid_status(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    task = client.post(f"/projects/{project['id']}/tasks", json={"title": "Task"}).json()

    response = client.patch(f"/projects/{project['id']}/tasks/{task['id']}", json={"status": "bogus"})

    assert response.status_code == 422


def test_list_tasks_returns_all_tasks_for_a_project(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    client.post(f"/projects/{project['id']}/tasks", json={"title": "Task 1"})
    client.post(f"/projects/{project['id']}/tasks", json={"title": "Task 2"})

    response = client.get(f"/projects/{project['id']}/tasks")

    assert response.status_code == 200
    assert len(response.json()) == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_tasks_api.py -v`
Expected: FAIL with 404 (no `/projects/{id}/tasks` route yet)

- [ ] **Step 3: Add Task schemas (append to `fieldos/schemas.py`)**

```python
class TaskCreate(BaseModel):
    title: str
    assignee_id: Optional[str] = None
    due_date: Optional[date] = None


class TaskStatusUpdate(BaseModel):
    status: str


class TaskOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    title: str
    assignee_id: Optional[str]
    due_date: Optional[date]
    status: str
    created_at: datetime
    updated_at: datetime
```

- [ ] **Step 4: Create `fieldos/routers/tasks.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Task
from fieldos.permissions import ROLE_OWNER, ROLE_PM, get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import TaskCreate, TaskOut, TaskStatusUpdate

router = APIRouter(prefix="/projects/{project_id}/tasks", tags=["tasks"])

VALID_STATUSES = {"todo", "in_progress", "done", "blocked"}


@router.post("", response_model=TaskOut, status_code=201)
def create_task(
    project_id: str,
    body: TaskCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    task = Task(project_id=project_id, title=body.title, assignee_id=body.assignee_id, due_date=body.due_date)
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@router.get("", response_model=list[TaskOut])
def list_tasks(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(Task).filter(Task.project_id == project_id).order_by(Task.created_at).all()


@router.patch("/{task_id}", response_model=TaskOut)
def update_task_status(
    project_id: str,
    task_id: str,
    body: TaskStatusUpdate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    if body.status not in VALID_STATUSES:
        raise HTTPException(status_code=422, detail=f"status must be one of {sorted(VALID_STATUSES)}")

    task = db.get(Task, task_id)
    if task is None or task.project_id != project_id:
        raise HTTPException(status_code=404, detail="Task not found")

    task.status = body.status
    db.commit()
    db.refresh(task)
    return task
```

- [ ] **Step 5: Mount the router in `fieldos/app.py`**

```python
from fieldos.routers import companies, projects, tasks

# inside create_fieldos_app():
    app.include_router(tasks.router)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `pytest tests/fieldos/test_tasks_api.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add fieldos/schemas.py fieldos/routers/tasks.py fieldos/app.py tests/fieldos/test_tasks_api.py
git commit -m "feat: add Tasks API"
```

---

## Task 10: DPR API (manual entries + photos)

**Files:**
- Modify: `fieldos/schemas.py`
- Create: `fieldos/routers/dpr.py`
- Modify: `fieldos/app.py`
- Test: `tests/fieldos/test_dpr_api.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_dpr_api.py
from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_create_manual_dpr_entry_is_confirmed_immediately(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(
        f"/projects/{project['id']}/dpr",
        json={
            "entry_date": "2026-08-11",
            "work_summary": "Poured 50 cum concrete on footing F12",
            "manpower_count": 8,
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "confirmed"
    assert body["source"] == "manual"


def test_list_dpr_entries_orders_newest_first(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-10", "work_summary": "Day 1", "manpower_count": 5},
    )
    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Day 2", "manpower_count": 6},
    )

    response = client.get(f"/projects/{project['id']}/dpr")

    assert response.status_code == 200
    dates = [e["entry_date"] for e in response.json()]
    assert dates == ["2026-08-11", "2026-08-10"]


def test_add_photo_to_dpr_entry(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    entry = client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Steel fixing", "manpower_count": 4},
    ).json()

    response = client.post(
        f"/projects/{project['id']}/dpr/{entry['id']}/photos",
        json={"photo_url": "https://storage.example.com/photo1.jpg", "caption": "Column C4"},
    )

    assert response.status_code == 201
    assert response.json()["caption"] == "Column C4"


def test_dpr_denies_non_project_member(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    stranger_client = build_client(db_session, user_id="stranger-1")
    response = stranger_client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Should fail", "manpower_count": 1},
    )

    assert response.status_code == 403
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_dpr_api.py -v`
Expected: FAIL with 404 (no `/projects/{id}/dpr` route yet)

- [ ] **Step 3: Add DPR schemas (append to `fieldos/schemas.py`)**

```python
class DPREntryCreate(BaseModel):
    entry_date: date
    work_summary: str
    manpower_count: int = 0
    weather: Optional[str] = None


class DPREntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    created_by: str
    entry_date: date
    work_summary: str
    manpower_count: int
    weather: Optional[str]
    status: str
    source: str
    created_at: datetime


class DPRPhotoCreate(BaseModel):
    photo_url: str
    caption: Optional[str] = None


class DPRPhotoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    dpr_entry_id: str
    photo_url: str
    caption: Optional[str]
    created_at: datetime
```

- [ ] **Step 4: Create `fieldos/routers/dpr.py`**

```python
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import DPREntry, DPRPhoto
from fieldos.permissions import require_project_access
from fieldos.schemas import DPREntryCreate, DPREntryOut, DPRPhotoCreate, DPRPhotoOut

router = APIRouter(prefix="/projects/{project_id}/dpr", tags=["dpr"])


@router.post("", response_model=DPREntryOut, status_code=201)
def create_dpr_entry(
    project_id: str,
    body: DPREntryCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    entry = DPREntry(
        project_id=project_id,
        created_by=current_user.id,
        entry_date=body.entry_date,
        work_summary=body.work_summary,
        manpower_count=body.manpower_count,
        weather=body.weather,
        status="confirmed",
        source="manual",
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.get("", response_model=list[DPREntryOut])
def list_dpr_entries(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return (
        db.query(DPREntry)
        .filter(DPREntry.project_id == project_id)
        .order_by(DPREntry.entry_date.desc())
        .all()
    )


@router.post("/{dpr_id}/photos", response_model=DPRPhotoOut, status_code=201)
def add_dpr_photo(
    project_id: str,
    dpr_id: str,
    body: DPRPhotoCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    entry = db.get(DPREntry, dpr_id)
    if entry is None or entry.project_id != project_id:
        raise HTTPException(status_code=404, detail="DPR entry not found")

    photo = DPRPhoto(dpr_entry_id=dpr_id, photo_url=body.photo_url, caption=body.caption)
    db.add(photo)
    db.commit()
    db.refresh(photo)
    return photo
```

- [ ] **Step 5: Mount the router in `fieldos/app.py`**

```python
from fieldos.routers import companies, dpr, projects, tasks

# inside create_fieldos_app():
    app.include_router(dpr.router)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `pytest tests/fieldos/test_dpr_api.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add fieldos/schemas.py fieldos/routers/dpr.py fieldos/app.py tests/fieldos/test_dpr_api.py
git commit -m "feat: add DPR API for manual entries and photos"
```

---

## Task 11: Issues API

**Files:**
- Modify: `fieldos/schemas.py`
- Create: `fieldos/routers/issues.py`
- Modify: `fieldos/app.py`
- Test: `tests/fieldos/test_issues_api.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_issues_api.py
from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_any_project_member_can_create_an_issue(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.add(ProjectMember(project_id=project["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    engineer_client = build_client(db_session, user_id="engineer-1")
    response = engineer_client.post(
        f"/projects/{project['id']}/issues",
        json={"description": "Cement delivery delayed by 2 days", "severity": "high"},
    )

    assert response.status_code == 201
    assert response.json()["status"] == "open"


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
    assert allowed.json()["status"] == "resolved"


def test_list_issues_for_a_project(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    client.post(f"/projects/{project['id']}/issues", json={"description": "Issue 1"})
    client.post(f"/projects/{project['id']}/issues", json={"description": "Issue 2"})

    response = client.get(f"/projects/{project['id']}/issues")

    assert response.status_code == 200
    assert len(response.json()) == 2
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_issues_api.py -v`
Expected: FAIL with 404 (no `/projects/{id}/issues` route yet)

- [ ] **Step 3: Add Issue schemas (append to `fieldos/schemas.py`)**

```python
class IssueCreate(BaseModel):
    description: str
    severity: str = "medium"
    dpr_entry_id: Optional[str] = None


class IssueOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    project_id: str
    dpr_entry_id: Optional[str]
    description: str
    severity: str
    status: str
    created_at: datetime
    resolved_at: Optional[datetime]
```

- [ ] **Step 4: Create `fieldos/routers/issues.py`**

```python
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Issue
from fieldos.permissions import ROLE_OWNER, ROLE_PM, get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import IssueCreate, IssueOut

router = APIRouter(prefix="/projects/{project_id}/issues", tags=["issues"])


@router.post("", response_model=IssueOut, status_code=201)
def create_issue(
    project_id: str,
    body: IssueCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    issue = Issue(
        project_id=project_id,
        dpr_entry_id=body.dpr_entry_id,
        description=body.description,
        severity=body.severity,
        status="open",
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)
    return issue


@router.get("", response_model=list[IssueOut])
def list_issues(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(Issue).filter(Issue.project_id == project_id).order_by(Issue.created_at.desc()).all()


@router.patch("/{issue_id}/resolve", response_model=IssueOut)
def resolve_issue(
    project_id: str,
    issue_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    issue = db.get(Issue, issue_id)
    if issue is None or issue.project_id != project_id:
        raise HTTPException(status_code=404, detail="Issue not found")

    issue.status = "resolved"
    issue.resolved_at = datetime.utcnow()
    db.commit()
    db.refresh(issue)
    return issue
```

- [ ] **Step 5: Mount the router in `fieldos/app.py`**

```python
from fieldos.routers import companies, dpr, issues, projects, tasks

# inside create_fieldos_app():
    app.include_router(issues.router)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `pytest tests/fieldos/test_issues_api.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add fieldos/schemas.py fieldos/routers/issues.py fieldos/app.py tests/fieldos/test_issues_api.py
git commit -m "feat: add Issues API"
```

---

## Task 12: Dashboard + site feed API

**Files:**
- Modify: `fieldos/schemas.py`
- Create: `fieldos/routers/dashboard.py`
- Modify: `fieldos/app.py`
- Test: `tests/fieldos/test_dashboard_api.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_dashboard_api.py
from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_dashboard_reports_percent_complete_streak_and_open_issues(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    t1 = client.post(f"/projects/{project['id']}/tasks", json={"title": "Task 1"}).json()
    client.post(f"/projects/{project['id']}/tasks", json={"title": "Task 2"})
    client.patch(f"/projects/{project['id']}/tasks/{t1['id']}", json={"status": "done"})

    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-10", "work_summary": "Day 1", "manpower_count": 5},
    )
    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Day 2", "manpower_count": 5},
    )

    client.post(f"/projects/{project['id']}/issues", json={"description": "Open issue"})

    response = client.get(f"/projects/{project['id']}/dashboard")

    assert response.status_code == 200
    body = response.json()
    assert body["percent_tasks_complete"] == 50.0
    assert body["dpr_streak_days"] == 2
    assert body["open_issue_count"] == 1


def test_site_feed_merges_dpr_and_issues_newest_first(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-10", "work_summary": "Day 1 work", "manpower_count": 5},
    )
    client.post(f"/projects/{project['id']}/issues", json={"description": "Cement delay"})

    response = client.get(f"/projects/{project['id']}/feed")

    assert response.status_code == 200
    types = {item["type"] for item in response.json()}
    assert types == {"dpr", "issue"}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_dashboard_api.py -v`
Expected: FAIL with 404 (no `/projects/{id}/dashboard` route yet)

- [ ] **Step 3: Add dashboard/feed schemas (append to `fieldos/schemas.py`)**

```python
class DashboardOut(BaseModel):
    percent_tasks_complete: float
    dpr_streak_days: int
    open_issue_count: int


class FeedItemOut(BaseModel):
    type: str
    id: str
    occurred_at: datetime
    summary: str
```

- [ ] **Step 4: Create `fieldos/routers/dashboard.py`**

```python
from datetime import date, datetime

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import DPREntry, Issue, Task
from fieldos.permissions import require_project_access
from fieldos.schemas import DashboardOut, FeedItemOut

router = APIRouter(prefix="/projects/{project_id}", tags=["dashboard"])


def _consecutive_day_streak(entry_dates: list[date]) -> int:
    if not entry_dates:
        return 0
    unique_dates = sorted(set(entry_dates), reverse=True)
    streak = 1
    for i in range(1, len(unique_dates)):
        if (unique_dates[i - 1] - unique_dates[i]).days == 1:
            streak += 1
        else:
            break
    return streak


@router.get("/dashboard", response_model=DashboardOut)
def get_dashboard(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    tasks = db.query(Task).filter(Task.project_id == project_id).all()
    total_tasks = len(tasks)
    done_tasks = len([t for t in tasks if t.status == "done"])
    percent_complete = round((done_tasks / total_tasks) * 100, 1) if total_tasks else 0.0

    entries = (
        db.query(DPREntry)
        .filter(DPREntry.project_id == project_id, DPREntry.status == "confirmed")
        .all()
    )
    dpr_streak = _consecutive_day_streak([e.entry_date for e in entries])

    open_issues = (
        db.query(Issue).filter(Issue.project_id == project_id, Issue.status == "open").count()
    )

    return DashboardOut(
        percent_tasks_complete=percent_complete,
        dpr_streak_days=dpr_streak,
        open_issue_count=open_issues,
    )


@router.get("/feed", response_model=list[FeedItemOut])
def get_site_feed(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    items: list[FeedItemOut] = []
    for entry in db.query(DPREntry).filter(DPREntry.project_id == project_id).all():
        items.append(
            FeedItemOut(
                type="dpr",
                id=entry.id,
                occurred_at=datetime.combine(entry.entry_date, datetime.min.time()),
                summary=entry.work_summary,
            )
        )
    for issue in db.query(Issue).filter(Issue.project_id == project_id).all():
        items.append(
            FeedItemOut(type="issue", id=issue.id, occurred_at=issue.created_at, summary=issue.description)
        )

    items.sort(key=lambda i: i.occurred_at, reverse=True)
    return items
```

- [ ] **Step 5: Mount the router in `fieldos/app.py`**

```python
from fieldos.routers import companies, dashboard, dpr, issues, projects, tasks

# inside create_fieldos_app():
    app.include_router(dashboard.router)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `pytest tests/fieldos/test_dashboard_api.py -v`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add fieldos/schemas.py fieldos/routers/dashboard.py fieldos/app.py tests/fieldos/test_dashboard_api.py
git commit -m "feat: add project dashboard and site activity feed endpoints"
```

---

## Task 13: Mount FieldOS into the existing RAG service (`api.py`)

**Files:**
- Modify: `api.py`
- Test: `tests/fieldos/test_app_integration.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/fieldos/test_app_integration.py
"""Confirms api.py exposes the FieldOS routes alongside the existing RAG routes,
without needing to load the RAG retriever (which requires GPU/model downloads)."""
import ast
from pathlib import Path


def test_api_py_includes_all_fieldos_routers():
    source = Path("api.py").read_text(encoding="utf-8")
    tree = ast.parse(source)
    include_router_calls = [
        node
        for node in ast.walk(tree)
        if isinstance(node, ast.Call)
        and isinstance(node.func, ast.Attribute)
        and node.func.attr == "include_router"
    ]
    assert len(include_router_calls) >= 5, "expected companies, projects, tasks, dpr, issues, dashboard routers mounted"
```

This test statically inspects `api.py` rather than importing it, because importing `api.py` triggers `advanced_kb.HybridRetriever`, which loads ML models — not appropriate for a fast unit test.

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/fieldos/test_app_integration.py -v`
Expected: FAIL — `api.py` has zero `include_router` calls today

- [ ] **Step 3: Modify `api.py`**

Add these lines after the existing `app.add_middleware(...)` block (around line 32 in the current file, right before `retriever = None`):

```python
from fieldos.routers import companies, dashboard, dpr, issues, projects, tasks

app.include_router(companies.router)
app.include_router(projects.router)
app.include_router(tasks.router)
app.include_router(dpr.router)
app.include_router(issues.router)
app.include_router(dashboard.router)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/fieldos/test_app_integration.py -v`
Expected: PASS

- [ ] **Step 5: Sanity-check the full app still boots**

Run: `python -c "import api"`
Expected: no exceptions (this does import the RAG retriever class definition, but does not call `load_retriever()`, so no models are actually loaded)

- [ ] **Step 6: Commit**

```bash
git add api.py tests/fieldos/test_app_integration.py
git commit -m "feat: mount FieldOS routers into the existing RAG API service"
```

---

## Task 14: Alembic migrations for Supabase Postgres

**Files:**
- Create: `alembic.ini`
- Create: `fieldos/alembic/env.py`
- Create: `fieldos/alembic/script.py.mako`
- Create: `fieldos/alembic/versions/0001_initial_schema.py`

This task has no unit test — its verification step is running the migration against a real Postgres instance (Supabase local dev stack or any Postgres you point `DATABASE_URL` at).

- [ ] **Step 1: Create `alembic.ini`**

```ini
[alembic]
script_location = fieldos/alembic
prepend_sys_path = .
sqlalchemy.url =

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
```

- [ ] **Step 2: Create `fieldos/alembic/env.py`**

```python
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

import fieldos.models  # noqa: F401  registers all models on Base.metadata
from fieldos.config import settings
from fieldos.db import Base

config = context.config
config.set_main_option("sqlalchemy.url", settings.database_url)

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

- [ ] **Step 3: Create `fieldos/alembic/script.py.mako`**

```mako
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}

"""
from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = ${repr(branch_labels)}
depends_on = ${repr(depends_on)}


def upgrade() -> None:
    ${upgrades if upgrades else "pass"}


def downgrade() -> None:
    ${downgrades if downgrades else "pass"}
```

- [ ] **Step 4: Generate the initial migration**

Run (with `DATABASE_URL` pointed at a real Postgres — e.g. `supabase start` for a local dev stack, or your Supabase project's connection string):

```bash
alembic revision --autogenerate -m "initial schema"
```

Expected: a new file appears at `fieldos/alembic/versions/<hash>_initial_schema.py` containing `create_table` calls for all 8 tables (`companies`, `company_members`, `projects`, `project_members`, `tasks`, `dpr_entries`, `dpr_photos`, `issues`).

- [ ] **Step 5: Apply the migration**

Run: `alembic upgrade head`
Expected: no errors; connecting to the Postgres instance and running `\dt` shows all 8 tables.

- [ ] **Step 6: Commit**

```bash
git add alembic.ini fieldos/alembic/
git commit -m "chore: add Alembic migration setup and initial schema migration"
```

---

## Task 15: Frontend scaffold

**Files:**
- Create: `frontend/package.json`, `frontend/tsconfig.json`, `frontend/next.config.mjs`
- Create: `frontend/tailwind.config.ts`, `frontend/postcss.config.js`
- Create: `frontend/vitest.config.ts`, `frontend/vitest.setup.ts`
- Create: `frontend/.env.local.example`
- Create: `frontend/app/layout.tsx`, `frontend/app/globals.css`, `frontend/app/page.tsx`

No business logic here — verification is `npm run dev` booting successfully.

- [ ] **Step 1: Create `frontend/package.json`**

```json
{
  "name": "fieldos-frontend",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "test": "vitest run"
  },
  "dependencies": {
    "next": "^14.2.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "@supabase/supabase-js": "^2.45.0"
  },
  "devDependencies": {
    "typescript": "^5.5.0",
    "@types/node": "^20.14.0",
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "tailwindcss": "^3.4.0",
    "postcss": "^8.4.0",
    "autoprefixer": "^10.4.0",
    "vitest": "^2.0.0",
    "@vitejs/plugin-react": "^4.3.0",
    "@testing-library/react": "^16.0.0",
    "@testing-library/jest-dom": "^6.4.0",
    "jsdom": "^24.1.0"
  }
}
```

- [ ] **Step 2: Install dependencies**

Run: `cd frontend && npm install`
Expected: installs without error.

- [ ] **Step 3: Create `frontend/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "lib": ["dom", "dom.iterable", "esnext"],
    "allowJs": true,
    "skipLibCheck": true,
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "module": "esnext",
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "preserve",
    "incremental": true,
    "baseUrl": ".",
    "paths": { "@/*": ["./*"] },
    "plugins": [{ "name": "next" }]
  },
  "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
  "exclude": ["node_modules"]
}
```

- [ ] **Step 4: Create `frontend/next.config.mjs`**

```js
/** @type {import('next').NextConfig} */
const nextConfig = {};

export default nextConfig;
```

- [ ] **Step 5: Create `frontend/tailwind.config.ts`**

```ts
import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: { extend: {} },
  plugins: [],
};

export default config;
```

- [ ] **Step 6: Create `frontend/postcss.config.js`**

```js
module.exports = {
  plugins: { tailwindcss: {}, autoprefixer: {} },
};
```

- [ ] **Step 7: Create `frontend/vitest.config.ts`**

```ts
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    setupFiles: "./vitest.setup.ts",
  },
});
```

- [ ] **Step 8: Create `frontend/vitest.setup.ts`**

```ts
import "@testing-library/jest-dom/vitest";
```

- [ ] **Step 9: Create `frontend/.env.local.example`**

```
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
```

- [ ] **Step 10: Create `frontend/app/globals.css`**

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

- [ ] **Step 11: Create `frontend/app/layout.tsx`**

```tsx
import "./globals.css";
import type { ReactNode } from "react";

export const metadata = {
  title: "FieldOS",
  description: "Voice-first construction site management",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body className="bg-slate-50 text-slate-900">{children}</body>
    </html>
  );
}
```

- [ ] **Step 12: Create `frontend/app/page.tsx`**

```tsx
import Link from "next/link";

export default function HomePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4">
      <h1 className="text-3xl font-bold">FieldOS</h1>
      <Link href="/login" className="rounded bg-slate-900 px-4 py-2 text-white">
        Sign in
      </Link>
    </main>
  );
}
```

- [ ] **Step 13: Verify the app boots**

Run: `cd frontend && npm run dev` (then visit `http://localhost:3000`)
Expected: page loads showing "FieldOS" and a "Sign in" link. Stop the dev server after confirming.

- [ ] **Step 14: Commit**

```bash
git add frontend/
git commit -m "chore: scaffold Next.js frontend with Tailwind and Vitest"
```

---

## Task 16: Supabase client + typed API wrapper

**Files:**
- Create: `frontend/lib/supabaseClient.ts`
- Create: `frontend/lib/api.ts`
- Test: `frontend/lib/api.test.ts`

- [ ] **Step 1: Create `frontend/lib/supabaseClient.ts`**

```ts
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
```

- [ ] **Step 2: Write the failing test**

```ts
// frontend/lib/api.test.ts
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("./supabaseClient", () => ({
  supabase: { auth: { getSession: vi.fn() } },
}));

import { apiFetch } from "./api";
import { supabase } from "./supabaseClient";

describe("apiFetch", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it("attaches the Supabase access token as a bearer header", async () => {
    (supabase.auth.getSession as any).mockResolvedValue({
      data: { session: { access_token: "test-token" } },
    });
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ ok: true }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch("/projects");

    const [, options] = fetchMock.mock.calls[0];
    expect(options.headers.Authorization).toBe("Bearer test-token");
  });

  it("omits the Authorization header when there is no session", async () => {
    (supabase.auth.getSession as any).mockResolvedValue({ data: { session: null } });
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, json: async () => ({}) });
    vi.stubGlobal("fetch", fetchMock);

    await apiFetch("/projects");

    const [, options] = fetchMock.mock.calls[0];
    expect(options.headers.Authorization).toBeUndefined();
  });

  it("throws when the API responds with a non-2xx status", async () => {
    (supabase.auth.getSession as any).mockResolvedValue({ data: { session: null } });
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 403, text: async () => "forbidden" })
    );

    await expect(apiFetch("/projects")).rejects.toThrow("API error 403");
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd frontend && npm run test -- lib/api.test.ts`
Expected: FAIL — `Cannot find module './api'`

- [ ] **Step 4: Implement `frontend/lib/api.ts`**

```ts
import { supabase } from "./supabaseClient";

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? "http://localhost:8000";

async function authHeader(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

export async function apiFetch<T>(path: string, options: RequestInit = {}): Promise<T> {
  const headers = {
    "Content-Type": "application/json",
    ...(await authHeader()),
    ...(options.headers ?? {}),
  };
  const res = await fetch(`${API_BASE_URL}${path}`, { ...options, headers });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json() as Promise<T>;
}

export type Project = {
  id: string;
  company_id: string;
  name: string;
  client_name: string | null;
  status: string;
};

export function createProject(data: { company_id: string; name: string; client_name?: string }) {
  return apiFetch<Project>("/projects", { method: "POST", body: JSON.stringify(data) });
}

export function listProjects(companyId: string) {
  return apiFetch<Project[]>(`/projects?company_id=${encodeURIComponent(companyId)}`);
}

export function getProject(projectId: string) {
  return apiFetch<Project>(`/projects/${projectId}`);
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd frontend && npm run test -- lib/api.test.ts`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add frontend/lib/
git commit -m "feat: add Supabase client and typed API wrapper"
```

---

## Task 17: Auth pages (login via OTP)

**Files:**
- Create: `frontend/app/login/page.tsx`
- Test: `frontend/app/login/page.test.tsx`

- [ ] **Step 1: Write the failing test**

```tsx
// frontend/app/login/page.test.tsx
import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/supabaseClient", () => ({
  supabase: { auth: { signInWithOtp: vi.fn().mockResolvedValue({ error: null }) } },
}));

import LoginPage from "./page";
import { supabase } from "@/lib/supabaseClient";

describe("LoginPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("sends an OTP to the entered phone number", async () => {
    render(<LoginPage />);

    fireEvent.change(screen.getByLabelText(/phone number/i), {
      target: { value: "+919876543210" },
    });
    fireEvent.click(screen.getByRole("button", { name: /send code/i }));

    expect(supabase.auth.signInWithOtp).toHaveBeenCalledWith({ phone: "+919876543210" });
    expect(await screen.findByText(/code sent/i)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npm run test -- app/login/page.test.tsx`
Expected: FAIL — `Cannot find module './page'`

- [ ] **Step 3: Implement `frontend/app/login/page.tsx`**

```tsx
"use client";

import { useState } from "react";

import { supabase } from "@/lib/supabaseClient";

export default function LoginPage() {
  const [phone, setPhone] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSendCode() {
    setError(null);
    const { error } = await supabase.auth.signInWithOtp({ phone });
    if (error) {
      setError(error.message);
      return;
    }
    setSent(true);
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-4 p-6">
      <h1 className="text-2xl font-bold">Sign in to FieldOS</h1>
      <label className="flex flex-col gap-1 text-sm">
        Phone number
        <input
          type="tel"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          placeholder="+91XXXXXXXXXX"
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <button
        onClick={handleSendCode}
        className="rounded bg-slate-900 px-4 py-2 text-white"
        type="button"
      >
        Send code
      </button>
      {sent && <p className="text-sm text-green-600">Code sent — check your phone.</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}
    </main>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npm run test -- app/login/page.test.tsx`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add frontend/app/login/
git commit -m "feat: add phone OTP login page"
```

---

## Task 18: Projects UI (list + create)

**Files:**
- Create: `frontend/components/ProjectCard.tsx`
- Test: `frontend/components/ProjectCard.test.tsx`
- Create: `frontend/components/NewProjectForm.tsx`
- Test: `frontend/components/NewProjectForm.test.tsx`
- Create: `frontend/app/projects/page.tsx`
- Create: `frontend/app/projects/new/page.tsx`

- [ ] **Step 1: Write the failing ProjectCard test**

```tsx
// frontend/components/ProjectCard.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { ProjectCard } from "./ProjectCard";

describe("ProjectCard", () => {
  it("renders the project name, client, and status", () => {
    render(
      <ProjectCard
        project={{ id: "1", name: "Skyline Towers", client_name: "Acme Developers", status: "active" }}
      />
    );

    expect(screen.getByText("Skyline Towers")).toBeInTheDocument();
    expect(screen.getByText("Acme Developers")).toBeInTheDocument();
    expect(screen.getByText("active")).toBeInTheDocument();
  });

  it("links to the project detail page", () => {
    render(<ProjectCard project={{ id: "42", name: "X", client_name: null, status: "planning" }} />);
    expect(screen.getByRole("link")).toHaveAttribute("href", "/projects/42");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd frontend && npm run test -- components/ProjectCard.test.tsx`
Expected: FAIL — `Cannot find module './ProjectCard'`

- [ ] **Step 3: Implement `frontend/components/ProjectCard.tsx`**

```tsx
type Project = {
  id: string;
  name: string;
  client_name?: string | null;
  status: string;
};

export function ProjectCard({ project }: { project: Project }) {
  return (
    <a
      href={`/projects/${project.id}`}
      className="block rounded-lg border border-slate-200 p-4 hover:border-slate-400"
    >
      <h3 className="font-semibold text-slate-900">{project.name}</h3>
      {project.client_name && <p className="text-sm text-slate-500">{project.client_name}</p>}
      <span className="mt-2 inline-block rounded bg-slate-100 px-2 py-0.5 text-xs uppercase text-slate-600">
        {project.status}
      </span>
    </a>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd frontend && npm run test -- components/ProjectCard.test.tsx`
Expected: PASS

- [ ] **Step 5: Write the failing NewProjectForm test**

```tsx
// frontend/components/NewProjectForm.test.tsx
import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { NewProjectForm } from "./NewProjectForm";

describe("NewProjectForm", () => {
  it("calls onSubmit with the entered name and client", () => {
    const onSubmit = vi.fn();
    render(<NewProjectForm companyId="company-1" onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/project name/i), { target: { value: "Skyline Towers" } });
    fireEvent.change(screen.getByLabelText(/client/i), { target: { value: "Acme" } });
    fireEvent.click(screen.getByRole("button", { name: /create project/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      company_id: "company-1",
      name: "Skyline Towers",
      client_name: "Acme",
    });
  });
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd frontend && npm run test -- components/NewProjectForm.test.tsx`
Expected: FAIL — `Cannot find module './NewProjectForm'`

- [ ] **Step 7: Implement `frontend/components/NewProjectForm.tsx`**

```tsx
"use client";

import { useState } from "react";

type NewProjectData = { company_id: string; name: string; client_name: string };

export function NewProjectForm({
  companyId,
  onSubmit,
}: {
  companyId: string;
  onSubmit: (data: NewProjectData) => void;
}) {
  const [name, setName] = useState("");
  const [clientName, setClientName] = useState("");

  function handleSubmit() {
    onSubmit({ company_id: companyId, name, client_name: clientName });
  }

  return (
    <div className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Project name
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Client
        <input
          value={clientName}
          onChange={(e) => setClientName(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <button onClick={handleSubmit} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
        Create project
      </button>
    </div>
  );
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `cd frontend && npm run test -- components/NewProjectForm.test.tsx`
Expected: PASS

- [ ] **Step 9: Wire up the pages (no new tests — thin composition of already-tested pieces)**

```tsx
// frontend/app/projects/page.tsx
"use client";

import { useEffect, useState } from "react";

import { ProjectCard } from "@/components/ProjectCard";
import { listProjects, type Project } from "@/lib/api";

const DEMO_COMPANY_ID = process.env.NEXT_PUBLIC_DEMO_COMPANY_ID ?? "";

export default function ProjectsPage() {
  const [projects, setProjects] = useState<Project[]>([]);

  useEffect(() => {
    listProjects(DEMO_COMPANY_ID).then(setProjects).catch(console.error);
  }, []);

  return (
    <main className="mx-auto max-w-3xl p-6">
      <div className="mb-4 flex items-center justify-between">
        <h1 className="text-2xl font-bold">Projects</h1>
        <a href="/projects/new" className="rounded bg-slate-900 px-4 py-2 text-white">
          New project
        </a>
      </div>
      <div className="grid gap-3">
        {projects.map((p) => (
          <ProjectCard key={p.id} project={p} />
        ))}
      </div>
    </main>
  );
}
```

```tsx
// frontend/app/projects/new/page.tsx
"use client";

import { useRouter } from "next/navigation";

import { NewProjectForm } from "@/components/NewProjectForm";
import { createProject } from "@/lib/api";

const DEMO_COMPANY_ID = process.env.NEXT_PUBLIC_DEMO_COMPANY_ID ?? "";

export default function NewProjectPage() {
  const router = useRouter();

  async function handleSubmit(data: { company_id: string; name: string; client_name: string }) {
    const project = await createProject(data);
    router.push(`/projects/${project.id}`);
  }

  return (
    <main className="mx-auto max-w-md p-6">
      <h1 className="mb-4 text-2xl font-bold">New Project</h1>
      <NewProjectForm companyId={DEMO_COMPANY_ID} onSubmit={handleSubmit} />
    </main>
  );
}
```

`NEXT_PUBLIC_DEMO_COMPANY_ID` is a placeholder wiring for this plan — Plan 1 doesn't build a company-switcher UI. Add it to `frontend/.env.local.example`:

```
NEXT_PUBLIC_DEMO_COMPANY_ID=
```

- [ ] **Step 10: Commit**

```bash
git add frontend/components/ProjectCard.tsx frontend/components/ProjectCard.test.tsx frontend/components/NewProjectForm.tsx frontend/components/NewProjectForm.test.tsx frontend/app/projects/ frontend/.env.local.example
git commit -m "feat: add project list and create-project UI"
```

---

## Task 19: Project detail UI (tasks, DPR form, issues, feed, dashboard)

**Files:**
- Modify: `frontend/lib/api.ts` (add task/DPR/issue/dashboard/feed calls)
- Create: `frontend/components/TaskList.tsx`
- Test: `frontend/components/TaskList.test.tsx`
- Create: `frontend/components/DPRForm.tsx`
- Test: `frontend/components/DPRForm.test.tsx`
- Create: `frontend/components/SiteFeed.tsx`
- Create: `frontend/components/DashboardWidget.tsx`
- Test: `frontend/components/DashboardWidget.test.tsx`
- Create: `frontend/app/projects/[id]/page.tsx`

- [ ] **Step 1: Extend `frontend/lib/api.ts`**

```ts
// append to frontend/lib/api.ts
export type Task = {
  id: string;
  project_id: string;
  title: string;
  status: "todo" | "in_progress" | "done" | "blocked";
  due_date: string | null;
};

export type DPREntry = {
  id: string;
  entry_date: string;
  work_summary: string;
  manpower_count: number;
  status: string;
};

export type Issue = {
  id: string;
  description: string;
  severity: string;
  status: string;
};

export type FeedItem = { type: string; id: string; occurred_at: string; summary: string };

export type Dashboard = {
  percent_tasks_complete: number;
  dpr_streak_days: number;
  open_issue_count: number;
};

export function listTasks(projectId: string) {
  return apiFetch<Task[]>(`/projects/${projectId}/tasks`);
}

export function createTask(projectId: string, title: string) {
  return apiFetch<Task>(`/projects/${projectId}/tasks`, {
    method: "POST",
    body: JSON.stringify({ title }),
  });
}

export function updateTaskStatus(projectId: string, taskId: string, status: Task["status"]) {
  return apiFetch<Task>(`/projects/${projectId}/tasks/${taskId}`, {
    method: "PATCH",
    body: JSON.stringify({ status }),
  });
}

export function listDprEntries(projectId: string) {
  return apiFetch<DPREntry[]>(`/projects/${projectId}/dpr`);
}

export function createDprEntry(
  projectId: string,
  data: { entry_date: string; work_summary: string; manpower_count: number }
) {
  return apiFetch<DPREntry>(`/projects/${projectId}/dpr`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}

export function listIssues(projectId: string) {
  return apiFetch<Issue[]>(`/projects/${projectId}/issues`);
}

export function getSiteFeed(projectId: string) {
  return apiFetch<FeedItem[]>(`/projects/${projectId}/feed`);
}

export function getDashboard(projectId: string) {
  return apiFetch<Dashboard>(`/projects/${projectId}/dashboard`);
}
```

- [ ] **Step 2: Write the failing TaskList test**

```tsx
// frontend/components/TaskList.test.tsx
import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { TaskList } from "./TaskList";

describe("TaskList", () => {
  const tasks = [
    { id: "1", project_id: "p1", title: "Pour footing", status: "todo" as const, due_date: null },
  ];

  it("renders each task's title and status", () => {
    render(<TaskList tasks={tasks} onStatusChange={vi.fn()} />);
    expect(screen.getByText("Pour footing")).toBeInTheDocument();
    expect(screen.getByDisplayValue("todo")).toBeInTheDocument();
  });

  it("calls onStatusChange when a task's status select changes", () => {
    const onStatusChange = vi.fn();
    render(<TaskList tasks={tasks} onStatusChange={onStatusChange} />);

    fireEvent.change(screen.getByDisplayValue("todo"), { target: { value: "done" } });

    expect(onStatusChange).toHaveBeenCalledWith("1", "done");
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd frontend && npm run test -- components/TaskList.test.tsx`
Expected: FAIL — `Cannot find module './TaskList'`

- [ ] **Step 4: Implement `frontend/components/TaskList.tsx`**

```tsx
import type { Task } from "@/lib/api";

const STATUSES: Task["status"][] = ["todo", "in_progress", "done", "blocked"];

export function TaskList({
  tasks,
  onStatusChange,
}: {
  tasks: Task[];
  onStatusChange: (taskId: string, status: Task["status"]) => void;
}) {
  return (
    <ul className="flex flex-col gap-2">
      {tasks.map((task) => (
        <li key={task.id} className="flex items-center justify-between rounded border border-slate-200 p-2">
          <span>{task.title}</span>
          <select
            value={task.status}
            onChange={(e) => onStatusChange(task.id, e.target.value as Task["status"])}
            className="rounded border border-slate-300 p-1 text-sm"
          >
            {STATUSES.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
        </li>
      ))}
    </ul>
  );
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd frontend && npm run test -- components/TaskList.test.tsx`
Expected: PASS

- [ ] **Step 6: Write the failing DPRForm test**

```tsx
// frontend/components/DPRForm.test.tsx
import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { DPRForm } from "./DPRForm";

describe("DPRForm", () => {
  it("submits entry date, work summary, and manpower count", () => {
    const onSubmit = vi.fn();
    render(<DPRForm onSubmit={onSubmit} />);

    fireEvent.change(screen.getByLabelText(/date/i), { target: { value: "2026-08-11" } });
    fireEvent.change(screen.getByLabelText(/work summary/i), {
      target: { value: "Poured 50 cum concrete on footing F12" },
    });
    fireEvent.change(screen.getByLabelText(/manpower/i), { target: { value: "8" } });
    fireEvent.click(screen.getByRole("button", { name: /submit dpr/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      entry_date: "2026-08-11",
      work_summary: "Poured 50 cum concrete on footing F12",
      manpower_count: 8,
    });
  });
});
```

- [ ] **Step 7: Run test to verify it fails**

Run: `cd frontend && npm run test -- components/DPRForm.test.tsx`
Expected: FAIL — `Cannot find module './DPRForm'`

- [ ] **Step 8: Implement `frontend/components/DPRForm.tsx`**

```tsx
"use client";

import { useState } from "react";

type DPRSubmission = { entry_date: string; work_summary: string; manpower_count: number };

export function DPRForm({ onSubmit }: { onSubmit: (data: DPRSubmission) => void }) {
  const [entryDate, setEntryDate] = useState("");
  const [workSummary, setWorkSummary] = useState("");
  const [manpowerCount, setManpowerCount] = useState("0");

  function handleSubmit() {
    onSubmit({
      entry_date: entryDate,
      work_summary: workSummary,
      manpower_count: Number(manpowerCount),
    });
  }

  return (
    <div className="flex flex-col gap-3">
      <label className="flex flex-col gap-1 text-sm">
        Date
        <input
          type="date"
          value={entryDate}
          onChange={(e) => setEntryDate(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Work summary
        <textarea
          value={workSummary}
          onChange={(e) => setWorkSummary(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <label className="flex flex-col gap-1 text-sm">
        Manpower count
        <input
          type="number"
          value={manpowerCount}
          onChange={(e) => setManpowerCount(e.target.value)}
          className="rounded border border-slate-300 p-2"
        />
      </label>
      <button onClick={handleSubmit} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
        Submit DPR
      </button>
    </div>
  );
}
```

- [ ] **Step 9: Run test to verify it passes**

Run: `cd frontend && npm run test -- components/DPRForm.test.tsx`
Expected: PASS

- [ ] **Step 10: Write the failing DashboardWidget test**

```tsx
// frontend/components/DashboardWidget.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { DashboardWidget } from "./DashboardWidget";

describe("DashboardWidget", () => {
  it("renders percent complete, DPR streak, and open issues", () => {
    render(
      <DashboardWidget dashboard={{ percent_tasks_complete: 50, dpr_streak_days: 3, open_issue_count: 2 }} />
    );

    expect(screen.getByText("50%")).toBeInTheDocument();
    expect(screen.getByText("3")).toBeInTheDocument();
    expect(screen.getByText("2")).toBeInTheDocument();
  });
});
```

- [ ] **Step 11: Run test to verify it fails**

Run: `cd frontend && npm run test -- components/DashboardWidget.test.tsx`
Expected: FAIL — `Cannot find module './DashboardWidget'`

- [ ] **Step 12: Implement `frontend/components/DashboardWidget.tsx`**

```tsx
import type { Dashboard } from "@/lib/api";

export function DashboardWidget({ dashboard }: { dashboard: Dashboard }) {
  return (
    <div className="grid grid-cols-3 gap-3">
      <div className="rounded border border-slate-200 p-3 text-center">
        <div className="text-2xl font-bold">{dashboard.percent_tasks_complete}%</div>
        <div className="text-xs text-slate-500">Tasks complete</div>
      </div>
      <div className="rounded border border-slate-200 p-3 text-center">
        <div className="text-2xl font-bold">{dashboard.dpr_streak_days}</div>
        <div className="text-xs text-slate-500">Day DPR streak</div>
      </div>
      <div className="rounded border border-slate-200 p-3 text-center">
        <div className="text-2xl font-bold">{dashboard.open_issue_count}</div>
        <div className="text-xs text-slate-500">Open issues</div>
      </div>
    </div>
  );
}
```

- [ ] **Step 13: Run test to verify it passes**

Run: `cd frontend && npm run test -- components/DashboardWidget.test.tsx`
Expected: PASS

- [ ] **Step 14: Implement `frontend/components/SiteFeed.tsx` (no dedicated test — trivial rendering of already-typed data, exercised by the Task 20 smoke test)**

```tsx
import type { FeedItem } from "@/lib/api";

export function SiteFeed({ items }: { items: FeedItem[] }) {
  return (
    <ul className="flex flex-col gap-2">
      {items.map((item) => (
        <li key={`${item.type}-${item.id}`} className="rounded border border-slate-200 p-2">
          <span className="mr-2 rounded bg-slate-100 px-1.5 py-0.5 text-xs uppercase text-slate-500">
            {item.type}
          </span>
          {item.summary}
        </li>
      ))}
    </ul>
  );
}
```

- [ ] **Step 15: Wire up the project detail page (thin composition, no new tests)**

```tsx
// frontend/app/projects/[id]/page.tsx
"use client";

import { useEffect, useState } from "react";

import { DashboardWidget } from "@/components/DashboardWidget";
import { DPRForm } from "@/components/DPRForm";
import { SiteFeed } from "@/components/SiteFeed";
import { TaskList } from "@/components/TaskList";
import {
  createDprEntry,
  createTask,
  getDashboard,
  getSiteFeed,
  listTasks,
  updateTaskStatus,
  type Dashboard,
  type FeedItem,
  type Task,
} from "@/lib/api";

export default function ProjectDetailPage({ params }: { params: { id: string } }) {
  const projectId = params.id;
  const [tasks, setTasks] = useState<Task[]>([]);
  const [feed, setFeed] = useState<FeedItem[]>([]);
  const [dashboard, setDashboard] = useState<Dashboard | null>(null);
  const [newTaskTitle, setNewTaskTitle] = useState("");

  async function refresh() {
    const [t, f, d] = await Promise.all([
      listTasks(projectId),
      getSiteFeed(projectId),
      getDashboard(projectId),
    ]);
    setTasks(t);
    setFeed(f);
    setDashboard(d);
  }

  useEffect(() => {
    refresh().catch(console.error);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [projectId]);

  async function handleAddTask() {
    if (!newTaskTitle.trim()) return;
    await createTask(projectId, newTaskTitle);
    setNewTaskTitle("");
    refresh();
  }

  async function handleStatusChange(taskId: string, status: Task["status"]) {
    await updateTaskStatus(projectId, taskId, status);
    refresh();
  }

  async function handleDprSubmit(data: { entry_date: string; work_summary: string; manpower_count: number }) {
    await createDprEntry(projectId, data);
    refresh();
  }

  return (
    <main className="mx-auto grid max-w-4xl gap-8 p-6">
      {dashboard && <DashboardWidget dashboard={dashboard} />}

      <section>
        <h2 className="mb-2 text-lg font-semibold">Tasks</h2>
        <div className="mb-3 flex gap-2">
          <input
            value={newTaskTitle}
            onChange={(e) => setNewTaskTitle(e.target.value)}
            placeholder="New task title"
            className="flex-1 rounded border border-slate-300 p-2"
          />
          <button onClick={handleAddTask} type="button" className="rounded bg-slate-900 px-4 py-2 text-white">
            Add
          </button>
        </div>
        <TaskList tasks={tasks} onStatusChange={handleStatusChange} />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">Daily Progress Report</h2>
        <DPRForm onSubmit={handleDprSubmit} />
      </section>

      <section>
        <h2 className="mb-2 text-lg font-semibold">Site Feed</h2>
        <SiteFeed items={feed} />
      </section>
    </main>
  );
}
```

- [ ] **Step 16: Commit**

```bash
git add frontend/lib/api.ts frontend/components/TaskList.tsx frontend/components/TaskList.test.tsx frontend/components/DPRForm.tsx frontend/components/DPRForm.test.tsx frontend/components/DashboardWidget.tsx frontend/components/DashboardWidget.test.tsx frontend/components/SiteFeed.tsx frontend/app/projects/[id]/
git commit -m "feat: add project detail UI with tasks, DPR form, feed, and dashboard"
```

---

## Task 20: End-to-end manual smoke test

**Files:** none (verification only)

- [ ] **Step 1: Run the full backend test suite**

Run: `pytest tests/fieldos/ -v`
Expected: all tests PASS

- [ ] **Step 2: Run the full frontend test suite**

Run: `cd frontend && npm run test`
Expected: all tests PASS

- [ ] **Step 3: Start a local Supabase dev stack (Postgres + Auth + Storage)**

Run: `supabase start` (requires the Supabase CLI; see https://supabase.com/docs/guides/local-development)
Expected: prints local `API URL`, `anon key`, and `service_role key` — copy these into `.env` (backend) and `frontend/.env.local`.

- [ ] **Step 4: Apply migrations to the local Supabase Postgres**

Run: `alembic upgrade head`
Expected: no errors.

- [ ] **Step 5: Start the backend**

Run: `python api.py`
Expected: server starts on port 8000 (RAG retriever loading may take a while on first run — that's expected and unrelated to FieldOS routes).

- [ ] **Step 6: Start the frontend**

Run: `cd frontend && npm run dev`
Expected: server starts on port 3000.

- [ ] **Step 7: Seed real Protek Consult data via the API**

Instead of throwaway placeholder names, seed the company and its three real projects
(from `resources/`) so the walkthrough exercises the app with data that actually
matters. Visit `http://localhost:3000/login`, sign in via OTP, then copy the
session's access token (from the browser's dev tools → Application → Local
Storage → the Supabase auth entry, or from the `/companies` call's `Authorization`
header if you're driving this from `http://localhost:8000/docs` instead) and use
it below.

```bash
TOKEN="paste-your-access-token-here"

# Create the company — note the returned "id"
curl -s -X POST http://localhost:8000/companies \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name": "Protek Consult"}'

COMPANY_ID="paste-the-id-from-above"

# Narapally — S+5 residential, ~10,097.7 SFT total slab area
curl -s -X POST http://localhost:8000/projects \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\": \"$COMPANY_ID\", \"name\": \"Narapally Residential (S+5)\", \"start_date\": \"2026-01-01\"}"

# Thumukunta — S+4+1 TDR, 2,415.83 SFT/floor
curl -s -X POST http://localhost:8000/projects \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\": \"$COMPANY_ID\", \"name\": \"Thumukunta Residential (S+4+1 TDR)\", \"start_date\": \"2026-01-01\"}"

# Vidyanagar — G+1 duplex, internally "Upperpally Duplex"
curl -s -X POST http://localhost:8000/projects \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d "{\"company_id\": \"$COMPANY_ID\", \"name\": \"Vidyanagar Duplex (Upperpally)\", \"start_date\": \"2026-01-01\"}"
```

Expected: three `201` responses, each with a distinct project `id`. Keep the
Narapally project's `id` for the next step.

- [ ] **Step 8: Manual UI walkthrough on the Narapally project**

1. Set `NEXT_PUBLIC_DEMO_COMPANY_ID` in `frontend/.env.local` to the company id from
   Step 7 and restart the frontend (`npm run dev`).
2. Visit `/projects` — confirm all three seeded projects (Narapally, Thumukunta,
   Vidyanagar) render as cards.
3. Open the Narapally project (`/projects/<narapally-id>`) and add a task grounded
   in its real BOQ: title `Brick work - 9" walls, Flat 1 First Floor`.
   Change its status to `in_progress`, then `done`.
4. Submit a manual DPR entry: date today, work summary
   `Completed 9" brick work on Flat 1 & Flat 2, first floor. Shuttering started for typical floor slab.`,
   manpower count `12`.
5. Confirm the dashboard's "Tasks complete" (should read `100%` with one done task)
   and "DPR streak" (`1`) update, and confirm the DPR entry appears in the Site Feed.

Expected: every step works without console errors, and the three real project
names are visible throughout — not placeholder data.

- [ ] **Step 9: Commit**

```bash
git commit --allow-empty -m "chore: Plan 1 (foundation + core CRUD) verified end-to-end with real Protek Consult project data"
```

---

## What's Next

- **Plan 2** — voice-driven agentic DPR flow: `dpr_voice_notes` + `agent_actions_log` tables, Sarvam STT integration, Claude tool-calling agent, draft→confirm UI.
- **Plan 3** — offline-first sync: service worker, IndexedDB queue, `/sync/push` endpoint, background sync retry.
