from fastapi.testclient import TestClient

from fieldos.app import create_fieldos_app
from fieldos.db import get_db


def build_real_auth_client(db_session):
    """Unlike tests/fieldos/conftest.py's build_client, this does NOT stub out
    get_current_user -- these tests exercise the real register/login/session flow."""
    app = create_fieldos_app()

    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    return TestClient(app)


def test_register_creates_user_and_returns_a_working_session_token(db_session):
    client = build_real_auth_client(db_session)

    response = client.post(
        "/auth/register", json={"username": "site.eng1", "name": "Ravi Kumar", "password": "password123"}
    )

    assert response.status_code == 201
    body = response.json()
    assert body["user"]["username"] == "site.eng1"
    assert body["token"]

    me = client.get("/auth/me", headers={"Authorization": f"Bearer {body['token']}"})
    assert me.status_code == 200
    assert me.json()["username"] == "site.eng1"


def test_register_rejects_duplicate_username(db_session):
    client = build_real_auth_client(db_session)
    client.post("/auth/register", json={"username": "dupe", "name": "A", "password": "password123"})

    response = client.post("/auth/register", json={"username": "dupe", "name": "B", "password": "password456"})

    assert response.status_code == 409


def test_register_race_loser_gets_409_not_500(db_session, monkeypatch):
    """Regression test for a real bug found under concurrent load: two
    requests can both pass the existence check before either commits (10
    simultaneous registrations of the same username produced 1x 201 + 9x
    raw 500s before this fix -- see fieldos/routers/auth.py's IntegrityError
    handling). Simulates "lost the race" deterministically, without real
    threading, by inserting the colliding row between the check and the
    flush -- the exact interleaving a real race produces."""
    import fieldos.routers.auth as auth_router
    from fieldos.auth import hash_password
    from fieldos.models import User

    client = build_real_auth_client(db_session)
    real_flush = db_session.flush

    def flush_after_inserting_the_racing_winner(*args, **kwargs):
        # A concurrent request "wins" and commits first, right before this
        # request's own flush -- the check-then-insert race window.
        db_session.add(User(username="race-target", name="Winner", password_hash=hash_password("password123")))
        db_session.flush = real_flush
        return real_flush(*args, **kwargs)

    monkeypatch.setattr(db_session, "flush", flush_after_inserting_the_racing_winner)

    response = client.post(
        "/auth/register", json={"username": "race-target", "name": "Loser", "password": "password123"}
    )

    assert response.status_code == 409
    assert response.json()["detail"] == "Username already taken"


def test_register_rejects_short_password(db_session):
    client = build_real_auth_client(db_session)

    response = client.post("/auth/register", json={"username": "shortpw", "name": "A", "password": "short"})

    assert response.status_code == 422


def test_login_with_correct_password_succeeds(db_session):
    client = build_real_auth_client(db_session)
    client.post("/auth/register", json={"username": "site.eng2", "name": "A", "password": "password123"})

    response = client.post("/auth/login", json={"username": "site.eng2", "password": "password123"})

    assert response.status_code == 200
    assert response.json()["token"]


def test_login_with_wrong_password_fails(db_session):
    client = build_real_auth_client(db_session)
    client.post("/auth/register", json={"username": "site.eng3", "name": "A", "password": "password123"})

    response = client.post("/auth/login", json={"username": "site.eng3", "password": "wrong-password"})

    assert response.status_code == 401


def test_login_with_unknown_username_fails(db_session):
    client = build_real_auth_client(db_session)

    response = client.post("/auth/login", json={"username": "nobody", "password": "password123"})

    assert response.status_code == 401


def test_me_without_a_token_is_rejected(db_session):
    client = build_real_auth_client(db_session)

    response = client.get("/auth/me")

    assert response.status_code == 401


def test_me_with_bogus_token_is_rejected(db_session):
    client = build_real_auth_client(db_session)

    response = client.get("/auth/me", headers={"Authorization": "Bearer not-a-real-token"})

    assert response.status_code == 401
