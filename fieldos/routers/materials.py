from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import func
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import MaterialEntry, MaterialPhoto
from fieldos.permissions import require_project_access
from fieldos.storage import public_url, save_upload, validate_upload
from fieldos.schemas import MaterialEntryCreate, MaterialEntryOut, MaterialPhotoOut

router = APIRouter(prefix="/projects/{project_id}/materials", tags=["materials"])


@router.post("", response_model=MaterialEntryOut, status_code=201)
def create_material_entry(
    project_id: str,
    body: MaterialEntryCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    entry = MaterialEntry(
        project_id=project_id,
        entry_date=body.entry_date,
        item_name=body.item_name,
        category=body.category,
        quantity=body.quantity,
        unit=body.unit,
        supplier=body.supplier,
        cost=body.cost,
        notes=body.notes,
        created_by=current_user.id,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.get("", response_model=list[MaterialEntryOut])
def list_material_entries(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return (
        db.query(MaterialEntry)
        .filter(MaterialEntry.project_id == project_id)
        .order_by(MaterialEntry.entry_date.desc(), MaterialEntry.created_at.desc())
        .all()
    )


@router.get("/summary")
def material_summary(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Aggregate cost by category for the project dashboard."""
    require_project_access(db, project_id, current_user.id)

    rows = (
        db.query(
            MaterialEntry.category,
            func.count(MaterialEntry.id).label("count"),
            func.coalesce(func.sum(MaterialEntry.cost), 0).label("total_cost"),
            func.coalesce(func.sum(MaterialEntry.quantity), 0).label("total_quantity"),
        )
        .filter(MaterialEntry.project_id == project_id)
        .group_by(MaterialEntry.category)
        .all()
    )

    return [
        {
            "category": r.category,
            "count": r.count,
            "total_cost": str(r.total_cost),
            "total_quantity": str(r.total_quantity),
        }
        for r in rows
    ]


# Photo upload endpoints
@router.post("/{entry_id}/photos", response_model=MaterialPhotoOut, status_code=201)
async def upload_material_photo(
    project_id: str,
    entry_id: str,
    file: UploadFile = File(...),
    caption: str = "",
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    entry = db.get(MaterialEntry, entry_id)
    if entry is None or entry.project_id != project_id:
        raise HTTPException(status_code=404, detail="Material entry not found")
    require_project_access(db, project_id, current_user.id)

    content = await file.read()
    ext = validate_upload(file, content, kind="image")
    key, _ = save_upload(content, subdir="materials", canonical_ext=ext)

    photo = MaterialPhoto(
        material_entry_id=entry_id,
        photo_url=public_url(key),
        caption=caption or None,
    )
    db.add(photo)
    db.commit()
    db.refresh(photo)
    return photo


@router.get("/{entry_id}/photos", response_model=list[MaterialPhotoOut])
def list_material_photos(
    project_id: str,
    entry_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    entry = db.get(MaterialEntry, entry_id)
    if entry is None or entry.project_id != project_id:
        raise HTTPException(status_code=404, detail="Material entry not found")
    require_project_access(db, project_id, current_user.id)
    return db.query(MaterialPhoto).filter(MaterialPhoto.material_entry_id == entry_id).all()