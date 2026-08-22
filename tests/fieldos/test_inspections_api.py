from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_create_inspection(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection", "inspection_type": "quality", "scheduled_date": "2025-01-15"},
    )

    assert response.status_code == 201
    insp = response.json()
    assert insp["title"] == "Foundation Inspection"
    assert insp["inspection_type"] == "quality"
    assert insp["status"] == "open"
    assert insp["project_id"] == project["id"]


def test_list_inspections(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    owner_client.post(f"/projects/{project['id']}/inspections", json={"title": "Inspection 1"})
    owner_client.post(f"/projects/{project['id']}/inspections", json={"title": "Inspection 2"})

    response = owner_client.get(f"/projects/{project['id']}/inspections")

    assert response.status_code == 200
    insps = response.json()
    assert len(insps) == 2


def test_complete_inspection_sets_overall_result(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection"},
    )
    insp_id = create_resp.json()["id"]

    complete_resp = owner_client.patch(
        f"/projects/{project['id']}/inspections/{insp_id}/complete?result=pass",
    )

    assert complete_resp.status_code == 200
    assert complete_resp.json()["status"] == "completed"
    assert complete_resp.json()["overall_result"] == "pass"


def test_complete_inspection_invalid_result_rejected(db_session):
    """Regression test: the result parameter used to accept any free-text string.
    Now it should reject invalid values with 422."""
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection"},
    )
    insp_id = create_resp.json()["id"]

    # Invalid result value should be rejected
    response = owner_client.patch(
        f"/projects/{project['id']}/inspections/{insp_id}/complete?result=maybe",
    )

    assert response.status_code == 422


def test_complete_inspection_with_fail_result(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection"},
    )
    insp_id = create_resp.json()["id"]

    complete_resp = owner_client.patch(
        f"/projects/{project['id']}/inspections/{insp_id}/complete?result=fail",
    )

    assert complete_resp.status_code == 200
    assert complete_resp.json()["overall_result"] == "fail"


def test_add_inspection_item(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection"},
    )
    insp_id = create_resp.json()["id"]

    response = owner_client.post(
        f"/inspections/{insp_id}/items",
        json={"item_description": "Check rebar spacing", "status": "pending"},
    )

    assert response.status_code == 201
    item = response.json()
    assert item["item_description"] == "Check rebar spacing"
    assert item["status"] == "pending"
    assert item["inspection_id"] == insp_id


def test_list_inspection_items(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection"},
    )
    insp_id = create_resp.json()["id"]

    owner_client.post(f"/inspections/{insp_id}/items", json={"item_description": "Item 1"})
    owner_client.post(f"/inspections/{insp_id}/items", json={"item_description": "Item 2"})

    response = owner_client.get(f"/inspections/{insp_id}/items")

    assert response.status_code == 200
    items = response.json()
    assert len(items) == 2
    assert items[0]["item_description"] == "Item 1"
    assert items[1]["item_description"] == "Item 2"


def test_update_inspection_item(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/inspections",
        json={"title": "Foundation Inspection"},
    )
    insp_id = create_resp.json()["id"]

    item_resp = owner_client.post(
        f"/inspections/{insp_id}/items",
        json={"item_description": "Check rebar", "status": "pending"},
    )
    item_id = item_resp.json()["id"]

    update_resp = owner_client.patch(
        f"/inspections/{insp_id}/items/{item_id}",
        json={"item_description": "Check rebar spacing", "status": "pass"},
    )

    assert update_resp.status_code == 200
    assert update_resp.json()["status"] == "pass"
    assert update_resp.json()["item_description"] == "Check rebar spacing"