from fieldos import sarvam
from tests.fieldos.conftest import build_client


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post("/projects", json={"company_id": company["id"], "name": "Test Project"}).json()
    return company, project


def test_create_manual_dpr_entry_is_confirmed_immediately(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(
        f"/projects/{project['id']}/dpr",
        json={
            "entry_date": "2026-08-11",
            "work_summary": "Poured 50 cum concrete on footing F12",
            "manpower_count": 8,
        },
    )

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "confirmed"
    assert body["source"] == "manual"


def test_list_dpr_entries_orders_newest_first(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-10", "work_summary": "Day 1", "manpower_count": 5},
    )
    client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Day 2", "manpower_count": 6},
    )

    response = client.get(f"/projects/{project['id']}/dpr")

    assert response.status_code == 200
    dates = [e["entry_date"] for e in response.json()]
    assert dates == ["2026-08-11", "2026-08-10"]


def test_add_photo_to_dpr_entry(db_session):
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)
    entry = client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Steel fixing", "manpower_count": 4},
    ).json()

    response = client.post(
        f"/projects/{project['id']}/dpr/{entry['id']}/photos",
        json={"photo_url": "https://storage.example.com/photo1.jpg", "caption": "Column C4"},
    )

    assert response.status_code == 201
    assert response.json()["caption"] == "Column C4"


def test_dpr_denies_non_project_member(db_session):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    stranger_client = build_client(db_session, user_id="stranger-1")
    response = stranger_client.post(
        f"/projects/{project['id']}/dpr",
        json={"entry_date": "2026-08-11", "work_summary": "Should fail", "manpower_count": 1},
    )

    assert response.status_code == 403


def test_voice_draft_returns_503_when_sarvam_not_configured(db_session, monkeypatch):
    monkeypatch.setattr(sarvam.settings, "sarvam_api_key", "")
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(
        f"/projects/{project['id']}/dpr/voice-draft",
        files={"audio": ("recording.webm", b"fake audio bytes", "audio/webm")},
    )

    assert response.status_code == 503


def test_voice_draft_returns_a_structured_draft_without_saving_anything(db_session, monkeypatch):
    monkeypatch.setattr(sarvam, "transcribe_audio", lambda *a, **k: "poured column footings with 12 workers")
    monkeypatch.setattr(
        sarvam,
        "structure_dpr_from_transcript",
        lambda transcript: {"work_summary": "Poured column footings", "manpower_count": 12, "weather": None},
    )
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(
        f"/projects/{project['id']}/dpr/voice-draft",
        files={"audio": ("recording.webm", b"fake audio bytes", "audio/webm")},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["work_summary"] == "Poured column footings"
    assert body["manpower_count"] == 12
    assert body["transcript"] == "poured column footings with 12 workers"

    # Nothing was actually saved -- it's a draft.
    entries = client.get(f"/projects/{project['id']}/dpr").json()
    assert entries == []


def test_voice_draft_returns_422_when_no_speech_detected(db_session, monkeypatch):
    # Real Sarvam behavior: an empty transcript (silence/background noise)
    # sent on to the chat completions endpoint gets rejected with a 400 from
    # Sarvam -- surface a clear, actionable error instead of a bare 502.
    monkeypatch.setattr(sarvam, "transcribe_audio", lambda *a, **k: "   ")
    client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(client)

    response = client.post(
        f"/projects/{project['id']}/dpr/voice-draft",
        files={"audio": ("recording.webm", b"fake audio bytes", "audio/webm")},
    )

    assert response.status_code == 422
    assert "no speech" in response.json()["detail"].lower()


def test_voice_draft_denies_non_project_member(db_session, monkeypatch):
    monkeypatch.setattr(sarvam, "transcribe_audio", lambda *a, **k: "irrelevant")
    monkeypatch.setattr(
        sarvam, "structure_dpr_from_transcript", lambda t: {"work_summary": t, "manpower_count": 0, "weather": None}
    )
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    stranger_client = build_client(db_session, user_id="stranger-1")
    response = stranger_client.post(
        f"/projects/{project['id']}/dpr/voice-draft",
        files={"audio": ("recording.webm", b"fake audio bytes", "audio/webm")},
    )

    assert response.status_code == 403
