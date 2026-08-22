from datetime import date, datetime, timezone

from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import DPREntry, Issue, Task
from fieldos.permissions import require_project_access
from fieldos.schemas import DashboardOut, FeedItemOut

router = APIRouter(prefix="/projects/{project_id}", tags=["dashboard"])


def _consecutive_day_streak(entry_dates: list[date]) -> int:
    if not entry_dates:
        return 0
    unique_dates = sorted(set(entry_dates), reverse=True)
    streak = 1
    for i in range(1, len(unique_dates)):
        if (unique_dates[i - 1] - unique_dates[i]).days == 1:
            streak += 1
        else:
            break
    return streak


@router.get("/dashboard", response_model=DashboardOut)
def get_dashboard(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    total_tasks = db.query(func.count(Task.id)).filter(Task.project_id == project_id).scalar() or 0
    done_tasks = (
        db.query(func.count(Task.id))
        .filter(Task.project_id == project_id, Task.status == "done")
        .scalar()
        or 0
    )
    percent_complete = round((done_tasks / total_tasks) * 100, 1) if total_tasks else 0.0

    entry_dates = (
        db.query(DPREntry.entry_date)
        .filter(DPREntry.project_id == project_id, DPREntry.status == "confirmed")
        .all()
    )
    dpr_streak = _consecutive_day_streak([e[0] for e in entry_dates])

    open_issues = (
        db.query(Issue).filter(Issue.project_id == project_id, Issue.status == "open").count()
    )

    return DashboardOut(
        percent_tasks_complete=percent_complete,
        dpr_streak_days=dpr_streak,
        open_issue_count=open_issues,
    )


@router.get("/feed", response_model=list[FeedItemOut])
def get_site_feed(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    items: list[FeedItemOut] = []
    for entry in db.query(DPREntry).filter(DPREntry.project_id == project_id).all():
        items.append(
            FeedItemOut(
                type="dpr",
                id=entry.id,
                occurred_at=datetime.combine(entry.entry_date, datetime.min.time()),
                summary=entry.work_summary,
            )
        )
    for issue in db.query(Issue).filter(Issue.project_id == project_id).all():
        items.append(
            FeedItemOut(type="issue", id=issue.id, occurred_at=issue.created_at, summary=issue.description)
        )

    items.sort(key=lambda i: i.occurred_at, reverse=True)
    return items
