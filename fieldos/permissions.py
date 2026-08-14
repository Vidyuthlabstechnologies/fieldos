from fastapi import HTTPException
from sqlalchemy.orm import Session

from fieldos.models import CompanyMember, Project, ProjectMember

ROLE_OWNER = "owner"
ROLE_PM = "project_manager"
ROLE_SITE_ENGINEER = "site_engineer"


def get_company_role(db: Session, company_id: str, user_id: str) -> str | None:
    member = (
        db.query(CompanyMember)
        .filter(CompanyMember.company_id == company_id, CompanyMember.user_id == user_id)
        .first()
    )
    return member.role if member else None


def require_company_role(db: Session, company_id: str, user_id: str, allowed: set[str]) -> str:
    role = get_company_role(db, company_id, user_id)
    if role is None or role not in allowed:
        raise HTTPException(status_code=403, detail="Not authorized for this company")
    return role


def require_any_owner_role(db: Session, user_id: str) -> None:
    """For installation-wide actions (e.g. settings) that aren't scoped to
    one company_id -- requires owning at least one company on this install,
    rather than any authenticated user (which would include a freshly
    self-registered account with zero memberships)."""
    is_owner_somewhere = (
        db.query(CompanyMember)
        .filter(CompanyMember.user_id == user_id, CompanyMember.role == ROLE_OWNER)
        .first()
    )
    if not is_owner_somewhere:
        raise HTTPException(status_code=403, detail="Must be a company owner to change this setting")


def get_project_or_404(db: Session, project_id: str) -> Project:
    project = db.get(Project, project_id)
    if project is None:
        raise HTTPException(status_code=404, detail="Project not found")
    return project


def require_project_access(db: Session, project_id: str, user_id: str) -> Project:
    project = get_project_or_404(db, project_id)
    company_role = get_company_role(db, project.company_id, user_id)
    if company_role == ROLE_OWNER:
        return project
    is_member = (
        db.query(ProjectMember)
        .filter(ProjectMember.project_id == project_id, ProjectMember.user_id == user_id)
        .first()
    )
    if not is_member:
        raise HTTPException(status_code=403, detail="Not a member of this project")
    return project
