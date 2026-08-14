"""Golden test against the real Narapally spreadsheet -- if this doesn't
reconcile against the sheet's own stated totals, the parser is wrong.
Not a synthetic fixture: resources/NARAPALLY MASONRY ESTIMATION.xlsx is
Protek Consult's actual estimation file.
"""

from decimal import Decimal
from pathlib import Path

import pytest

from importers.narapally_boq import parse_narapally_brick_work, to_project_export

XLSX_PATH = Path(__file__).parent.parent / "resources" / "NARAPALLY MASONRY ESTIMATION.xlsx"

pytestmark = pytest.mark.skipif(not XLSX_PATH.exists(), reason="resources/ is local-only, not checked in")


def test_all_brick_work_cost_heads_reconcile_against_the_sheets_own_totals():
    cost_heads = parse_narapally_brick_work(XLSX_PATH)

    assert len(cost_heads) == 4
    for ch in cost_heads:
        assert ch.sheet_stated_total is not None, f"{ch.name}: no sheet total captured"
        assert ch.reconciles, f"{ch.name}: computed={ch.computed_total} sheet={ch.sheet_stated_total}"


def test_wall_9in_flat_1_matches_the_known_figure():
    # Matches tests/fieldos/test_estimation_calc.py's golden value for this exact row.
    cost_heads = parse_narapally_brick_work(XLSX_PATH)
    wall_9in_flat1 = next(ch for ch in cost_heads if ch.name == 'WALL(9") (FLAT-1)')
    assert wall_9in_flat1.computed_total == Decimal("609.571875")


def test_flat_totals_match_the_sheets_grand_total_rows():
    cost_heads = parse_narapally_brick_work(XLSX_PATH)
    flat1_total = sum(ch.computed_total for ch in cost_heads if "FLAT-1" in ch.name)
    flat2_total = sum(ch.computed_total for ch in cost_heads if "FLAT-2" in ch.name)
    # Row 31 / row 29 GRAND TOTAL cells in the sheet.
    assert flat1_total == Decimal("1073.3139375")
    assert round(flat2_total, 6) == round(Decimal("935.6962499999998"), 6)


def test_to_project_export_produces_a_valid_shape():
    cost_heads = parse_narapally_brick_work(XLSX_PATH)
    export = to_project_export(cost_heads, "Narapally S+5")

    assert export["format"] == "fieldos.project_export.v1"
    assert export["project"]["name"] == "Narapally S+5"
    assert len(export["estimations"]) == 1
    cost_head_json = export["estimations"][0]["cost_heads"]
    assert len(cost_head_json) == 4
    assert all(c["calculation_type"] == "volume" for c in cost_head_json)
    # Deduction entries preserved and flagged.
    wall_9in = next(c for c in cost_head_json if c["name"] == 'WALL(9") (FLAT-1)')
    deductions = [e for e in wall_9in["measurement_entries"] if e["is_deduction"]]
    assert len(deductions) == 3  # D1, W1, V1
