from tests.fieldos.conftest import build_client


def test_create_company_makes_creator_the_owner(db_session):
    client = build_client(db_session, user_id="owner-1")

    response = client.post("/companies", json={"name": "Bhavya Developers"})

    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Bhavya Developers"

    from fieldos.models import CompanyMember

    membership = db_session.query(CompanyMember).filter_by(company_id=body["id"]).one()
    assert membership.user_id == "owner-1"
    assert membership.role == "owner"


def test_list_my_companies_returns_only_companies_the_user_belongs_to(db_session):
    client_a = build_client(db_session, user_id="owner-a")
    client_b = build_client(db_session, user_id="owner-b")

    client_a.post("/companies", json={"name": "Company A"})
    client_b.post("/companies", json={"name": "Company B"})

    response = client_a.get("/companies/mine")

    assert response.status_code == 200
    names = [c["name"] for c in response.json()]
    assert names == ["Company A"]
