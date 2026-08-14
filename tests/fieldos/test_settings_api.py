from tests.fieldos.conftest import build_client


def _make_owner_client(db_session, user_id="owner-1"):
    """Writing to /settings/sarvam requires owning at least one company --
    build a client for a user who actually does."""
    client = build_client(db_session, user_id=user_id)
    client.post("/companies", json={"name": "Test Co"})
    return client


def test_sarvam_status_is_not_configured_by_default(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = build_client(db_session, user_id="owner-1")

    response = client.get("/settings/sarvam")

    assert response.status_code == 200
    assert response.json() == {"configured": False}


def test_set_sarvam_key_marks_it_configured(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = _make_owner_client(db_session)

    response = client.put("/settings/sarvam", json={"api_key": "sk_real_key_123"})

    assert response.status_code == 200
    assert response.json() == {"configured": True}
    assert client.get("/settings/sarvam").json() == {"configured": True}


def test_set_sarvam_key_never_echoes_the_key_value(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = _make_owner_client(db_session)

    response = client.put("/settings/sarvam", json={"api_key": "sk_super_secret"})

    assert "sk_super_secret" not in response.text


def test_set_sarvam_key_can_be_updated(db_session, monkeypatch):
    from fieldos import sarvam
    from fieldos.models import AppSetting

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = _make_owner_client(db_session)

    client.put("/settings/sarvam", json={"api_key": "sk_first"})
    client.put("/settings/sarvam", json={"api_key": "sk_second"})

    row = db_session.get(AppSetting, sarvam.SETTING_KEY)
    assert row.value == "sk_second"


def test_clear_sarvam_key_removes_the_db_setting_but_env_fallback_still_applies(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "env-fallback-key")
    client = _make_owner_client(db_session)
    client.put("/settings/sarvam", json={"api_key": "sk_db_key"})

    response = client.delete("/settings/sarvam")

    assert response.status_code == 200
    # env var is still set in this test, so it's still "configured" -- just
    # via the fallback, not the DB override that was just cleared.
    assert response.json() == {"configured": True}
    assert sarvam.get_effective_api_key(db_session) == "env-fallback-key"


def test_sarvam_endpoints_require_authentication(db_session):
    from fastapi.testclient import TestClient

    from fieldos.app import create_fieldos_app
    from fieldos.db import get_db

    app = create_fieldos_app()
    app.dependency_overrides[get_db] = lambda: db_session
    client = TestClient(app)

    response = client.get("/settings/sarvam")

    assert response.status_code == 401


def test_set_sarvam_key_denies_a_user_who_owns_no_company(db_session):
    # The vulnerability this guards against: a freshly self-registered user
    # with zero company memberships must not be able to overwrite the one
    # shared credential every company's voice-to-DPR feature reads from.
    client = build_client(db_session, user_id="no-company-user")

    response = client.put("/settings/sarvam", json={"api_key": "sk_attacker_key"})

    assert response.status_code == 403


def test_clear_sarvam_key_denies_a_user_who_owns_no_company(db_session):
    client = build_client(db_session, user_id="no-company-user")

    response = client.delete("/settings/sarvam")

    assert response.status_code == 403


def test_set_sarvam_key_denies_a_non_owner_company_member(db_session):
    from fieldos.models import CompanyMember

    owner_client = _make_owner_client(db_session, user_id="owner-1")
    company_id = owner_client.get("/companies/mine").json()[0]["id"]
    db_session.add(CompanyMember(company_id=company_id, user_id="site-eng-1", role="site_engineer"))
    db_session.commit()

    site_engineer_client = build_client(db_session, user_id="site-eng-1")
    response = site_engineer_client.put("/settings/sarvam", json={"api_key": "sk_attacker_key"})

    assert response.status_code == 403


def test_get_sarvam_status_does_not_require_owner_role(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = build_client(db_session, user_id="no-company-user")

    response = client.get("/settings/sarvam")

    assert response.status_code == 200
