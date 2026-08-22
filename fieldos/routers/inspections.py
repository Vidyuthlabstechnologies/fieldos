from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy.orm import Session
from typing import Literal

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Inspection, InspectionItem, InspectionPhoto
from fieldos.permissions import require_project_access
from fieldos.storage import public_url, save_upload, validate_upload
from fieldos.schemas import (
    InspectionCreate,
    InspectionItemCreate,
    InspectionItemOut,
    InspectionOut,
    InspectionPhotoCreate,
    InspectionPhotoOut,
)

router = APIRouter(tags=["inspections"])


# ---------------------------------------------------------------------------
# Inspections
# ---------------------------------------------------------------------------

@router.post("/projects/{project_id}/inspections", response_model=InspectionOut, status_code=201)
def create_inspection(
    project_id: str,
    body: InspectionCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    insp = Inspection(
        project_id=project_id,
        inspector_id=current_user.id,
        **body.model_dump(),
    )
    db.add(insp)
    db.commit()
    db.refresh(insp)
    return insp


@router.get("/projects/{project_id}/inspections", response_model=list[InspectionOut])
def list_inspections(
    project_id: str,
    status: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    query = db.query(Inspection).filter(Inspection.project_id == project_id)
    if status:
        query = query.filter(Inspection.status == status)
    return query.order_by(Inspection.created_at.desc()).all()


@router.patch("/projects/{project_id}/inspections/{insp_id}/complete", response_model=InspectionOut)
def complete_inspection(
    project_id: str,
    insp_id: str,
    result: Literal["pass", "fail", "conditional"] = "pass",
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from datetime import date as date_type

    require_project_access(db, project_id, current_user.id)
    insp = db.get(Inspection, insp_id)
    if insp is None or insp.project_id != project_id:
        raise HTTPException(status_code=404, detail="Inspection not found")

    insp.status = "completed"
    insp.completed_date = date_type.today()
    insp.overall_result = result
    db.commit()
    db.refresh(insp)
    return insp


# ---------------------------------------------------------------------------
# Inspection checklist items
# ---------------------------------------------------------------------------

@router.post("/inspections/{insp_id}/items", response_model=InspectionItemOut, status_code=201)
def add_inspection_item(
    insp_id: str,
    body: InspectionItemCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    insp = db.get(Inspection, insp_id)
    if insp is None:
        raise HTTPException(status_code=404, detail="Inspection not found")
    require_project_access(db, insp.project_id, current_user.id)

    # Auto-increment sort order
    max_order = db.query(InspectionItem.sort_order).filter(InspectionItem.inspection_id == insp_id).order_by(InspectionItem.sort_order.desc()).first()
    next_order = (max_order[0] + 1) if max_order else 0

    item = InspectionItem(inspection_id=insp_id, sort_order=next_order, **body.model_dump())
    db.add(item)
    db.commit()
    db.refresh(item)
    return item


@router.get("/inspections/{insp_id}/items", response_model=list[InspectionItemOut])
def list_inspection_items(
    insp_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    insp = db.get(Inspection, insp_id)
    if insp is None:
        raise HTTPException(status_code=404, detail="Inspection not found")
    require_project_access(db, insp.project_id, current_user.id)
    return db.query(InspectionItem).filter(InspectionItem.inspection_id == insp_id).order_by(InspectionItem.sort_order).all()


@router.patch("/inspections/{insp_id}/items/{item_id}", response_model=InspectionItemOut)
def update_inspection_item(
    insp_id: str,
    item_id: str,
    body: InspectionItemCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    insp = db.get(Inspection, insp_id)
    if insp is None:
        raise HTTPException(status_code=404, detail="Inspection not found")
    require_project_access(db, insp.project_id, current_user.id)

    item = db.get(InspectionItem, item_id)
    if item is None or item.inspection_id != insp_id:
        raise HTTPException(status_code=404, detail="Inspection item not found")

    item.item_description = body.item_description
    item.status = body.status
    item.notes = body.notes
    db.commit()
    db.refresh(item)
    return item


# ---------------------------------------------------------------------------
# Inspection photos
# ---------------------------------------------------------------------------

@router.post("/inspections/{insp_id}/photos", response_model=InspectionPhotoOut, status_code=201)
async def upload_inspection_photo(
    insp_id: str,
    file: UploadFile = File(...),
    caption: str = "",
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    insp = db.get(Inspection, insp_id)
    if insp is None:
        raise HTTPException(status_code=404, detail="Inspection not found")
    require_project_access(db, insp.project_id, current_user.id)

    content = await file.read()
    ext = validate_upload(file, content, kind="image")
    key, _ = save_upload(content, subdir="inspections", canonical_ext=ext)
    photo_url = public_url(key)

    photo = InspectionPhoto(
        inspection_id=insp_id,
        photo_url=photo_url,
        caption=caption or None,
        uploaded_by=current_user.id,
    )
    db.add(photo)
    db.commit()
    db.refresh(photo)
    return photo


@router.get("/inspections/{insp_id}/photos", response_model=list[InspectionPhotoOut])
def list_inspection_photos(
    insp_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    insp = db.get(Inspection, insp_id)
    if insp is None:
        raise HTTPException(status_code=404, detail="Inspection not found")
    require_project_access(db, insp.project_id, current_user.id)
    return db.query(InspectionPhoto).filter(InspectionPhoto.inspection_id == insp_id).order_by(InspectionPhoto.created_at.desc()).all()