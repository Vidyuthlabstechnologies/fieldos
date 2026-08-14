from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.models import (
    CostHead,
    DPREntry,
    DPRPhoto,
    Estimation,
    Issue,
    MeasurementEntry,
    Project,
    ProjectMember,
    SteelEntry,
    Task,
)
from fieldos.permissions import ROLE_OWNER, ROLE_PM, require_company_role, require_project_access
from fieldos.schemas import (
    EXPORT_FORMAT,
    CostHeadExport,
    DPREntryExport,
    DPRPhotoExport,
    EstimationExport,
    IssueExport,
    MeasurementEntryExport,
    ProjectExport,
    ProjectExportPayload,
    ProjectOut,
    SteelEntryExport,
    TaskExport,
)

router = APIRouter(tags=["portability"])


@router.get("/projects/{project_id}/export", response_model=ProjectExport)
def export_project(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    project = require_project_access(db, project_id, current_user.id)

    tasks = db.query(Task).filter(Task.project_id == project_id).all()

    dpr_entries = (
        db.query(DPREntry).filter(DPREntry.project_id == project_id).order_by(DPREntry.entry_date).all()
    )
    dpr_local_id_by_real_id = {entry.id: i + 1 for i, entry in enumerate(dpr_entries)}

    dpr_entry_exports = []
    for entry in dpr_entries:
        photos = db.query(DPRPhoto).filter(DPRPhoto.dpr_entry_id == entry.id).all()
        dpr_entry_exports.append(
            DPREntryExport(
                local_id=dpr_local_id_by_real_id[entry.id],
                entry_date=entry.entry_date,
                work_summary=entry.work_summary,
                manpower_count=entry.manpower_count,
                weather=entry.weather,
                status=entry.status,
                source=entry.source,
                photos=[DPRPhotoExport(photo_url=p.photo_url, caption=p.caption) for p in photos],
            )
        )

    issues = db.query(Issue).filter(Issue.project_id == project_id).all()
    issue_exports = [
        IssueExport(
            dpr_entry_local_id=dpr_local_id_by_real_id.get(issue.dpr_entry_id) if issue.dpr_entry_id else None,
            description=issue.description,
            severity=issue.severity,
            status=issue.status,
            resolved_at=issue.resolved_at,
        )
        for issue in issues
    ]

    estimations = db.query(Estimation).filter(Estimation.project_id == project_id).all()
    estimation_exports = []
    for estimation in estimations:
        cost_heads = (
            db.query(CostHead)
            .filter(CostHead.estimation_id == estimation.id)
            .order_by(CostHead.sort_order)
            .all()
        )
        cost_head_exports = []
        for cost_head in cost_heads:
            measurement_entries = (
                db.query(MeasurementEntry).filter(MeasurementEntry.cost_head_id == cost_head.id).all()
            )
            steel_entries = db.query(SteelEntry).filter(SteelEntry.cost_head_id == cost_head.id).all()
            cost_head_exports.append(
                CostHeadExport(
                    name=cost_head.name,
                    calculation_type=cost_head.calculation_type,
                    raw_unit=cost_head.raw_unit,
                    billing_unit=cost_head.billing_unit,
                    conversion_factor=cost_head.conversion_factor,
                    rate_per_unit=cost_head.rate_per_unit,
                    sort_order=cost_head.sort_order,
                    measurement_entries=[
                        MeasurementEntryExport(
                            description=e.description,
                            length=e.length,
                            width=e.width,
                            depth=e.depth,
                            nos=e.nos,
                            is_deduction=e.is_deduction,
                        )
                        for e in measurement_entries
                    ],
                    steel_entries=[
                        SteelEntryExport(
                            description=e.description, bar_dia_mm=e.bar_dia_mm, nos=e.nos, length_ft=e.length_ft
                        )
                        for e in steel_entries
                    ],
                )
            )
        estimation_exports.append(
            EstimationExport(
                name=estimation.name,
                status=estimation.status,
                contractor_profit_percent=estimation.contractor_profit_percent,
                cost_heads=cost_head_exports,
            )
        )

    return ProjectExport(
        format=EXPORT_FORMAT,
        project=ProjectExportPayload(
            name=project.name,
            client_name=project.client_name,
            location_lat=project.location_lat,
            location_lng=project.location_lng,
            geofence_radius_m=project.geofence_radius_m,
            start_date=project.start_date,
            end_date=project.end_date,
            status=project.status,
        ),
        tasks=[TaskExport(title=t.title, due_date=t.due_date, status=t.status) for t in tasks],
        dpr_entries=dpr_entry_exports,
        issues=issue_exports,
        estimations=estimation_exports,
    )


@router.post("/companies/{company_id}/import", response_model=ProjectOut, status_code=201)
def import_project(
    company_id: str,
    body: ProjectExport,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if body.format != EXPORT_FORMAT:
        raise HTTPException(status_code=422, detail=f"Unsupported export format: {body.format!r}")

    creator_role = require_company_role(db, company_id, current_user.id, {ROLE_OWNER, ROLE_PM})

    project = Project(company_id=company_id, **body.project.model_dump())
    db.add(project)
    db.flush()
    db.add(ProjectMember(project_id=project.id, user_id=current_user.id, role=creator_role))

    for task in body.tasks:
        db.add(Task(project_id=project.id, title=task.title, due_date=task.due_date, status=task.status))

    dpr_real_id_by_local_id: dict[int, str] = {}
    for entry in body.dpr_entries:
        row = DPREntry(
            project_id=project.id,
            created_by=current_user.id,
            entry_date=entry.entry_date,
            work_summary=entry.work_summary,
            manpower_count=entry.manpower_count,
            weather=entry.weather,
            status=entry.status,
            source=entry.source,
        )
        db.add(row)
        db.flush()
        dpr_real_id_by_local_id[entry.local_id] = row.id
        for photo in entry.photos:
            db.add(DPRPhoto(dpr_entry_id=row.id, photo_url=photo.photo_url, caption=photo.caption))

    for issue in body.issues:
        db.add(
            Issue(
                project_id=project.id,
                dpr_entry_id=dpr_real_id_by_local_id.get(issue.dpr_entry_local_id)
                if issue.dpr_entry_local_id is not None
                else None,
                description=issue.description,
                severity=issue.severity,
                status=issue.status,
                resolved_at=issue.resolved_at,
            )
        )

    for estimation in body.estimations:
        estimation_row = Estimation(
            project_id=project.id,
            name=estimation.name,
            status=estimation.status,
            contractor_profit_percent=estimation.contractor_profit_percent,
            created_by=current_user.id,
        )
        db.add(estimation_row)
        db.flush()

        for cost_head in estimation.cost_heads:
            cost_head_row = CostHead(
                estimation_id=estimation_row.id,
                name=cost_head.name,
                calculation_type=cost_head.calculation_type,
                raw_unit=cost_head.raw_unit,
                billing_unit=cost_head.billing_unit,
                conversion_factor=cost_head.conversion_factor,
                rate_per_unit=cost_head.rate_per_unit,
                sort_order=cost_head.sort_order,
            )
            db.add(cost_head_row)
            db.flush()

            for e in cost_head.measurement_entries:
                db.add(
                    MeasurementEntry(
                        cost_head_id=cost_head_row.id,
                        description=e.description,
                        length=e.length,
                        width=e.width,
                        depth=e.depth,
                        nos=e.nos,
                        is_deduction=e.is_deduction,
                    )
                )
            for e in cost_head.steel_entries:
                db.add(
                    SteelEntry(
                        cost_head_id=cost_head_row.id,
                        description=e.description,
                        bar_dia_mm=e.bar_dia_mm,
                        nos=e.nos,
                        length_ft=e.length_ft,
                    )
                )

    db.commit()
    db.refresh(project)
    return project
