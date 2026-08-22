from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_upload_document_creates_version_1(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/projects/{project['id']}/documents?category=drawing",
        files={"file": ("test.pdf", b"fake content", "application/pdf")},
    )

    assert response.status_code == 201
    doc = response.json()
    assert doc["name"] == "test.pdf"
    assert doc["version"] == 1
    assert doc["category"] == "drawing"
    assert doc["project_id"] == project["id"]


def test_list_documents_returns_uploaded_document(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    owner_client.post(
        f"/projects/{project['id']}/documents?category=drawing",
        files={"file": ("test.pdf", b"fake content", "application/pdf")},
    )

    response = owner_client.get(f"/projects/{project['id']}/documents")

    assert response.status_code == 200
    docs = response.json()
    assert len(docs) == 1
    assert docs[0]["name"] == "test.pdf"


def test_upload_same_filename_increments_version(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    # Upload first version
    resp1 = owner_client.post(
        f"/projects/{project['id']}/documents?category=drawing",
        files={"file": ("plan.pdf", b"version 1", "application/pdf")},
    )
    assert resp1.status_code == 201
    assert resp1.json()["version"] == 1

    # Upload same filename again
    resp2 = owner_client.post(
        f"/projects/{project['id']}/documents?category=specification",
        files={"file": ("plan.pdf", b"version 2", "application/pdf")},
    )
    assert resp2.status_code == 201
    assert resp2.json()["version"] == 2


def test_document_versions_endpoint_returns_all_versions(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    # Upload two versions
    owner_client.post(
        f"/projects/{project['id']}/documents?category=drawing",
        files={"file": ("plan.pdf", b"version 1", "application/pdf")},
    )
    owner_client.post(
        f"/projects/{project['id']}/documents?category=drawing",
        files={"file": ("plan.pdf", b"version 2", "application/pdf")},
    )

    response = owner_client.get(f"/projects/{project['id']}/documents/versions/plan.pdf")

    assert response.status_code == 200
    versions = response.json()
    assert len(versions) == 2
    # Should be ordered by version desc
    assert versions[0]["version"] == 2
    assert versions[1]["version"] == 1


def test_list_documents_filter_by_category(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    owner_client.post(
        f"/projects/{project['id']}/documents?category=drawing",
        files={"file": ("drawing1.pdf", b"content", "application/pdf")},
    )
    owner_client.post(
        f"/projects/{project['id']}/documents?category=specification",
        files={"file": ("spec1.pdf", b"content", "application/pdf")},
    )

    response = owner_client.get(f"/projects/{project['id']}/documents?category=drawing")

    assert response.status_code == 200
    docs = response.json()
    assert len(docs) == 1
    assert docs[0]["category"] == "drawing"