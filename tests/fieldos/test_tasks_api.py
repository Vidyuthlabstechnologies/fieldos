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
