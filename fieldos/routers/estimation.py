from dataclasses import asdict
from decimal import ROUND_HALF_UP, Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, selectinload

from fieldos.auth import CurrentUser, get_current_user
from fieldos.db import get_db
from fieldos.estimation_calc import CALC_STEEL_WEIGHT, build_boq
from fieldos.models import CostHead, Estimation, MeasurementEntry, SteelEntry
from fieldos.permissions import require_project_access
from fieldos.schemas import (
    BOQLineOut,
    BOQOut,
    CostHeadCreate,
    CostHeadOut,
    EstimationCreate,
    EstimationOut,
    MeasurementEntryCreate,
    MeasurementEntryOut,
    SteelEntryCreate,
    SteelEntryOut,
)

router = APIRouter(tags=["estimation"])

VALID_CALCULATION_TYPES = {"volume", "area", "steel_weight", "count"}


def get_estimation_or_404(db: Session, estimation_id: str) -> Estimation:
    estimation = db.get(Estimation, estimation_id)
    if estimation is None:
        raise HTTPException(status_code=404, detail="Estimation not found")
    return estimation


def get_cost_head_or_404(db: Session, cost_head_id: str) -> CostHead:
    cost_head = db.get(CostHead, cost_head_id)
    if cost_head is None:
        raise HTTPException(status_code=404, detail="Cost head not found")
    return cost_head


@router.post("/projects/{project_id}/estimations", response_model=EstimationOut, status_code=201)
def create_estimation(
    project_id: str,
    body: EstimationCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)

    estimation = Estimation(
        project_id=project_id,
        name=body.name,
        contractor_profit_percent=body.contractor_profit_percent,
        created_by=current_user.id,
    )
    db.add(estimation)
    db.commit()
    db.refresh(estimation)
    return estimation


@router.get("/projects/{project_id}/estimations", response_model=list[EstimationOut])
def list_estimations(
    project_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    require_project_access(db, project_id, current_user.id)
    return (
        db.query(Estimation)
        .filter(Estimation.project_id == project_id)
        .order_by(Estimation.created_at.desc())
        .all()
    )


@router.post("/estimations/{estimation_id}/cost-heads", response_model=CostHeadOut, status_code=201)
def create_cost_head(
    estimation_id: str,
    body: CostHeadCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    estimation = get_estimation_or_404(db, estimation_id)
    require_project_access(db, estimation.project_id, current_user.id)

    if body.calculation_type not in VALID_CALCULATION_TYPES:
        raise HTTPException(
            status_code=422,
            detail=f"calculation_type must be one of {sorted(VALID_CALCULATION_TYPES)}",
        )

    cost_head = CostHead(
        estimation_id=estimation_id,
        name=body.name,
        calculation_type=body.calculation_type,
        raw_unit=body.raw_unit,
        billing_unit=body.billing_unit,
        conversion_factor=body.conversion_factor,
        rate_per_unit=body.rate_per_unit,
    )
    db.add(cost_head)
    db.commit()
    db.refresh(cost_head)
    return cost_head


@router.get("/estimations/{estimation_id}/cost-heads", response_model=list[CostHeadOut])
def list_cost_heads(
    estimation_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    estimation = get_estimation_or_404(db, estimation_id)
    require_project_access(db, estimation.project_id, current_user.id)
    return (
        db.query(CostHead)
        .filter(CostHead.estimation_id == estimation_id)
        .order_by(CostHead.sort_order)
        .all()
    )


@router.post(
    "/cost-heads/{cost_head_id}/measurement-entries",
    response_model=MeasurementEntryOut,
    status_code=201,
)
def create_measurement_entry(
    cost_head_id: str,
    body: MeasurementEntryCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    cost_head = get_cost_head_or_404(db, cost_head_id)
    estimation = get_estimation_or_404(db, cost_head.estimation_id)
    require_project_access(db, estimation.project_id, current_user.id)

    if cost_head.calculation_type == CALC_STEEL_WEIGHT:
        raise HTTPException(
            status_code=422,
            detail="this cost head uses steel entries, not measurement entries",
        )

    entry = MeasurementEntry(
        cost_head_id=cost_head_id,
        description=body.description,
        length=body.length,
        width=body.width,
        depth=body.depth,
        nos=body.nos,
        is_deduction=body.is_deduction,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.post(
    "/cost-heads/{cost_head_id}/steel-entries",
    response_model=SteelEntryOut,
    status_code=201,
)
def create_steel_entry(
    cost_head_id: str,
    body: SteelEntryCreate,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    cost_head = get_cost_head_or_404(db, cost_head_id)
    estimation = get_estimation_or_404(db, cost_head.estimation_id)
    require_project_access(db, estimation.project_id, current_user.id)

    if cost_head.calculation_type != CALC_STEEL_WEIGHT:
        raise HTTPException(
            status_code=422,
            detail="this cost head doesn't use steel entries",
        )

    entry = SteelEntry(
        cost_head_id=cost_head_id,
        description=body.description,
        bar_dia_mm=body.bar_dia_mm,
        nos=body.nos,
        length_ft=body.length_ft,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return entry


@router.get("/estimations/{estimation_id}/boq", response_model=BOQOut)
def get_boq(
    estimation_id: str,
    current_user: CurrentUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    estimation = get_estimation_or_404(db, estimation_id)
    require_project_access(db, estimation.project_id, current_user.id)

    cost_heads = (
        db.query(CostHead)
        .filter(CostHead.estimation_id == estimation_id)
        .order_by(CostHead.sort_order)
        .options(selectinload(CostHead.measurement_entries), selectinload(CostHead.steel_entries))
        .all()
    )

    cost_heads_with_entries: list[
        tuple[CostHead, list[MeasurementEntry], list[SteelEntry]]
    ] = []
    for cost_head in cost_heads:
        if cost_head.calculation_type == CALC_STEEL_WEIGHT:
            cost_heads_with_entries.append((cost_head, [], list(cost_head.steel_entries)))
        else:
            cost_heads_with_entries.append((cost_head, list(cost_head.measurement_entries), []))

    result = build_boq(cost_heads_with_entries, contractor_profit_percent=estimation.contractor_profit_percent)

    return BOQOut(
        lines=[_round_boq_line(line) for line in result.lines],
        subtotal=_round_money(result.subtotal),
        contractor_profit_percent=result.contractor_profit_percent,
        contractor_profit_amount=_round_money(result.contractor_profit_amount),
        grand_total=_round_money(result.grand_total),
    )


_QUANTITY_PLACES = Decimal("1.000000")
_MONEY_PLACES = Decimal("1.00")


def _round_money(value: Decimal) -> Decimal:
    return value.quantize(_MONEY_PLACES, rounding=ROUND_HALF_UP)


def _round_boq_line(line) -> BOQLineOut:
    # SQLAlchemy's SQLite Numeric type pads read-back values to their full
    # declared column scale (e.g. 108.25 -> Decimal("108.250000")), so
    # multiplying several of them compounds into long trailing-zero strings
    # (e.g. "718.509375000000000000000000"). Mathematically correct but
    # unusable in a UI -- round for display here, at the API boundary, so
    # the internal calculation engine itself stays exact/unrounded.
    data = asdict(line)
    data["raw_quantity"] = data["raw_quantity"].quantize(_QUANTITY_PLACES, rounding=ROUND_HALF_UP)
    data["billing_quantity"] = data["billing_quantity"].quantize(_QUANTITY_PLACES, rounding=ROUND_HALF_UP)
    if data["amount"] is not None:
        data["amount"] = _round_money(data["amount"])
    return BOQLineOut(**data)
