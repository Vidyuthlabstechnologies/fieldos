from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def _add_site_engineer(db_session, company_id, project_id, user_id="engineer-1"):
    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company_id, user_id=user_id, role="site_engineer"))
    db_session.add(ProjectMember(project_id=project_id, user_id=user_id, role="site_engineer"))
    db_session.commit()


def test_create_worker_requires_owner_or_pm_regression(db_session):
    """Regression test: worker CRUD used to be open to any project member,
    which let any site engineer edit payroll data (daily_wage)."""
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    _add_site_engineer(db_session, company["id"], project["id"])
    engineer_client = build_client(db_session, user_id="engineer-1")

    denied = engineer_client.post(
        f"/projects/{project['id']}/workers",
        json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "800.00"},
    )
    assert denied.status_code == 403

    allowed = owner_client.post(
        f"/projects/{project['id']}/workers",
        json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "800.00"},
    )
    assert allowed.status_code == 201
    worker = allowed.json()
    assert worker["name"] == "Ravi Kumar"
    assert worker["status"] == "active"


def test_update_worker_requires_owner_or_pm_regression(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    _add_site_engineer(db_session, company["id"], project["id"])
    engineer_client = build_client(db_session, user_id="engineer-1")

    worker = owner_client.post(
        f"/projects/{project['id']}/workers",
        json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "800.00"},
    ).json()

    denied = engineer_client.patch(
        f"/projects/{project['id']}/workers/{worker['id']}",
        json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "5000.00"},
    )
    assert denied.status_code == 403

    allowed = owner_client.patch(
        f"/projects/{project['id']}/workers/{worker['id']}",
        json={"name": "Ravi Kumar", "role": "head mason", "daily_wage": "900.00"},
    )
    assert allowed.status_code == 200
    assert allowed.json()["role"] == "head mason"
    assert allowed.json()["daily_wage"] == "900.00"


def test_deactivate_worker_requires_owner_or_pm_regression(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    _add_site_engineer(db_session, company["id"], project["id"])
    engineer_client = build_client(db_session, user_id="engineer-1")

    worker = owner_client.post(
        f"/projects/{project['id']}/workers",
        json={"name": "Ravi Kumar", "role": "mason"},
    ).json()

    denied = engineer_client.delete(f"/projects/{project['id']}/workers/{worker['id']}")
    assert denied.status_code == 403

    allowed = owner_client.delete(f"/projects/{project['id']}/workers/{worker['id']}")
    assert allowed.status_code == 204

    workers = owner_client.get(f"/projects/{project['id']}/workers").json()
    assert workers[0]["status"] == "inactive"


def test_list_workers_open_to_any_project_member(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    _add_site_engineer(db_session, company["id"], project["id"])
    engineer_client = build_client(db_session, user_id="engineer-1")

    owner_client.post(f"/projects/{project['id']}/workers", json={"name": "Ravi Kumar", "role": "mason"})

    response = engineer_client.get(f"/projects/{project['id']}/workers")

    assert response.status_code == 200
    assert len(response.json()) == 1


def test_mark_attendance_open_to_any_project_member(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)
    _add_site_engineer(db_session, company["id"], project["id"])
    engineer_client = build_client(db_session, user_id="engineer-1")

    worker = owner_client.post(
        f"/projects/{project['id']}/workers", json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "800.00"}
    ).json()

    response = engineer_client.post(
        f"/projects/{project['id']}/attendance",
        json={"worker_id": worker["id"], "attendance_date": "2025-01-15", "status": "present"},
    )

    assert response.status_code == 201
    assert response.json()["status"] == "present"


def test_mark_attendance_twice_same_day_updates_not_duplicates(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    worker = owner_client.post(
        f"/projects/{project['id']}/workers", json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "800.00"}
    ).json()

    owner_client.post(
        f"/projects/{project['id']}/attendance",
        json={"worker_id": worker["id"], "attendance_date": "2025-01-15", "status": "present"},
    )
    second = owner_client.post(
        f"/projects/{project['id']}/attendance",
        json={"worker_id": worker["id"], "attendance_date": "2025-01-15", "status": "half_day"},
    )

    assert second.status_code == 201
    assert second.json()["status"] == "half_day"

    records = owner_client.get(f"/projects/{project['id']}/attendance").json()
    assert len(records) == 1


def test_attendance_summary(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    from datetime import date

    today = date.today().isoformat()

    worker = owner_client.post(
        f"/projects/{project['id']}/workers", json={"name": "Ravi Kumar", "role": "mason", "daily_wage": "800.00"}
    ).json()
    owner_client.post(
        f"/projects/{project['id']}/attendance",
        json={"worker_id": worker["id"], "attendance_date": today, "status": "present"},
    )

    response = owner_client.get(f"/projects/{project['id']}/attendance/summary")

    assert response.status_code == 200
    summary = response.json()
    assert summary["total_workers"] == 1
    assert summary["present"] == 1
    assert summary["absent"] == 0
    assert summary["total_wage_cost"] == "800.00"
