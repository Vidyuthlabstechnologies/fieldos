"""Tests for Stripe webhook hardening (P1).

Missing secret -> 503; bad signature / malformed payload -> generic 400 with
no internals leaked; duplicate event -> idempotent no-op. Valid-event
processing is covered by the existing test_billing_api.py suite.
"""

import hashlib
import hmac
import json
import time

import pytest

from fieldos.routers import billing as billing_module


def _sign(payload: bytes, secret: str, timestamp: int | None = None) -> str:
    ts = timestamp if timestamp is not None else int(time.time())
    signed_payload = f"{ts}.".encode() + payload
    sig = hmac.new(secret.encode(), signed_payload, hashlib.sha256).hexdigest()
    return f"t={ts},v1={sig}"


@pytest.fixture()
def webhook_env(monkeypatch):
    monkeypatch.setattr(billing_module, "STRIPE_SECRET_KEY", "sk_test_dummy")
    monkeypatch.setenv("STRIPE_WEBHOOK_SECRET", "whsec_test_dummy")
    # The handler reads the secret via os.getenv at request time.
    return "whsec_test_dummy"


def _post(client, payload: dict | bytes, header: str | None):
    body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
    headers = {"stripe-signature": header} if header else {}
    return client.post("/billing/webhook", content=body, headers=headers)


def test_missing_webhook_secret_returns_503(db_session, monkeypatch):
    from tests.fieldos.conftest import build_client

    monkeypatch.setattr(billing_module, "STRIPE_SECRET_KEY", None)
    monkeypatch.delenv("STRIPE_WEBHOOK_SECRET", raising=False)

    client = build_client(db_session)
    resp = _post(client, {"type": "checkout.session.completed"}, "t=1,v1=abc")
    assert resp.status_code == 503
    assert resp.json()["detail"] == "Billing not configured"


def test_invalid_signature_returns_generic_400(db_session, webhook_env):
    from tests.fieldos.conftest import build_client

    client = build_client(db_session)
    resp = _post(
        client,
        b'{"type": "checkout.session.completed"}',
        _sign(b'{"type": "checkout.session.completed"}', "whsec_wrong_secret"),
    )
    assert resp.status_code == 400
    detail = resp.json()["detail"]
    assert detail == "Invalid signature"
    # No verifier internals or exception text leak.
    assert "whsec" not in detail and "Error" not in detail


def test_malformed_payload_returns_generic_400(db_session, webhook_env):
    from tests.fieldos.conftest import build_client

    client = build_client(db_session)
    garbage = b"{not-json"
    resp = _post(client, garbage, _sign(garbage, webhook_env))
    assert resp.status_code == 400
    assert resp.json()["detail"] in ("Invalid signature", "Invalid webhook payload")


def test_missing_signature_header_returns_400(db_session, webhook_env):
    from tests.fieldos.conftest import build_client

    client = build_client(db_session)
    resp = _post(client, {"type": "invoice.payment_failed"}, None)
    assert resp.status_code == 400


def test_duplicate_event_is_idempotent(db_session, webhook_env):
    """A replayed event must be a no-op the second time (single BillingEvent row)."""
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    from sqlalchemy.pool import StaticPool

    import fieldos.models  # noqa: F401
    from fieldos.db import Base
    from fieldos.app import create_fieldos_app
    from fieldos.db import get_db

    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

    app = create_fieldos_app()

    def override_get_db():
        session = SessionLocal()
        try:
            yield session
        finally:
            session.close()

    # Real token auth isn't needed for the unauthenticated webhook.
    from fastapi.testclient import TestClient

    client = TestClient(app)
    app.dependency_overrides[get_db] = override_get_db

    payload = {
        "id": "evt_test_123",
        "type": "invoice.payment_failed",
        "data": {"object": {"customer": "cus_unknown", "amount": 1000}},
    }
    body = json.dumps(payload).encode()
    header = _sign(body, webhook_env)

    r1 = client.post("/billing/webhook", content=body, headers={"stripe-signature": header})
    r2 = client.post("/billing/webhook", content=body, headers={"stripe-signature": header})
    assert r1.status_code == 200
    assert r2.status_code == 200

    with SessionLocal() as check:
        rows = check.query(billing_module.BillingEvent).all()
        assert len(rows) == 1
