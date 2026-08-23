"""Golden test for the general BRICK WORK / CONCRETE ESTIMATION importer
(importers/brick_and_concrete_boq.py), using Protek Consult's real
Thumukunta spreadsheet as the one concrete example currently available --
if this doesn't reconcile against the sheet's own stated totals, the
parser is wrong. Not a synthetic fixture: resources/THUMUKUNTA EST.xlsx is
Protek Consult's actual estimation file. The importer itself is general
(any workbook following the same sheet-layout convention), not specific to
this file -- see that module's docstring.
"""

from decimal import Decimal
from pathlib import Path

import pytest

from importers.brick_and_concrete_boq import parse_brick_work, parse_concrete_estimation, to_project_export

XLSX_PATH = Path(__file__).parent.parent / "resources" / "THUMUKUNTA EST.xlsx"

pytestmark = pytest.mark.skipif(not XLSX_PATH.exists(), reason="resources/ is local-only, not checked in")


def test_all_brick_work_cost_heads_reconcile_against_the_sheets_own_totals():
    cost_heads = parse_brick_work(XLSX_PATH)

    assert len(cost_heads) == 3
    for ch in cost_heads:
        assert ch.sheet_stated_total is not None, f"{ch.name}: no sheet total captured"
        assert ch.reconciles, f"{ch.name}: computed={ch.computed_total} sheet={ch.sheet_stated_total}"


def test_all_concrete_estimation_cost_heads_reconcile_against_the_sheets_own_totals():
    cost_heads = parse_concrete_estimation(XLSX_PATH)

    assert len(cost_heads) == 11
    for ch in cost_heads:
        assert ch.sheet_stated_total is not None, f"{ch.name}: no sheet total captured"
        assert ch.reconciles, f"{ch.name}: computed={ch.computed_total} sheet={ch.sheet_stated_total}"


def test_brick_work_groups_sum_to_the_sheets_1st_floor_grand_total():
    # Row 110's "TOTAL BRICK WORK FOR 1ST FLOOR" -- not its own cost head
    # (it's a whole-sheet total spanning all three groups, not a
    # measurable group of its own), cross-checked here instead.
    cost_heads = parse_brick_work(XLSX_PATH)
    total = sum((ch.computed_total for ch in cost_heads), Decimal(0))
    assert round(total, 6) == round(Decimal("2044.3359375"), 6)


def test_concrete_categories_sum_to_the_boq_abstracts_rcc_line():
    # Independently verified by hand against the BOQ sheet's own "RCC" row
    # while building this importer: Laying RCC + Pedestals + Columns +
    # Plinth Beams + Grade Slab + Beams + Staircase + net Roof Slab.
    cost_heads = parse_concrete_estimation(XLSX_PATH)
    rcc_names = {
        "LAYING RCC", "PEDESTALS", "COLUMNS", "PLINTH BEAMS", "GRADE SLAB", "BEAMS", "STAIRCASE", "ROOF SLAB",
    }
    total = sum((ch.computed_total for ch in cost_heads if ch.name.upper() in rcc_names), Decimal(0))
    assert round(total, 6) == round(Decimal("5702.620597222222"), 6)


def test_soil_filling_matches_the_boq_abstracts_earth_filling_line():
    # SOIL FILLING is expressed as excavation net of PCC/RCC/Pedestals --
    # the trickiest section to parse (see
    # importers/brick_and_concrete_boq.py's in_derived_category_body
    # comment). Matches the abstract's "EARTH FILLING" row exactly.
    cost_heads = parse_concrete_estimation(XLSX_PATH)
    soil_filling = next(ch for ch in cost_heads if ch.name.upper() == "SOIL FILLING")
    assert round(soil_filling.computed_total, 6) == round(Decimal("5189.7711"), 6)


def test_to_project_export_produces_two_estimations_with_volume_cost_heads():
    brick_heads = parse_brick_work(XLSX_PATH)
    concrete_heads = parse_concrete_estimation(XLSX_PATH)
    export = to_project_export(brick_heads, concrete_heads, "Thumukunta S+4")

    assert export["format"] == "fieldos.project_export.v1"
    assert export["project"]["name"] == "Thumukunta S+4"
    assert len(export["estimations"]) == 2

    names = {e["name"] for e in export["estimations"]}
    assert names == {"Brick Work BOQ (imported from Excel)", "RCC & Concrete Work BOQ (imported from Excel)"}

    for estimation in export["estimations"]:
        assert all(c["calculation_type"] == "volume" for c in estimation["cost_heads"])

    brick_export = next(e for e in export["estimations"] if "Brick" in e["name"])
    assert len(brick_export["cost_heads"]) == 3
    concrete_export = next(e for e in export["estimations"] if "RCC" in e["name"])
    assert len(concrete_export["cost_heads"]) == 11


def test_to_project_export_omits_empty_estimations_when_a_sheet_has_no_heads():
    # General-importer behavior: a workbook missing one of the two sheets
    # should produce an export with only the estimation(s) that have data,
    # not an empty-cost-heads estimation for the missing sheet.
    brick_heads = parse_brick_work(XLSX_PATH)
    export = to_project_export(brick_heads, [], "Some other project")

    assert len(export["estimations"]) == 1
    assert export["estimations"][0]["name"] == "Brick Work BOQ (imported from Excel)"


def test_parse_functions_return_empty_list_for_a_workbook_missing_the_sheet(tmp_path):
    import openpyxl

    wb = openpyxl.Workbook()
    wb.active.title = "Unrelated Sheet"
    empty_path = tmp_path / "empty.xlsx"
    wb.save(empty_path)

    assert parse_brick_work(empty_path) == []
    assert parse_concrete_estimation(empty_path) == []
