"""Golden tests against real numbers from resources/ (Narapally, Thumukunta).

If these don't match the real spreadsheets exactly, the calculation engine
is wrong — these are not invented examples.
"""

from decimal import Decimal

from fieldos.estimation_calc import (
    CALC_AREA,
    CALC_COUNT,
    CALC_VOLUME,
    measurement_entry_quantity,
    steel_entry_weight_kg,
    steel_unit_weight_kg_per_m,
)


def test_narapally_wall_9in_volume_matches_real_boq_sheet():
    # NARAPALLY MASONRY ESTIMATION.xlsx, BOQ sheet, FLAT-1 FIRST FLOOR WALL(9")
    # LENGTH=108.25, BREADTH=0.75, DEPTH=8.85, NOS=1 -> 718.509375 CFT
    qty = measurement_entry_quantity(
        CALC_VOLUME,
        length=Decimal("108.25"),
        width=Decimal("0.75"),
        depth=Decimal("8.85"),
        nos=Decimal("1"),
    )
    assert qty == Decimal("718.509375")


def test_narapally_deduction_d1_is_subtracted():
    # Same sheet, DEDUCTION (9" WALLS) D1 row: 3.5 x 0.75 x 7 x 1 = 18.375 CFT,
    # deducted from the gross wall quantity.
    qty = measurement_entry_quantity(
        CALC_VOLUME,
        length=Decimal("3.5"),
        width=Decimal("0.75"),
        depth=Decimal("7"),
        nos=Decimal("1"),
        is_deduction=True,
    )
    assert qty == Decimal("-18.375")


def test_thumukunta_footing_excavation_volume():
    # THUMUKUNTA EST.xlsx, CONCRETE ESTIMATION sheet, F1 excavation row:
    # 10.66 x 9.16 x 6.25 x 2 = 1220.57 CFT (sheet rounds to 2dp: 1220.57)
    qty = measurement_entry_quantity(
        CALC_VOLUME,
        length=Decimal("10.66"),
        width=Decimal("9.16"),
        depth=Decimal("6.25"),
        nos=Decimal("2"),
    )
    assert round(qty, 2) == Decimal("1220.57")


def test_area_calculation_ignores_depth():
    # Plastering-style entries: Length x Width x Nos, no depth.
    qty = measurement_entry_quantity(
        CALC_AREA,
        length=Decimal("10"),
        width=Decimal("12"),
        depth=None,
        nos=Decimal("2"),
    )
    assert qty == Decimal("240")


def test_count_calculation_ignores_dimensions():
    # Doors/windows: quantity is just Nos.
    qty = measurement_entry_quantity(
        CALC_COUNT,
        length=None,
        width=None,
        depth=None,
        nos=Decimal("14"),
    )
    assert qty == Decimal("14")


def test_steel_unit_weight_10mm_matches_thumukunta_slab_sheet():
    # THUMUKUNTA EST.xlsx, SLAB REINFORCEMENT sheet: 10mm bar -> WEIGHT(KG/M) = 0.6172839506172839
    weight = steel_unit_weight_kg_per_m(Decimal("10"))
    assert round(weight, 10) == round(Decimal("0.6172839506172839"), 10)


def test_steel_unit_weight_25mm_matches_thumukunta_column_sheet():
    # THUMUKUNTA EST.xlsx, COLUMN REINFORCEMENT sheet, C1 25mm bar -> 3.8580246913580245
    weight = steel_unit_weight_kg_per_m(Decimal("25"))
    assert round(weight, 10) == round(Decimal("3.8580246913580245"), 10)


def test_steel_unit_weight_20mm_matches_thumukunta_column_sheet():
    # C2/C3/C4 20mm bar -> 2.4691358024691357
    weight = steel_unit_weight_kg_per_m(Decimal("20"))
    assert round(weight, 10) == round(Decimal("2.4691358024691357"), 10)


def test_steel_unit_weight_16mm_matches_thumukunta_column_sheet():
    # 16mm bar -> 1.5802469135802468
    weight = steel_unit_weight_kg_per_m(Decimal("16"))
    assert round(weight, 10) == round(Decimal("1.5802469135802468"), 10)


def test_steel_entry_weight_matches_column_c1_25mm_row():
    # THUMUKUNTA EST.xlsx, COLUMN REINFORCEMENT, 1ST FLOOR, C1, dia 25:
    # NOS=16, LENGTH(FT)=10.5, LENGTH(M)=3.2012195121951224, TOTAL WEIGHT(KG)=197.60614272809397
    weight = steel_entry_weight_kg(
        bar_dia_mm=Decimal("25"),
        nos=Decimal("16"),
        length_ft=Decimal("10.5"),
    )
    assert round(weight, 4) == round(Decimal("197.60614272809397"), 4)


def test_deduction_entries_net_out_against_gross_quantity():
    gross = measurement_entry_quantity(
        CALC_VOLUME, Decimal("100"), Decimal("1"), Decimal("10"), Decimal("1")
    )
    deduction = measurement_entry_quantity(
        CALC_VOLUME, Decimal("5"), Decimal("1"), Decimal("10"), Decimal("2"), is_deduction=True
    )
    net = gross + deduction
    assert net == Decimal("1000") - Decimal("100")
