"""Centralized local file storage for uploads (documents, photos, evidence).

Extends fieldos.paths (which owns *where* files live: the OS app-data dir,
so the PyInstaller-packaged desktop app works regardless of CWD) with the
rules for *what* may be stored and *how*:

- Size cap and MIME/extension allowlist, enforced centrally so no router
  can forget them. Client Content-Type alone is not trusted blindly: it must
  be allowlisted AND agree with the filename extension. There is deliberately
  no magic-byte sniffing -- that needs a native dependency (libmagic) which
  would complicate offline PyInstaller packaging for marginal gain on a
  loopback-only, authenticated API.
- Collision-proof stored names: uuid4 hex + a canonical extension derived
  from the allowlist mapping. The user-supplied filename is preserved ONLY
  as database metadata and is never part of a filesystem path.
- Traversal safety on both write and read: every path that crosses the
  trust boundary is resolved and verified to stay inside the uploads root.
"""

import uuid
from pathlib import Path
from urllib.parse import unquote

from fastapi import HTTPException, UploadFile

from fieldos.config import settings
from fieldos.paths import uploads_dir

# URL prefix stored in DB columns (photo_url / download links). Keys are
# relative POSIX-style paths under the uploads root, e.g.
# "documents/{project_id}/{uuid}.pdf" or "materials/{uuid}.jpg".
UPLOADS_URL_PREFIX = "/uploads"

DEFAULT_MAX_UPLOAD_MB = 25

IMAGE_MIME_EXTENSIONS: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}

DOCUMENT_MIME_EXTENSIONS: dict[str, str] = {
    **IMAGE_MIME_EXTENSIONS,  # site drawings/photos arrive as documents too
    "application/pdf": ".pdf",
    "text/plain": ".txt",
    "text/csv": ".csv",
    "application/json": ".json",
    "application/rtf": ".rtf",
    "application/msword": ".doc",
    "application/vnd.ms-excel": ".xls",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ".xlsx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation": ".pptx",
    # CAD deliverables are the everyday currency of a construction project.
    "application/acad": ".dwg",
    "image/vnd.dwg": ".dwg",
    "application/x-zip-compressed": ".zip",
    "application/zip": ".zip",
}


class UploadRejected(HTTPException):
    def __init__(self, status_code: int, detail: str) -> None:
        super().__init__(status_code=status_code, detail=detail)


def _max_upload_bytes() -> int:
    return settings.max_upload_mb * 1024 * 1024


def validate_upload(file: UploadFile, content: bytes, *, kind: str) -> str:
    """Check size/MIME/extension coherence. Returns the canonical extension."""
    if len(content) == 0:
        raise UploadRejected(422, "Empty files cannot be uploaded")
    if len(content) > _max_upload_bytes():
        raise UploadRejected(
            413,
            f"File exceeds the {settings.max_upload_mb} MB upload limit",
        )

    allowed = IMAGE_MIME_EXTENSIONS if kind == "image" else DOCUMENT_MIME_EXTENSIONS
    mime = (file.content_type or "").split(";")[0].strip().lower()
    ext = allowed.get(mime)
    if ext is None:
        raise UploadRejected(415, f"Unsupported file type: {mime or 'unknown'}")

    supplied_ext = Path(file.filename or "").suffix.lower()
    # ".jpeg" is accepted as an alias of the canonical ".jpg"; anything else
    # must agree with the MIME-derived extension.
    if supplied_ext and supplied_ext not in (ext, ".jpeg"):
        raise UploadRejected(415, f"File extension {supplied_ext!r} does not match content type {mime!r}")
    return ext


def save_upload(content: bytes, *, subdir: str, canonical_ext: str) -> tuple[str, Path]:
    """Store bytes under uploads_root/subdir with a collision-proof name.

    Returns (relative key, absolute path). The relative key is what gets
    persisted in DB rows as "{UPLOADS_URL_PREFIX}/{key}".
    """
    root = uploads_dir()

    # subdir is always caller-constructed from trusted values (e.g.
    # f"documents/{project_id}"), never raw request input, but check for
    # ".." lexically anyway as defense in depth -- see _ensure_inside for
    # why this is lexical rather than resolve()-based.
    _reject_traversal(subdir)
    target_dir = root / subdir
    target_dir.mkdir(parents=True, exist_ok=True)

    stored_name = f"{uuid.uuid4().hex}{canonical_ext}"
    dest = target_dir / stored_name

    _ensure_inside(root, dest)
    dest.write_bytes(content)
    return f"{subdir}/{stored_name}", dest


def resolve_stored_path(key: str) -> Path:
    """Resolve a stored key to a path inside the uploads root, safely.

    Raises 404 (not 403/500) for traversal attempts or bad keys so callers
    never reveal whether a sibling file exists outside the root.
    """
    root = uploads_dir()
    cleaned = Path(unquote(key).replace("\\", "/"))
    if cleaned.is_absolute() or ".." in cleaned.parts or not cleaned.parts:
        raise HTTPException(status_code=404, detail="Not found")
    candidate = root / cleaned
    _ensure_inside(root, candidate)
    return candidate


def _reject_traversal(subdir: str) -> None:
    parts = Path(subdir.replace("\\", "/")).parts
    if not parts or ".." in parts or Path(subdir).is_absolute():
        raise HTTPException(status_code=404, detail="Not found")


def _ensure_inside(root: Path, candidate: Path) -> None:
    # Deliberately lexical, NOT Path.resolve()-based: resolve()/realpath()
    # can disagree between a path that already exists on disk and one that
    # doesn't yet (symlinks, junctions, and -- observed directly in this
    # sandboxed dev environment -- container filesystem redirection can
    # make an already-materialized `root` and a just-created `candidate`
    # resolve to entirely different real paths, even though `candidate` was
    # built by joining onto `root`). Every candidate reaching this function
    # was constructed by joining `root / <already-traversal-checked-parts>`,
    # so a lexical relative_to() is both correct and doesn't depend on
    # filesystem resolution being consistent across a mkdir boundary.
    try:
        candidate.relative_to(root)
    except ValueError:
        raise HTTPException(status_code=404, detail="Not found") from None


def public_url(key: str) -> str:
    return f"{UPLOADS_URL_PREFIX}/{key}"
