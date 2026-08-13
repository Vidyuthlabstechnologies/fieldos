"""Pure BOQ/estimation calculation functions.

No database access here on purpose — these are the precision-critical
formulas, kept isolated so they can be golden-tested against real numbers
from resources/ without any DB or FastAPI setup.

All arithmetic uses Decimal, never float, to avoid rounding error
compounding across hundreds of line items in a real BOQ.
"""

from decimal import Decimal

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
