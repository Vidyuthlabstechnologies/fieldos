from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Equipment, EquipmentLog
from fieldos.permissions import get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import EquipmentCreate, EquipmentLogCreate, EquipmentLogOut, EquipmentOut, EquipmentUpdate

router = APIRouter(tags=["equipment"])


# ---------------------------------------------------------------------------
# Equipment CRUD
# ---------------------------------------------------------------------------

@router.post("/projects/{project_id}/equipment", response_model=EquipmentOut, status_code=201)
def create_equipment(
    project_id: str,
    body: EquipmentCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    eq = Equipment(project_id=project_id, **body.model_dump())
    db.add(eq)
    db.commit()
    db.refresh(eq)
    return eq


@router.get("/projects/{project_id}/equipment", response_model=list[EquipmentOut])
def list_equipment(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(Equipment).filter(Equipment.project_id == project_id).order_by(Equipment.name).all()


@router.patch("/projects/{project_id}/equipment/{eq_id}", response_model=EquipmentOut)
def update_equipment_status(
    project_id: str,
    eq_id: str,
    body: EquipmentUpdate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    eq = db.get(Equipment, eq_id)
    if eq is None or eq.project_id != project_id:
        raise HTTPException(status_code=404, detail="Equipment not found")
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(eq, k, v)
    db.commit()
    db.refresh(eq)
    return eq


@router.delete("/projects/{project_id}/equipment/{eq_id}", status_code=204)
def remove_equipment(
    project_id: str,
    eq_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM

    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    eq = db.get(Equipment, eq_id)
    if eq is None or eq.project_id != project_id:
        raise HTTPException(status_code=404, detail="Equipment not found")
    db.delete(eq)
    db.commit()


# ---------------------------------------------------------------------------
# Equipment logs (usage, maintenance, fuel, etc.)
# ---------------------------------------------------------------------------

@router.post("/equipment/{eq_id}/logs", response_model=EquipmentLogOut, status_code=201)
def create_equipment_log(
    eq_id: str,
    body: EquipmentLogCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    eq = db.get(Equipment, eq_id)
    if eq is None:
        raise HTTPException(status_code=404, detail="Equipment not found")
    require_project_access(db, eq.project_id, current_user.id)

    log = EquipmentLog(equipment_id=eq_id, created_by=current_user.id, **body.model_dump())
    db.add(log)
    db.commit()
    db.refresh(log)
    return log


@router.get("/equipment/{eq_id}/logs", response_model=list[EquipmentLogOut])
def list_equipment_logs(
    eq_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    eq = db.get(Equipment, eq_id)
    if eq is None:
        raise HTTPException(status_code=404, detail="Equipment not found")
    require_project_access(db, eq.project_id, current_user.id)
    return db.query(EquipmentLog).filter(EquipmentLog.equipment_id == eq_id).order_by(EquipmentLog.log_date.desc()).all()
