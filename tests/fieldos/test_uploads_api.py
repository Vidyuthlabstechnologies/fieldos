"""Tests for the authenticated upload/download system (P0 fix).

Covers: authenticated download, unauthenticated rejection, authorization
(404-masking), traversal rejection, collision-proof stored names, size cap,
MIME/extension allowlist, empty-file rejection.
"""

from pathlib import Path

import pytest

from fieldos.models import CompanyMember, ProjectMember, Session as SessionModel, User
from fieldos.storage import resolve_stored_path
from fieldos import storage as storage_module
from tests.fieldos.conftest import build_client


@pytest.fixture()
def isolated_uploads(tmp_path, monkeypatch):
    """Point the storage layer at a throwaway dir instead of the real app-data."""
    monkeypatch.setattr(storage_module, "uploads_dir", lambda: tmp_path)
    return tmp_path


def _create_company_and_project(client):
    company = client.post("/companies", json={"name": "Test Co"}).json()
    project = client.post(
        "/projects", json={"company_id": company["id"], "name": "Test Project"}
    ).json()
    return company, project


def _make_session(db_session, user_id: str, token: str) -> None:
    db_session.add(User(id=user_id, username=user_id, name=user_id, password_hash="x"))
    db_session.add(
        SessionModel(
            token=token,
            user_id=user_id,
            expires_at=__import__("datetime").datetime.max.replace(tzinfo=None),
        )
    )
    db_session.commit()


def _grant_project_access(db_session, user_id: str, company_id: str, project_id: str) -> None:
    db_session.add(CompanyMember(company_id=company_id, user_id=user_id, role="owner"))
    db_session.add(ProjectMember(project_id=project_id, user_id=user_id, role="owner"))
    db_session.commit()


def _upload_document(client, project_id: str, name="plan.pdf", content=b"drawing bytes"):
    return client.post(
        f"/projects/{project_id}/documents?category=drawing",
        files={"file": (name, content, "application/pdf")},
    )


def test_upload_and_authenticated_download_roundtrip(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    resp = _upload_document(owner_client, project["id"], content=b"unique-bytes-123")
    assert resp.status_code == 201
    doc = resp.json()

    # Derive the storage key from the absolute file_path the DB records.
    root = isolated_uploads
    key = str(Path(doc["file_path"]).relative_to(root)).replace("\\", "/")

    _make_session(db_session, "reader-1", "reader-token")
    _grant_project_access(db_session, "reader-1", doc["project_id"], project["id"])
    reader = build_client(db_session, user_id="reader-1")

    dl = reader.get(
        f"/uploads/{key}", headers={"Authorization": "Bearer reader-token"}
    )
    assert dl.status_code == 200
    assert dl.content == b"unique-bytes-123"
    # Original filename preserved as metadata (download name), not on disk.
    assert "plan.pdf" in dl.headers.get("content-disposition", "")
    stored_name = Path(doc["file_path"]).name
    assert stored_name != "plan.pdf"


def test_download_without_token_is_401(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)
    resp = _upload_document(owner_client, project["id"])
    doc = resp.json()
    key = str(Path(doc["file_path"]).relative_to(isolated_uploads)).replace("\\", "/")

    anon = build_client(db_session, user_id="owner-1")
    dl = anon.get(f"/uploads/{key}")
    assert dl.status_code == 401


def test_download_by_unauthorized_user_masks_as_404(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)
    resp = _upload_document(owner_client, project["id"])
    doc = resp.json()
    key = str(Path(doc["file_path"]).relative_to(isolated_uploads)).replace("\\", "/")

    # Valid session, but this user belongs to NO company/project.
    _make_session(db_session, "outsider-1", "outsider-token")
    outsider = build_client(db_session, user_id="outsider-1")
    dl = outsider.get(f"/uploads/{key}", headers={"Authorization": "Bearer outsider-token"})
    assert dl.status_code == 404


def test_unknown_key_returns_404(db_session, isolated_uploads):
    _make_session(db_session, "reader-1", "reader-token")
    reader = build_client(db_session, user_id="reader-1")
    dl = reader.get("/uploads/documents/nope/missing.pdf", headers={"Authorization": "Bearer reader-token"})
    assert dl.status_code == 404


def test_path_traversal_rejected_at_resolution():
    for bad in ["../secret.txt", "a/../../secret.txt", "..\\..\\secret.txt", "/etc/passwd", ""]:
        with pytest.raises(Exception) as excinfo:
            resolve_stored_path(bad)
        assert getattr(excinfo.value, "status_code", None) == 404


def test_traversal_over_http_returns_404_not_file(db_session, isolated_uploads):
    _make_session(db_session, "reader-1", "reader-token")
    reader = build_client(db_session, user_id="reader-1")
    # Encoded .. segments survive routing and hit the resolver directly.
    dl = reader.get(
        "/uploads/..%2F..%2Ffieldos_dev.db",
        headers={"Authorization": "Bearer reader-token"},
    )
    assert dl.status_code in (404,)


def test_duplicate_filenames_get_distinct_stored_files(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    # _upload_document always sends content_type="application/pdf" -- use a
    # .pdf filename so this stays a test of version-increment-on-duplicate-
    # filename, not an incidental MIME/extension-mismatch rejection (that's
    # covered separately by test_extension_mime_mismatch_rejected).
    r1 = _upload_document(owner_client, project["id"], name="boq.pdf", content=b"version one")
    r2 = _upload_document(owner_client, project["id"], name="boq.pdf", content=b"version two")
    d1, d2 = r1.json(), r2.json()

    assert d1["version"] == 1
    assert d2["version"] == 2
    assert d1["file_path"] != d2["file_path"]
    assert Path(d1["file_path"]).read_bytes() == b"version one"
    assert Path(d2["file_path"]).read_bytes() == b"version two"


def test_oversized_upload_rejected_with_413(db_session, isolated_uploads, monkeypatch):
    from fieldos.config import settings

    monkeypatch.setattr(settings, "max_upload_mb", 1)

    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    big_pdf = b"x" * (1024 * 1024 + 100)
    resp = _upload_document(owner_client, project["id"], content=big_pdf)
    assert resp.status_code == 413


def test_unsupported_mime_rejected_with_415(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    resp = owner_client.post(
        f"/projects/{project['id']}/documents",
        files={"file": ("payload.bin", b"\x00\x01\x02", "application/octet-stream")},
    )
    assert resp.status_code == 415


def test_extension_mime_mismatch_rejected(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    resp = owner_client.post(
        f"/projects/{project['id']}/documents",
        files={"file": ("report.pdf", b"not really", "image/png")},
    )
    assert resp.status_code == 415


def test_empty_file_rejected(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)

    resp = _upload_document(owner_client, project["id"], content=b"")
    assert resp.status_code == 422


def test_material_photo_upload_uses_central_storage(db_session, isolated_uploads):
    owner_client = build_client(db_session, user_id="owner-1")
    _, project = _create_company_and_project(owner_client)
    entry = owner_client.post(
        f"/projects/{project['id']}/materials",
        json={
            "entry_date": "2026-08-22",
            "item_name": "Cement",
            "category": "cement",
            "quantity": "50",
            "unit": "bags",
        },
    ).json()

    resp = owner_client.post(
        f"/projects/{project['id']}/materials/{entry['id']}/photos",
        files={"file": ("site.jpg", b"\xff\xd8\xff\xe0jpegdata", "image/jpeg")},
    )
    assert resp.status_code == 201
    photo = resp.json()
    assert photo["photo_url"].startswith("/uploads/materials/")
    # Stored under the app-data root we isolated -- never the repo CWD.
    stored = isolated_uploads / "materials"
    assert any(p.read_bytes() == b"\xff\xd8\xff\xe0jpegdata" for p in stored.iterdir())
