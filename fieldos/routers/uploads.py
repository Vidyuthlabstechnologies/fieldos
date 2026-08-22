"""Authenticated serving of locally-stored uploads.

Uploads are construction drawings, site photos, inspection evidence and
commercial documents -- they must never be served by an unauthenticated
StaticFiles mount. Downloads go through the same bearer-token auth as every
other endpoint (plus ?token= because <img>/<a> tags cannot set headers --
same precedent as the WebSocket route), and every key is resolved against a
DB row so authorization follows the existing project/company model.

A 404 is returned both when the row is missing AND when the requester lacks
access, so responses never reveal whether an unauthorized file exists.
"""

import logging

from fastapi import APIRouter, Depends, Header, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from fieldos.auth import verify_token
from fieldos.db import get_db
from fieldos.models import Document, Inspection, InspectionPhoto, MaterialEntry, MaterialPhoto
from fieldos.permissions import require_project_access
from fieldos.storage import resolve_stored_path

logger = logging.getLogger(__name__)

router = APIRouter(tags=["uploads"])


@router.get("/uploads/{key:path}")
def download_upload(
    key: str,
    token: str | None = None,
    authorization: str | None = Header(default=None),
    db: Session = Depends(get_db),
):
    # Bearer header first; fall back to the query param used by <img> tags.
    if token:
        user = verify_token(token, db)
    elif authorization and authorization.startswith("Bearer "):
        user = verify_token(authorization.removeprefix("Bearer ").strip(), db)
    else:
        raise HTTPException(status_code=401, detail="Missing bearer token")

    path = resolve_stored_path(key)
    if not path.is_file():
        logger.warning("Upload key %r resolves to a missing file", key)

    # Stored names are uuid-suffixed and unique per upload, so matching on
    # the final path component handles both the current relative-key layout
    # and pre-existing rows that hold absolute paths / bare "/uploads/{f}".
    fname = key.rsplit("/", 1)[-1]

    doc = db.query(Document).filter(Document.file_path.endswith(fname)).first()
    if doc is not None:
        _require_access_or_404(db, doc.project_id, user.id)
        return _file_response(path, download_name=doc.name)

    url_suffix = "/" + fname
    photo = db.query(InspectionPhoto).filter(InspectionPhoto.photo_url.endswith(url_suffix)).first()
    if photo is not None:
        inspection = db.get(Inspection, photo.inspection_id)
        if inspection is not None:
            _require_access_or_404(db, inspection.project_id, user.id)
            return _file_response(path)

    material_photo = (
        db.query(MaterialPhoto).filter(MaterialPhoto.photo_url.endswith(url_suffix)).first()
    )
    if material_photo is not None:
        entry = db.get(MaterialEntry, material_photo.material_entry_id)
        if entry is not None:
            _require_access_or_404(db, entry.project_id, user.id)
            return _file_response(path)

    raise HTTPException(status_code=404, detail="Not found")


def _require_access_or_404(db: Session, project_id: str, user_id: str) -> None:
    # require_project_access raises 403 for an authenticated-but-unrelated
    # user -- that leaks "this file exists, you're just not allowed to see
    # it". This module's whole design goal (see docstring) is that an
    # authorized and an unauthorized-but-existing request are indistinguishable,
    # so translate 403 (and anything else project-access raises) into 404 here.
    try:
        require_project_access(db, project_id, user_id)
    except HTTPException as exc:
        raise HTTPException(status_code=404, detail="Not found") from exc


def _file_response(path, download_name: str | None = None):
    if not path.is_file():
        raise HTTPException(status_code=404, detail="File missing from local storage")
    if download_name:
        return FileResponse(path, filename=download_name)
    return FileResponse(path)
