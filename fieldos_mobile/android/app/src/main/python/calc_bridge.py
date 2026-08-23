"""Kotlin-facing wrapper around estimation_calc.py.

Every Decimal in and out crosses the Kotlin/Python boundary as a string,
never a float/double -- that's the entire point of this bridge (it exists
to eliminate the Python/Dart precision-model divergence documented in
docs/CODEBASE_RECONNAISSANCE.md's duplicated-logic section, not to
reintroduce a new one at the platform-channel boundary).
"""

from decimal import Decimal

import estimation_calc as calc


def _dec(value):
    return None if value is None else Decimal(value)


def measurement_entry_quantity(
    calculation_type: str,
    length: str | None,
    width: str | None,
    depth: str | None,
    nos: str,
    is_deduction: bool,
) -> str:
    result = calc.measurement_entry_quantity(
        calculation_type, _dec(length), _dec(width), _dec(depth), Decimal(nos), is_deduction
    )
    return str(result)


def steel_entry_weight_kg(bar_dia_mm: str, nos: str, length_ft: str) -> str:
    result = calc.steel_entry_weight_kg(Decimal(bar_dia_mm), Decimal(nos), Decimal(length_ft))
    return str(result)


def cost_head_billing_quantity(raw_quantity: str, conversion_factor: str) -> str:
    return str(Decimal(raw_quantity) * Decimal(conversion_factor))


def cost_head_amount(billing_quantity: str, rate_per_unit: str | None) -> str | None:
    if rate_per_unit is None:
        return None
    return str(Decimal(billing_quantity) * Decimal(rate_per_unit))
