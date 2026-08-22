from tests.fieldos.test_auth_api import build_real_auth_client


def _register_owner_with_project(client):
    """The websocket route authenticates via a real session token looked up
    directly in the sessions table (not the get_current_user override used
    elsewhere), so this needs the real register/login flow, not build_client."""
    auth = client.post(
        "/auth/register", json={"username": "owner1", "name": "Owner One", "password": "password123"}
    ).json()
    token = auth["token"]
    headers = {"Authorization": f"Bearer {token}"}

    company = client.post("/companies", json={"name": "Test Co"}, headers=headers).json()
    project = client.post(
        "/projects", json={"company_id": company["id"], "name": "Test Project"}, headers=headers
    ).json()
    return project, token


def test_valid_token_connects_successfully(db_session):
    client = build_real_auth_client(db_session)
    project, token = _register_owner_with_project(client)

    with client.websocket_connect(f"/projects/{project['id']}/ws?token={token}") as ws:
        # Connection succeeded (accept() was called) -- send a message and
        # confirm the server doesn't immediately close on us.
        ws.send_text('{"type": "ping", "payload": {}}')
        # No assertion on a reply: broadcast() excludes the sender, so a
        # lone connection sending to itself receives nothing back -- the
        # real assertion is that the `with` block didn't raise on connect.


def test_invalid_token_is_rejected(db_session):
    client = build_real_auth_client(db_session)
    project, _ = _register_owner_with_project(client)

    from starlette.websockets import WebSocketDisconnect

    try:
        with client.websocket_connect(f"/projects/{project['id']}/ws?token=not-a-real-token") as ws:
            ws.receive_text()
        assert False, "expected the connection to be rejected"
    except WebSocketDisconnect as exc:
        assert exc.code == 4001


def test_missing_project_access_is_rejected(db_session):
    """A second, real user with no membership in the project should be
    closed with 4003 (added as part of the HTTPException-after-accept fix)."""
    client = build_real_auth_client(db_session)
    project, _ = _register_owner_with_project(client)

    other_auth = client.post(
        "/auth/register", json={"username": "outsider", "name": "Outsider", "password": "password123"}
    ).json()

    from starlette.websockets import WebSocketDisconnect

    try:
        with client.websocket_connect(f"/projects/{project['id']}/ws?token={other_auth['token']}") as ws:
            ws.receive_text()
        assert False, "expected the connection to be rejected"
    except WebSocketDisconnect as exc:
        assert exc.code == 4003
