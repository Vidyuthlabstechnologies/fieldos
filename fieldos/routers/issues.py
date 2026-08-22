from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import Issue
from fieldos.permissions import ROLE_OWNER, ROLE_PM, get_project_or_404, require_company_role, require_project_access
from fieldos.schemas import IssueCreate, IssueOut

router = APIRouter(prefix="/projects/{project_id}/issues", tags=["issues"])


@router.post("", response_model=IssueOut, status_code=201)
def create_issue(
    project_id: str,
    body: IssueCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    issue = Issue(
        project_id=project_id,
        dpr_entry_id=body.dpr_entry_id,
        description=body.description,
        severity=body.severity,
        status="open",
    )
    db.add(issue)
    db.commit()
    db.refresh(issue)
    return issue


@router.get("", response_model=list[IssueOut])
def list_issues(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return db.query(Issue).filter(Issue.project_id == project_id).order_by(Issue.created_at.desc()).all()


@router.patch("/{issue_id}/resolve", response_model=IssueOut)
def resolve_issue(
    project_id: str,
    issue_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = get_project_or_404(db, project_id)
    require_company_role(db, project.company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    issue = db.get(Issue, issue_id)
    if issue is None or issue.project_id != project_id:
        raise HTTPException(status_code=404, detail="Issue not found")

    issue.status = "resolved"
    issue.resolved_at = datetime.now(timezone.utc).replace(tzinfo=None)
    db.commit()
    db.refresh(issue)
    return issue
