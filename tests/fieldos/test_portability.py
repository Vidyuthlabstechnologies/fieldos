from decimal import Decimal

from tests.fieldos.conftest import build_client


def _make_populated_project(client, company_id: str) -> str:
    project = client.post(
        "/projects", json={"company_id": company_id, "name": "Narapally S+5", "client_name": "Acme Builders"}
    ).json()
    project_id = project["id"]

    client.post(f"/projects/{project_id}/tasks", json={"title": "Pour foundation"})

    dpr = client.post(
        f"/projects/{project_id}/dpr",
        json={"entry_date": "2026-08-01", "work_summary": "Poured column footings", "manpower_count": 12},
    ).json()

    issue = client.post(
        f"/projects/{project_id}/issues",
        json={"description": "Rebar delivery delayed", "severity": "high", "dpr_entry_id": dpr["id"]},
    )
    assert issue.status_code == 201

    estimation = client.post(
        f"/projects/{project_id}/estimations",
        json={"name": "Structural BOQ", "contractor_profit_percent": "10"},
    ).json()

    cost_head = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={
            "name": "9\" Brick wall",
            "calculation_type": "volume",
            "raw_unit": "CFT",
            "billing_unit": "CUM",
            "conversion_factor": "0.0283",
            "rate_per_unit": "450",
        },
    ).json()

    client.post(
        f"/cost-heads/{cost_head['id']}/measurement-entries",
        json={"description": "WALL(9\")", "length": "108.25", "width": "0.75", "depth": "8.85", "nos": "1"},
    )
    client.post(
        f"/cost-heads/{cost_head['id']}/measurement-entries",
        json={
            "description": "D1 deduction",
            "length": "3.5",
            "width": "0.75",
            "depth": "7",
            "nos": "1",
            "is_deduction": True,
        },
    )

    steel_head = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={
            "name": "Column reinforcement",
            "calculation_type": "steel_weight",
            "raw_unit": "KG",
            "billing_unit": "TONNE",
            "conversion_factor": "0.001",
        },
    ).json()
    client.post(
        f"/cost-heads/{steel_head['id']}/steel-entries",
        json={"description": "C1 25mm", "bar_dia_mm": "25", "nos": "16", "length_ft": "10.5"},
    )

    return project_id


def test_export_includes_the_full_project_tree(db_session):
    client = build_client(db_session, user_id="owner-1")
    client.post("/companies", json={"name": "Protek Consult"})
    company_id = client.get("/companies/mine").json()[0]["id"]
    project_id = _make_populated_project(client, company_id)

    response = client.get(f"/projects/{project_id}/export")

    assert response.status_code == 200
    body = response.json()
    assert body["format"] == "fieldos.project_export.v1"
    assert body["project"]["name"] == "Narapally S+5"
    assert len(body["tasks"]) == 1
    assert len(body["dpr_entries"]) == 1
    assert len(body["issues"]) == 1
    assert body["issues"][0]["dpr_entry_local_id"] == body["dpr_entries"][0]["local_id"]
    assert len(body["estimations"]) == 1
    assert len(body["estimations"][0]["cost_heads"]) == 2


def test_import_recreates_an_equivalent_project_in_a_different_company(db_session):
    client_a = build_client(db_session, user_id="owner-a")
    client_a.post("/companies", json={"name": "Site Office"})
    company_a = client_a.get("/companies/mine").json()[0]["id"]
    project_id = _make_populated_project(client_a, company_a)
    exported = client_a.get(f"/projects/{project_id}/export").json()

    client_b = build_client(db_session, user_id="owner-b")
    client_b.post("/companies", json={"name": "Head Office"})
    company_b = client_b.get("/companies/mine").json()[0]["id"]

    import_response = client_b.post(f"/companies/{company_b}/import", json=exported)
    assert import_response.status_code == 201
    new_project_id = import_response.json()["id"]
    assert import_response.json()["company_id"] == company_b

    reexported = client_b.get(f"/projects/{new_project_id}/export").json()

    # The re-exported copy must be byte-for-byte equivalent to the original
    # export, aside from the format marker itself -- this is the real
    # correctness bar for a data-portability feature, not just "didn't crash".
    assert reexported == exported


def test_import_rejects_an_unrecognized_export_format(db_session):
    client = build_client(db_session, user_id="owner-1")
    client.post("/companies", json={"name": "Protek Consult"})
    company_id = client.get("/companies/mine").json()[0]["id"]

    response = client.post(
        f"/companies/{company_id}/import",
        json={"format": "some.other.format.v9", "project": {"name": "X", "status": "planning"}},
    )

    assert response.status_code == 422


def test_import_requires_owner_or_pm_role(db_session):
    from fieldos.models import CompanyMember

    client = build_client(db_session, user_id="owner-1")
    company = client.post("/companies", json={"name": "Protek Consult"}).json()
    project_id = _make_populated_project(client, company["id"])
    exported = client.get(f"/projects/{project_id}/export").json()

    db_session.add(CompanyMember(company_id=company["id"], user_id="site-eng-1", role="site_engineer"))
    db_session.commit()
    site_engineer_client = build_client(db_session, user_id="site-eng-1")

    response = site_engineer_client.post(f"/companies/{company['id']}/import", json=exported)

    assert response.status_code == 403


def test_measurement_entry_decimal_precision_survives_a_round_trip(db_session):
    client = build_client(db_session, user_id="owner-1")
    client.post("/companies", json={"name": "Protek Consult"})
    company_id = client.get("/companies/mine").json()[0]["id"]
    project_id = _make_populated_project(client, company_id)

    exported = client.get(f"/projects/{project_id}/export").json()
    entry = exported["estimations"][0]["cost_heads"][0]["measurement_entries"][0]

    assert Decimal(entry["length"]) == Decimal("108.25")
    assert Decimal(entry["width"]) == Decimal("0.75")
    assert Decimal(entry["depth"]) == Decimal("8.85")
