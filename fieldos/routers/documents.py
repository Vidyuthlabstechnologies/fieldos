from fastapi import APIRouter, Depends, HTTPException, UploadFile
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Document
from fieldos.permissions import require_project_access
from fieldos.storage import save_upload, validate_upload
from fieldos.schemas import DocumentOut

router = APIRouter(prefix="/projects/{project_id}/documents", tags=["documents"])


@router.post("", response_model=DocumentOut, status_code=201)
async def upload_document(
    project_id: str,
    file: UploadFile,
    category: str = "other",
    notes: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    content = await file.read()
    ext = validate_upload(file, content, kind="document")

    # The stored name is generated (uuid + canonical extension); the user's
    # filename is kept only as metadata and never touches the filesystem.
    key, dest = save_upload(content, subdir=f"documents/{project_id}", canonical_ext=ext)

    existing = (
        db.query(Document)
        .filter(Document.project_id == project_id, Document.name == file.filename)
        .order_by(Document.version.desc())
        .first()
    )
    version = (existing.version + 1) if existing else 1

    doc = Document(
        project_id=project_id,
        name=file.filename or "unnamed",
        category=category,
        version=version,
        file_path=str(dest),
        file_size=len(content),
        mime_type=file.content_type,
        notes=notes,
        uploaded_by=current_user.id,
    )
    db.add(doc)
    db.commit()
    db.refresh(doc)
    return doc


@router.get("", response_model=list[DocumentOut])
def list_documents(
    project_id: str,
    category: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    query = db.query(Document).filter(Document.project_id == project_id)
    if category:
        query = query.filter(Document.category == category)
    return query.order_by(Document.name, Document.version.desc()).all()


@router.get("/versions/{name}")
def document_versions(
    project_id: str,
    name: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all versions of a document by name."""
    require_project_access(db, project_id, current_user.id)
    return (
        db.query(Document)
        .filter(Document.project_id == project_id, Document.name == name)
        .order_by(Document.version.desc())
        .all()
    )
