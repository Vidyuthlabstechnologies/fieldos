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
