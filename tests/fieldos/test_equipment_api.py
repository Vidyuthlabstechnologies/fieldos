from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_create_equipment(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy", "model": "CAT 320", "daily_rate": "500.00"},
    )

    assert response.status_code == 201
    eq = response.json()
    assert eq["name"] == "Excavator"
    assert eq["equipment_type"] == "heavy"
    assert eq["status"] == "available"
    assert eq["project_id"] == project["id"]


def test_list_equipment(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy"},
    )
    owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Dump Truck", "equipment_type": "transport"},
    )

    response = owner_client.get(f"/projects/{project['id']}/equipment")

    assert response.status_code == 200
    eqs = response.json()
    assert len(eqs) == 2
    assert eqs[0]["name"] == "Dump Truck"
    assert eqs[1]["name"] == "Excavator"


def test_update_equipment_status_regression(db_session):
    """Regression test: PATCH /projects/{id}/equipment/{eq_id} with status field
    used to accept wrong schema and could never actually update status."""
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    # Create equipment
    create_resp = owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy"},
    )
    eq_id = create_resp.json()["id"]

    # Update status to maintenance
    update_resp = owner_client.patch(
        f"/projects/{project['id']}/equipment/{eq_id}",
        json={"status": "maintenance"},
    )

    assert update_resp.status_code == 200
    assert update_resp.json()["status"] == "maintenance"

    # Verify it persists
    list_resp = owner_client.get(f"/projects/{project['id']}/equipment")
    assert list_resp.status_code == 200
    eq = next(e for e in list_resp.json() if e["id"] == eq_id)
    assert eq["status"] == "maintenance"


def test_update_equipment_other_fields(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy", "daily_rate": "500.00"},
    )
    eq_id = create_resp.json()["id"]

    update_resp = owner_client.patch(
        f"/projects/{project['id']}/equipment/{eq_id}",
        json={"daily_rate": "600.00", "notes": "Updated rate"},
    )

    assert update_resp.status_code == 200
    assert update_resp.json()["daily_rate"] == "600.00"
    assert update_resp.json()["notes"] == "Updated rate"


def test_remove_equipment_requires_owner_or_pm(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.add(ProjectMember(project_id=project["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    create_resp = owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy"},
    )
    eq_id = create_resp.json()["id"]

    engineer_client = build_client(db_session, user_id="engineer-1")

    # Site engineer should get 403
    denied = engineer_client.delete(f"/projects/{project['id']}/equipment/{eq_id}")
    assert denied.status_code == 403

    # Owner should succeed with 204
    allowed = owner_client.delete(f"/projects/{project['id']}/equipment/{eq_id}")
    assert allowed.status_code == 204

    # Verify it's gone
    list_resp = owner_client.get(f"/projects/{project['id']}/equipment")
    assert list_resp.status_code == 200
    assert len(list_resp.json()) == 0


def test_create_equipment_log(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy"},
    )
    eq_id = create_resp.json()["id"]

    response = owner_client.post(
        f"/equipment/{eq_id}/logs",
        json={"log_date": "2025-01-15", "log_type": "usage", "hours_used": "8.0", "description": "Foundation digging"},
    )

    assert response.status_code == 201
    log = response.json()
    assert log["equipment_id"] == eq_id
    assert log["log_type"] == "usage"
    assert log["hours_used"] == "8.00"


def test_list_equipment_logs(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/equipment",
        json={"name": "Excavator", "equipment_type": "heavy"},
    )
    eq_id = create_resp.json()["id"]

    owner_client.post(f"/equipment/{eq_id}/logs", json={"log_date": "2025-01-15", "log_type": "usage", "hours_used": "8.0"})
    owner_client.post(f"/equipment/{eq_id}/logs", json={"log_date": "2025-01-16", "log_type": "maintenance", "description": "Oil change"})

    response = owner_client.get(f"/equipment/{eq_id}/logs")

    assert response.status_code == 200
    logs = response.json()
    assert len(logs) == 2
    assert logs[0]["log_type"] == "maintenance"
    assert logs[1]["log_type"] == "usage"