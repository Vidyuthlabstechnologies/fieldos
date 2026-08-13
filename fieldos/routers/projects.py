from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Project, ProjectMember
from fieldos.permissions import (
    ROLE_OWNER,
    ROLE_PM,
    ROLE_SITE_ENGINEER,
    get_project_or_404,
    require_company_role,
    require_project_access,
)
from fieldos.schemas import ProjectCreate, ProjectMemberAdd, ProjectMemberOut, ProjectOut

router = APIRouter(prefix="/projects", tags=["projects"])


@router.post("", response_model=ProjectOut, status_code=201)
def create_project(
    body: ProjectCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    creator_role = require_company_role(db, body.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    project = Project(
        company_id=body.company_id,
        name=body.name,
        client_name=body.client_name,
        location_lat=body.location_lat,
        location_lng=body.location_lng,
        geofence_radius_m=body.geofence_radius_m,
        start_date=body.start_date,
        end_date=body.end_date,
        status="planning",
    )
    db.add(project)
    db.flush()

    db.add(ProjectMember(project_id=project.id, user_id=current_user.id, role=creator_role))
    db.commit()
    db.refresh(project)
    return project


@router.get("", response_model=list[ProjectOut])
def list_projects(
    company_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    role = require_company_role(
        db, company_id, current_user.id, {ROLE_OWNER, ROLE_PM, ROLE_SITE_ENGINEER}
    )
    query = db.query(Project).filter(Project.company_id == company_id)
    if role != ROLE_OWNER:
        member_project_ids = [
            m.project_id
            for m in db.query(ProjectMember).filter(ProjectMember.user_id == current_user.id).all()
        ]
        query = query.filter(Project.id.in_(member_project_ids))
    return query.all()


@router.get("/{project_id}", response_model=ProjectOut)
def get_project(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    return require_project_access(db, project_id, current_user.id)


@router.post("/{project_id}/members", response_model=ProjectMemberOut, status_code=201)
def add_project_member(
    project_id: str,
    body: ProjectMemberAdd,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    member = ProjectMember(project_id=project_id, user_id=body.user_id, role=body.role)
    db.add(member)
    db.commit()
    db.refresh(member)
    return member
