from dataclasses import dataclass
from decimal import Decimal

from fieldos.estimation_calc import (
    CALC_AREA,
    CALC_STEEL_WEIGHT,
    CALC_VOLUME,
    build_boq,
    cost_head_amount,
    cost_head_billing_quantity,
    cost_head_raw_quantity,
)


@dataclass
class FakeCostHead:
    id: str
    name: str
    calculation_type: str
    billing_unit: str
    conversion_factor: Decimal = Decimal("1")
    rate_per_unit: Decimal | None = None


@dataclass
class FakeEntry:
    length: Decimal | None
    width: Decimal | None
    depth: Decimal | None
    nos: Decimal
    is_deduction: bool = False


@dataclass
class FakeSteelEntry:
    bar_dia_mm: Decimal
    nos: Decimal
    length_ft: Decimal


def test_cost_head_raw_quantity_sums_volume_entries():
    cost_head = FakeCostHead(id="1", name="Brick Work", calculation_type=CALC_VOLUME, billing_unit="CFT")
    entries = [
        FakeEntry(Decimal("108.25"), Decimal("0.75"), Decimal("8.85"), Decimal("1")),
        FakeEntry(Decimal("3.5"), Decimal("0.75"), Decimal("7"), Decimal("1"), is_deduction=True),
    ]
    raw = cost_head_raw_quantity(cost_head, entries)
    assert raw == Decimal("718.509375") - Decimal("18.375")


def test_cost_head_billing_quantity_applies_conversion_factor():
    cost_head = FakeCostHead(
        id="1", name="RCC", calculation_type=CALC_VOLUME, billing_unit="CUM",
        conversion_factor=Decimal("1") / Decimal("35.3147"),
    )
    billing_qty = cost_head_billing_quantity(cost_head, Decimal("333"))
    assert round(billing_qty, 4) == round(Decimal("333") / Decimal("35.3147"), 4)


def test_cost_head_amount_is_none_without_a_rate():
    cost_head = FakeCostHead(id="1", name="Unpriced", calculation_type=CALC_AREA, billing_unit="SFT")
    assert cost_head_amount(cost_head, Decimal("100")) is None


def test_cost_head_amount_multiplies_billing_quantity_by_rate():
    cost_head = FakeCostHead(
        id="1", name="Plastering", calculation_type=CALC_AREA, billing_unit="SFT",
        rate_per_unit=Decimal("25"),
    )
    amount = cost_head_amount(cost_head, Decimal("12102.55"))
    assert amount == Decimal("302563.75")


def test_build_boq_rolls_up_multiple_cost_heads_with_profit():
    # Mirrors the shape of the real Vidyanagar ABSTRACT sheet: several priced
    # cost heads summed to a subtotal, plus a contractor profit percentage.
    brick = FakeCostHead(
        id="brick", name="Brick Masonry", calculation_type=CALC_VOLUME, billing_unit="CFT",
        rate_per_unit=Decimal("290"),
    )
    plaster = FakeCostHead(
        id="plaster", name="Plastering", calculation_type=CALC_AREA, billing_unit="SFT",
        rate_per_unit=Decimal("45"),
    )
    steel = FakeCostHead(
        id="steel", name="Steel Reinforcement", calculation_type=CALC_STEEL_WEIGHT,
        billing_unit="TONNES", conversion_factor=Decimal("0.001"), rate_per_unit=Decimal("87600"),
    )

    cost_heads_with_entries = [
        (brick, [FakeEntry(Decimal("10"), Decimal("1"), Decimal("10"), Decimal("1"))], []),
        (plaster, [FakeEntry(Decimal("100"), Decimal("50"), None, Decimal("1"))], []),
        (steel, [], [FakeSteelEntry(Decimal("16"), Decimal("10"), Decimal("100"))]),
    ]

    result = build_boq(cost_heads_with_entries, contractor_profit_percent=Decimal("10"))

    assert len(result.lines) == 3
    brick_line = next(line for line in result.lines if line.cost_head_id == "brick")
    assert brick_line.raw_quantity == Decimal("100")
    assert brick_line.amount == Decimal("29000")

    plaster_line = next(line for line in result.lines if line.cost_head_id == "plaster")
    assert plaster_line.raw_quantity == Decimal("5000")
    assert plaster_line.amount == Decimal("225000")

    expected_subtotal = brick_line.amount + plaster_line.amount + next(
        line for line in result.lines if line.cost_head_id == "steel"
    ).amount
    quantize_to = Decimal("1.0000000000")
    assert result.subtotal == expected_subtotal
    expected_profit = (expected_subtotal * Decimal("10") / Decimal("100")).quantize(quantize_to)
    assert result.contractor_profit_amount.quantize(quantize_to) == expected_profit
    assert result.grand_total == result.subtotal + result.contractor_profit_amount


def test_build_boq_excludes_unpriced_cost_heads_from_subtotal():
    unpriced = FakeCostHead(id="u", name="Unpriced Head", calculation_type=CALC_AREA, billing_unit="SFT")
    result = build_boq([(unpriced, [FakeEntry(Decimal("10"), Decimal("10"), None, Decimal("1"))], [])])
    assert result.lines[0].amount is None
    assert result.subtotal == Decimal(0)
    assert result.grand_total == Decimal(0)
