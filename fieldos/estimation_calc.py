"""Pure BOQ/estimation calculation functions.

No database access here on purpose — these are the precision-critical
formulas, kept isolated so they can be golden-tested against real numbers
from resources/ without any DB or FastAPI setup.

All arithmetic uses Decimal, never float, to avoid rounding error
compounding across hundreds of line items in a real BOQ.
"""

from dataclasses import dataclass, field
from decimal import Decimal
from typing import Iterable, Protocol

CALC_VOLUME = "volume"
CALC_AREA = "area"
CALC_STEEL_WEIGHT = "steel_weight"
CALC_COUNT = "count"

# Note: this uses the rounded 1m = 3.28ft conversion, matching the real
# Protek Consult estimation sheets exactly (verified against Thumukunta's
# COLUMN REINFORCEMENT sheet), rather than the more precise 0.3048 factor.
FT_TO_M = Decimal(1) / Decimal("3.28")
CFT_TO_CUM = Decimal(1) / Decimal("35.3147")
KG_TO_TONNE = Decimal(1) / Decimal("1000")


def steel_unit_weight_kg_per_m(bar_dia_mm: Decimal) -> Decimal:
    """IS 1786 standard unit weight of a reinforcement bar, in kg per metre.

    unit weight = dia_mm^2 / 162
    """
    return (bar_dia_mm * bar_dia_mm) / Decimal("162")


def steel_entry_weight_kg(bar_dia_mm: Decimal, nos: Decimal, length_ft: Decimal) -> Decimal:
    """Total weight in kg for one steel reinforcement entry (e.g. one bar group)."""
    length_m = length_ft * FT_TO_M
    unit_weight = steel_unit_weight_kg_per_m(bar_dia_mm)
    return nos * length_m * unit_weight


def measurement_entry_quantity(
    calculation_type: str,
    length: Decimal | None,
    width: Decimal | None,
    depth: Decimal | None,
    nos: Decimal,
    is_deduction: bool = False,
) -> Decimal:
    """Per-row quantity for a volume/area/count measurement entry.

    Deduction rows (door/window/ventilator openings subtracted from gross
    brickwork, etc.) return a negative quantity so summing all of a cost
    head's entries directly yields the net quantity.
    """
    if calculation_type == CALC_VOLUME:
        qty = (length or Decimal(0)) * (width or Decimal(0)) * (depth or Decimal(0)) * nos
    elif calculation_type == CALC_AREA:
        qty = (length or Decimal(0)) * (width or Decimal(0)) * nos
    elif calculation_type == CALC_COUNT:
        qty = nos
    else:
        raise ValueError(
            f"measurement entries don't support calculation_type={calculation_type!r}"
        )
    return -qty if is_deduction else qty


# --- BOQ rollup ---------------------------------------------------------
#
# These functions accept plain duck-typed objects (SQLAlchemy model
# instances satisfy them naturally via matching attribute names) so this
# module stays free of any DB dependency — callers (the API router) fetch
# rows from the database and pass them in.


class MeasurementEntryLike(Protocol):
    length: Decimal | None
    width: Decimal | None
    depth: Decimal | None
    nos: Decimal
    is_deduction: bool


class SteelEntryLike(Protocol):
    bar_dia_mm: Decimal
    nos: Decimal
    length_ft: Decimal


class CostHeadLike(Protocol):
    id: str
    name: str
    calculation_type: str
    billing_unit: str
    conversion_factor: Decimal
    rate_per_unit: Decimal | None


def cost_head_raw_quantity(
    cost_head: CostHeadLike,
    entries: Iterable[MeasurementEntryLike] = (),
    steel_entries: Iterable[SteelEntryLike] = (),
) -> Decimal:
    """Sum of all entries belonging to one cost head, in its raw unit."""
    if cost_head.calculation_type == CALC_STEEL_WEIGHT:
        total = Decimal(0)
        for e in steel_entries:
            total += steel_entry_weight_kg(e.bar_dia_mm, e.nos, e.length_ft)
        return total
    total = Decimal(0)
    for e in entries:
        total += measurement_entry_quantity(
            cost_head.calculation_type, e.length, e.width, e.depth, e.nos, e.is_deduction
        )
    return total


def cost_head_billing_quantity(cost_head: CostHeadLike, raw_quantity: Decimal) -> Decimal:
    """Raw quantity converted to the unit pricing is applied against (e.g. CFT -> CUM)."""
    return raw_quantity * cost_head.conversion_factor


def cost_head_amount(cost_head: CostHeadLike, billing_quantity: Decimal) -> Decimal | None:
    """Priced amount for a cost head, or None if no rate has been set yet."""
    if cost_head.rate_per_unit is None:
        return None
    return billing_quantity * cost_head.rate_per_unit


@dataclass
class CostHeadLine:
    cost_head_id: str
    name: str
    billing_unit: str
    raw_quantity: Decimal
    billing_quantity: Decimal
    rate_per_unit: Decimal | None
    amount: Decimal | None


@dataclass
class BOQResult:
    lines: list = field(default_factory=list)
    subtotal: Decimal = Decimal(0)
    contractor_profit_percent: Decimal | None = None
    contractor_profit_amount: Decimal = Decimal(0)
    grand_total: Decimal = Decimal(0)


def build_boq(
    cost_heads_with_entries: Iterable[
        tuple[CostHeadLike, Iterable[MeasurementEntryLike], Iterable[SteelEntryLike]]
    ],
    contractor_profit_percent: Decimal | None = None,
) -> BOQResult:
    """Roll many cost heads (each with its entries) up into a priced BOQ.

    `cost_heads_with_entries` is a sequence of (cost_head, measurement_entries,
    steel_entries) tuples — the caller fetches these from the database and
    passes them in a single pass, keeping this function itself DB-free.
    """
    lines: list[CostHeadLine] = []
    subtotal = Decimal(0)

    for cost_head, entries, steel_entries in cost_heads_with_entries:
        raw_qty = cost_head_raw_quantity(cost_head, entries, steel_entries)
        billing_qty = cost_head_billing_quantity(cost_head, raw_qty)
        amount = cost_head_amount(cost_head, billing_qty)
        lines.append(
            CostHeadLine(
                cost_head_id=cost_head.id,
                name=cost_head.name,
                billing_unit=cost_head.billing_unit,
                raw_quantity=raw_qty,
                billing_quantity=billing_qty,
                rate_per_unit=cost_head.rate_per_unit,
                amount=amount,
            )
        )
        if amount is not None:
            subtotal += amount

    if contractor_profit_percent is not None:
        profit_amount = subtotal * contractor_profit_percent / Decimal("100")
    else:
        profit_amount = Decimal(0)

    return BOQResult(
        lines=lines,
        subtotal=subtotal,
        contractor_profit_percent=contractor_profit_percent,
        contractor_profit_amount=profit_amount,
        grand_total=subtotal + profit_amount,
    )
