from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Task
from fieldos.permissions import ROLE_OWNER, ROLE_PM, get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import TaskCreate, TaskOut, TaskStatusUpdate

router = APIRouter(prefix="/projects/{project_id}/tasks", tags=["tasks"])

VALID_STATUSES = {"todo", "in_progress", "done", "blocked"}


@router.post("", response_model=TaskOut, status_code=201)
def create_task(
    project_id: str,
    body: TaskCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    task = Task(project_id=project_id, title=body.title, assignee_id=body.assignee_id, due_date=body.due_date)
    db.add(task)
    db.commit()
    db.refresh(task)
    return task


@router.get("", response_model=list[TaskOut])
def list_tasks(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(Task).filter(Task.project_id == project_id).order_by(Task.created_at).all()


@router.patch("/{task_id}", response_model=TaskOut)
def update_task_status(
    project_id: str,
    task_id: str,
    body: TaskStatusUpdate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    if body.status not in VALID_STATUSES:
        raise HTTPException(status_code=422, detail=f"status must be one of {sorted(VALID_STATUSES)}")

    task = db.get(Task, task_id)
    if task is None or task.project_id != project_id:
        raise HTTPException(status_code=404, detail="Task not found")

    task.status = body.status
    db.commit()
    db.refresh(task)
    return task
