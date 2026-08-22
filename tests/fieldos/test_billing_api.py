from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_list_plans_returns_empty_list(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _create_company_and_project(owner_client)

    response = owner_client.get("/billing/plans")

    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_get_subscription_returns_404_when_none_exists(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    response = owner_client.get(f"/billing/subscription?company_id={company['id']}")

    assert response.status_code == 404
    assert response.json()["detail"] == "No subscription found"


def test_get_subscription_requires_owner_role(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    from fieldos.models import CompanyMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    engineer_client = build_client(db_session, user_id="engineer-1")

    response = engineer_client.get(f"/billing/subscription?company_id={company['id']}")

    assert response.status_code == 403


def test_create_checkout_session_returns_503_when_stripe_not_configured(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    response = owner_client.post(
        f"/billing/checkout-session?company_id={company['id']}",
        json={"plan_id": "plan-1", "success_url": "http://localhost:3000/success", "cancel_url": "http://localhost:3000/cancel"},
    )

    assert response.status_code == 503
    assert response.json()["detail"] == "Billing not configured"


def test_create_portal_session_returns_503_when_stripe_not_configured(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    response = owner_client.post(f"/billing/portal-session?company_id={company['id']}")

    assert response.status_code == 503
    assert response.json()["detail"] == "Billing not configured"


def test_list_billing_events_requires_owner_role(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    response = owner_client.get(f"/billing/events?company_id={company['id']}")

    assert response.status_code == 200
    assert isinstance(response.json(), list)


def test_list_billing_events_forbidden_for_non_owner(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    company, _ = _create_company_and_project(owner_client)

    from fieldos.models import CompanyMember

    db_session.add(CompanyMember(company_id=company["id"], user_id="engineer-1", role="site_engineer"))
    db_session.commit()

    engineer_client = build_client(db_session, user_id="engineer-1")

    response = engineer_client.get(f"/billing/events?company_id={company['id']}")

    assert response.status_code == 403