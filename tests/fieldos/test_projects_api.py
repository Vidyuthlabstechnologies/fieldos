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
