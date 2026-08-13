from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Protek Consult"}).json()
    project = client.post(
        "/projects", json={"company_id": company["id"], "name": "Narapally Residential (S+5)"}
    ).json()
    return company, project


def test_create_and_list_estimations(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(
        f"/projects/{project['id']}/estimations",
        json={"name": "Narapally BOQ v1", "contractor_profit_percent": "10.00"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "draft"
    assert body["contractor_profit_percent"] == "10.00"

    listing = client.get(f"/projects/{project['id']}/estimations")
    assert listing.status_code == 200
    assert len(listing.json()) == 1


def test_estimation_denies_non_project_member(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    stranger_client = build_client(db_session, user_id="stranger-1")
    response = stranger_client.post(
        f"/projects/{project['id']}/estimations", json={"name": "Should fail"}
    )
    assert response.status_code == 403


def test_create_cost_head(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    estimation = client.post(f"/projects/{project['id']}/estimations", json={"name": "Est 1"}).json()

    response = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={
            "name": 'Brick Work - 9" Walls',
            "calculation_type": "volume",
            "raw_unit": "CFT",
            "billing_unit": "CFT",
            "rate_per_unit": "150.00",
        },
    )
    assert response.status_code == 201
    assert response.json()["calculation_type"] == "volume"


def test_measurement_entry_rejected_for_steel_cost_head(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    estimation = client.post(f"/projects/{project['id']}/estimations", json={"name": "Est 1"}).json()
    cost_head = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={
            "name": "Column Reinforcement",
            "calculation_type": "steel_weight",
            "raw_unit": "KG",
            "billing_unit": "TONNES",
            "conversion_factor": "0.001",
        },
    ).json()

    response = client.post(
        f"/cost-heads/{cost_head['id']}/measurement-entries",
        json={"description": "Should fail", "length": "10", "width": "1", "depth": "1", "nos": "1"},
    )
    assert response.status_code == 422


def test_steel_entry_rejected_for_non_steel_cost_head(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    estimation = client.post(f"/projects/{project['id']}/estimations", json={"name": "Est 1"}).json()
    cost_head = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={"name": "Brick Work", "calculation_type": "volume", "raw_unit": "CFT", "billing_unit": "CFT"},
    ).json()

    response = client.post(
        f"/cost-heads/{cost_head['id']}/steel-entries",
        json={"description": "Should fail", "bar_dia_mm": "16", "nos": "10", "length_ft": "10"},
    )
    assert response.status_code == 422


def test_boq_computes_real_narapally_wall_quantity_and_amount(db_session):
    # Grounded in the real NARAPALLY MASONRY ESTIMATION.xlsx BOQ sheet:
    # Wall(9") L=108.25 W=0.75 D=8.85 Nos=1 -> 718.509375 CFT.
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    estimation = client.post(
        f"/projects/{project['id']}/estimations",
        json={"name": "Narapally BOQ v1", "contractor_profit_percent": "10"},
    ).json()
    cost_head = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={
            "name": 'Brick Work - 9" Walls',
            "calculation_type": "volume",
            "raw_unit": "CFT",
            "billing_unit": "CFT",
            "rate_per_unit": "20",
        },
    ).json()
    client.post(
        f"/cost-heads/{cost_head['id']}/measurement-entries",
        json={"description": 'WALL(9")', "length": "108.25", "width": "0.75", "depth": "8.85", "nos": "1"},
    )

    response = client.get(f"/estimations/{estimation['id']}/boq")

    assert response.status_code == 200
    body = response.json()
    line = body["lines"][0]
    # Quantities/amounts are rounded for display at the API boundary (6dp for
    # quantities, 2dp for money) -- the internal calculation engine itself
    # stays exact/unrounded (see test_estimation_calc.py and
    # test_estimation_boq_rollup.py for the unrounded golden-number checks).
    assert line["raw_quantity"] == "718.509375"
    assert line["amount"] == "14370.19"
    assert body["subtotal"] == "14370.19"
    assert body["contractor_profit_amount"] == "1437.02"
    assert body["grand_total"] == "15807.21"


def test_boq_line_has_null_amount_when_unpriced(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    estimation = client.post(f"/projects/{project['id']}/estimations", json={"name": "Est 1"}).json()
    cost_head = client.post(
        f"/estimations/{estimation['id']}/cost-heads",
        json={"name": "Unpriced", "calculation_type": "area", "raw_unit": "SFT", "billing_unit": "SFT"},
    ).json()
    client.post(
        f"/cost-heads/{cost_head['id']}/measurement-entries",
        json={"description": "row", "length": "10", "width": "10", "nos": "1"},
    )

    response = client.get(f"/estimations/{estimation['id']}/boq")

    assert response.status_code == 200
    assert response.json()["lines"][0]["amount"] is None
    assert response.json()["subtotal"] == "0.00"
