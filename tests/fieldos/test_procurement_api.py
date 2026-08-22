from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_create_vendor_as_owner(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/companies/{company['id']}/vendors",
        json={"name": "ABC Cement Suppliers", "contact_person": "Ramesh", "phone": "9876543210", "category": "cement"},
    )

    assert response.status_code == 201
    vendor = response.json()
    assert vendor["name"] == "ABC Cement Suppliers"
    assert vendor["company_id"] == company["id"]


def test_list_vendors_as_site_engineer_regression(db_session):
    """Regression test: list_vendors used to call require_project_access(db,
    company_id, ...), which looks up the Project table with a company_id --
    wrong table, so this would 404/403 on every real install. Also confirms
    create_vendor works for an owner (it used to always 404 too, via a dead
    get_project_or_404(db, company_id) call before the real check)."""
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    create_resp = owner_client.post(
        f"/companies/{company['id']}/vendors",
        json={"name": "Steel Traders Co"},
    )
    assert create_resp.status_code == 201

    from fieldos.models import CompanyMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    engineer_client = build_client(db_session, user_id="engineer-1")
    response = engineer_client.get(f"/companies/{company['id']}/vendors")

    assert response.status_code == 200
    vendors = response.json()
    assert len(vendors) == 1
    assert vendors[0]["name"] == "Steel Traders Co"


def test_create_requisition(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/projects/{project['id']}/requisitions",
        json={"item_name": "OPC 53 Cement", "quantity": "50", "unit": "bag", "urgency": "high"},
    )

    assert response.status_code == 201
    req = response.json()
    assert req["item_name"] == "OPC 53 Cement"
    assert req["status"] == "pending"
    assert req["urgency"] == "high"


def test_approve_requisition_requires_owner_or_pm(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    req = owner_client.post(
        f"/projects/{project['id']}/requisitions",
        json={"item_name": "Sand", "quantity": "100", "unit": "cft"},
    ).json()

    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.add(ProjectMember(project_id=project["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()
    engineer_client = build_client(db_session, user_id="engineer-1")

    denied = engineer_client.patch(f"/projects/{project['id']}/requisitions/{req['id']}/approve")
    assert denied.status_code == 403

    allowed = owner_client.patch(f"/projects/{project['id']}/requisitions/{req['id']}/approve")
    assert allowed.status_code == 200
    assert allowed.json()["status"] == "approved"
    assert allowed.json()["approved_by"] == "owner-1"


def test_full_procurement_chain(db_session):
    """RFQ -> Quote -> PO -> GRN, end to end."""
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    vendor = owner_client.post(
        f"/companies/{company['id']}/vendors", json={"name": "Cement Vendor"}
    ).json()

    rfq = owner_client.post(
        f"/projects/{project['id']}/rfqs",
        json={"title": "Cement Supply Q1"},
    ).json()
    assert rfq["title"] == "Cement Supply Q1"
    assert rfq["status"] == "open"

    rfq_list = owner_client.get(f"/projects/{project['id']}/rfqs")
    assert rfq_list.status_code == 200
    assert len(rfq_list.json()) == 1

    quote = owner_client.post(
        f"/rfqs/{rfq['id']}/quotes",
        json={"vendor_id": vendor["id"], "total_amount": "50000.00", "delivery_days": 7},
    ).json()
    assert quote["vendor_id"] == vendor["id"]
    assert quote["total_amount"] == "50000.00"

    quote_list = owner_client.get(f"/rfqs/{rfq['id']}/quotes")
    assert quote_list.status_code == 200
    assert len(quote_list.json()) == 1

    po = owner_client.post(
        f"/projects/{project['id']}/purchase-orders",
        json={"vendor_id": vendor["id"], "po_number": "PO-2025-001", "total_amount": "50000.00", "quote_id": quote["id"]},
    ).json()
    assert po["po_number"] == "PO-2025-001"

    po_list = owner_client.get(f"/projects/{project['id']}/purchase-orders")
    assert po_list.status_code == 200
    assert len(po_list.json()) == 1

    grn = owner_client.post(
        f"/purchase-orders/{po['id']}/grn",
        json={
            "received_date": "2025-01-20",
            "item_description": "OPC 53 Cement - 50 bags",
            "ordered_qty": "50",
            "received_qty": "50",
            "unit": "bag",
            "condition": "good",
        },
    ).json()
    assert grn["item_description"] == "OPC 53 Cement - 50 bags"

    grn_list = owner_client.get(f"/purchase-orders/{po['id']}/grn")
    assert grn_list.status_code == 200
    assert len(grn_list.json()) == 1


def test_create_purchase_order_requires_owner_or_pm(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, project = _create_company_and_project(owner_client)

    vendor = owner_client.post(f"/companies/{company['id']}/vendors", json={"name": "Vendor A"}).json()

    from fieldos.models import CompanyMember, ProjectMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.add(ProjectMember(project_id=project["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()
    engineer_client = build_client(db_session, user_id="engineer-1")

    denied = engineer_client.post(
        f"/projects/{project['id']}/purchase-orders",
        json={"vendor_id": vendor["id"], "po_number": "PO-001", "total_amount": "1000.00"},
    )
    assert denied.status_code == 403
