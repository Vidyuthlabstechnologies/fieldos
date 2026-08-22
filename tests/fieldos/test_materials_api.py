from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_create_material_entry(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/projects/{project['id']}/materials",
        json={
            "entry_date": "2025-01-15",
            "item_name": "Cement",
            "category": "cement",
            "quantity": "50",
            "unit": "bags",
            "supplier": "ABC Supplies",
            "cost": "15000.00",
        },
    )

    assert response.status_code == 201
    entry = response.json()
    assert entry["item_name"] == "Cement"
    assert entry["category"] == "cement"
    assert entry["quantity"] == "50.000"
    assert entry["project_id"] == project["id"]


def test_list_material_entries(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    owner_client.post(
        f"/projects/{project['id']}/materials",
        json={"entry_date": "2025-01-15", "item_name": "Cement", "category": "cement", "quantity": "50", "unit": "bags"},
    )
    owner_client.post(
        f"/projects/{project['id']}/materials",
        json={"entry_date": "2025-01-16", "item_name": "Sand", "category": "sand", "quantity": "100", "unit": "cft"},
    )

    response = owner_client.get(f"/projects/{project['id']}/materials")

    assert response.status_code == 200
    entries = response.json()
    assert len(entries) == 2
    assert entries[0]["item_name"] == "Sand"
    assert entries[1]["item_name"] == "Cement"


def test_material_summary_endpoint(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    owner_client.post(
        f"/projects/{project['id']}/materials",
        json={"entry_date": "2025-01-15", "item_name": "Cement", "category": "cement", "quantity": "50", "unit": "bags", "cost": "15000.00"},
    )
    owner_client.post(
        f"/projects/{project['id']}/materials",
        json={"entry_date": "2025-01-16", "item_name": "Sand", "category": "sand", "quantity": "100", "unit": "cft", "cost": "5000.00"},
    )

    response = owner_client.get(f"/projects/{project['id']}/materials/summary")

    assert response.status_code == 200
    summary = response.json()
    assert len(summary) == 2
    cement = next(s for s in summary if s["category"] == "cement")
    sand = next(s for s in summary if s["category"] == "sand")
    assert cement["count"] == 1
    assert cement["total_cost"] == "15000.00"
    assert cement["total_quantity"] == "50.000"
    assert sand["count"] == 1
    assert sand["total_cost"] == "5000.00"
    assert sand["total_quantity"] == "100.000"


def test_upload_material_photo(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/materials",
        json={"entry_date": "2025-01-15", "item_name": "Cement", "category": "cement", "quantity": "50", "unit": "bags"},
    )
    entry_id = create_resp.json()["id"]

    response = owner_client.post(
        f"/projects/{project['id']}/materials/{entry_id}/photos?caption=Cement+delivery",
        files={"file": ("cement.jpg", b"fake image", "image/jpeg")},
    )

    assert response.status_code == 201
    photo = response.json()
    assert photo["material_entry_id"] == entry_id
    assert photo["caption"] == "Cement delivery"
    assert photo["photo_url"].startswith("/uploads/")


def test_list_material_photos(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/projects/{project['id']}/materials",
        json={"entry_date": "2025-01-15", "item_name": "Cement", "category": "cement", "quantity": "50", "unit": "bags"},
    )
    entry_id = create_resp.json()["id"]

    owner_client.post(
        f"/projects/{project['id']}/materials/{entry_id}/photos?caption=First+delivery",
        files={"file": ("photo1.jpg", b"img1", "image/jpeg")},
    )
    owner_client.post(
        f"/projects/{project['id']}/materials/{entry_id}/photos?caption=Second+delivery",
        files={"file": ("photo2.jpg", b"img2", "image/jpeg")},
    )

    response = owner_client.get(f"/projects/{project['id']}/materials/{entry_id}/photos")

    assert response.status_code == 200
    photos = response.json()
    assert len(photos) == 2
    # list_material_photos has no explicit ORDER BY -- insertion order
    assert photos[0]["caption"] == "First delivery"
    assert photos[1]["caption"] == "Second delivery"