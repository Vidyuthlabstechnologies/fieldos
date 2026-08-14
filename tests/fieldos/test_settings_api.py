from tests.fieldos.conftest import build_client


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
    client = build_client(db_session, user_id="owner-1")

    response = client.put("/settings/sarvam", json={"api_key": "sk_real_key_123"})

    assert response.status_code == 200
    assert response.json() == {"configured": True}
    assert client.get("/settings/sarvam").json() == {"configured": True}


def test_set_sarvam_key_never_echoes_the_key_value(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = build_client(db_session, user_id="owner-1")

    response = client.put("/settings/sarvam", json={"api_key": "sk_super_secret"})

    assert "sk_super_secret" not in response.text


def test_set_sarvam_key_can_be_updated(db_session, monkeypatch):
    from fieldos import sarvam
    from fieldos.models import AppSetting

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = build_client(db_session, user_id="owner-1")

    client.put("/settings/sarvam", json={"api_key": "sk_first"})
    client.put("/settings/sarvam", json={"api_key": "sk_second"})

    row = db_session.get(AppSetting, sarvam.SETTING_KEY)
    assert row.value == "sk_second"


def test_clear_sarvam_key_removes_the_db_setting_but_env_fallback_still_applies(db_session, monkeypatch):
    from fieldos import sarvam

    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "env-fallback-key")
    client = build_client(db_session, user_id="owner-1")
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
