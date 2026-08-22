from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Attendance, Worker
from fieldos.permissions import get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import AttendanceCreate, AttendanceOut, WorkerCreate, WorkerOut

router = APIRouter(prefix="/projects/{project_id}/workers", tags=["workers"])


# ---------------------------------------------------------------------------
# Workers CRUD
# ---------------------------------------------------------------------------

@router.post("", response_model=WorkerOut, status_code=201)
def create_worker(
    project_id: str,
    body: WorkerCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM

    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    worker = Worker(
        project_id=project_id,
        name=body.name,
        role=body.role,
        phone=body.phone,
        daily_wage=body.daily_wage,
    )
    db.add(worker)
    db.commit()
    db.refresh(worker)
    return worker


@router.get("", response_model=list[WorkerOut])
def list_workers(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return (
        db.query(Worker)
        .filter(Worker.project_id == project_id)
        .order_by(Worker.name)
        .all()
    )


@router.patch("/{worker_id}", response_model=WorkerOut)
def update_worker(
    project_id: str,
    worker_id: str,
    body: WorkerCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM

    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    worker = db.get(Worker, worker_id)
    if worker is None or worker.project_id != project_id:
        raise HTTPException(status_code=404, detail="Worker not found")

    worker.name = body.name
    worker.role = body.role
    worker.phone = body.phone
    worker.daily_wage = body.daily_wage
    db.commit()
    db.refresh(worker)
    return worker


@router.delete("/{worker_id}", status_code=204)
def deactivate_worker(
    project_id: str,
    worker_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    from fieldos.permissions import ROLE_OWNER, ROLE_PM

    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    worker = db.get(Worker, worker_id)
    if worker is None or worker.project_id != project_id:
        raise HTTPException(status_code=404, detail="Worker not found")

    worker.status = "inactive"
    db.commit()


# ---------------------------------------------------------------------------
# Attendance
# ---------------------------------------------------------------------------

_attendance_router = APIRouter(prefix="/projects/{project_id}/attendance", tags=["attendance"])


@_attendance_router.post("", response_model=AttendanceOut, status_code=201)
def mark_attendance(
    project_id: str,
    body: AttendanceCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    worker = db.get(Worker, body.worker_id)
    if worker is None or worker.project_id != project_id:
        raise HTTPException(status_code=404, detail="Worker not found")

    existing = (
        db.query(Attendance)
        .filter(Attendance.worker_id == body.worker_id, Attendance.attendance_date == body.attendance_date)
        .first()
    )
    if existing:
        existing.status = body.status
        existing.notes = body.notes
        db.commit()
        db.refresh(existing)
        return existing

    record = Attendance(
        worker_id=body.worker_id,
        attendance_date=body.attendance_date,
        status=body.status,
        notes=body.notes,
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return record


@_attendance_router.get("", response_model=list[AttendanceOut])
def list_attendance(
    project_id: str,
    date: str | None = None,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List attendance records for the project, optionally filtered by date (YYYY-MM-DD)."""
    require_project_access(db, project_id, current_user.id)

    from datetime import date as date_type

    query = (
        db.query(Attendance)
        .join(Worker, Worker.id == Attendance.worker_id)
        .filter(Worker.project_id == project_id)
    )
    if date:
        query = query.filter(Attendance.attendance_date == date_type.fromisoformat(date))
    return query.order_by(Attendance.attendance_date.desc()).all()


@_attendance_router.get("/summary")
def attendance_summary(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Summary: total workers, present/absent/half_day counts for a given date, total wage cost."""
    require_project_access(db, project_id, current_user.id)

    from datetime import date as date_type, timezone
    from sqlalchemy import func

    today = date_type.today()

    total_workers = db.query(func.count(Worker.id)).filter(Worker.project_id == project_id, Worker.status == "active").scalar() or 0

    attendance_rows = (
        db.query(Attendance.status, func.count(Attendance.id))
        .join(Worker, Worker.id == Attendance.worker_id)
        .filter(Worker.project_id == project_id, Attendance.attendance_date == today)
        .group_by(Attendance.status)
        .all()
    )
    counts = {status: cnt for status, cnt in attendance_rows}

    total_wage = (
        db.query(func.coalesce(func.sum(Worker.daily_wage), 0))
        .join(Attendance, Attendance.worker_id == Worker.id)
        .filter(
            Worker.project_id == project_id,
            Attendance.attendance_date == today,
            Attendance.status.in_(["present", "half_day"]),
        )
        .scalar()
    )

    return {
        "date": today.isoformat(),
        "total_workers": total_workers,
        "present": counts.get("present", 0),
        "absent": counts.get("absent", 0),
        "half_day": counts.get("half_day", 0),
        "total_wage_cost": str(total_wage),
    }
