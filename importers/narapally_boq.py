"""Parses NARAPALLY MASONRY ESTIMATION.xlsx's BOQ sheet (brick work sections
only, for now -- see the automation roadmap) into ProjectExport-shaped data,
so it can go through the same import path as any other project export
(fieldos/routers/portability.py) -- no separate, unverified DB-writing code
path for spreadsheet-derived data.

The sheet is a dual-column layout (two flats side by side per row block),
not a clean table: section headers, "DEDUCTION" sub-headers, and "TOTAL" /
"GRAND TOTAL" marker rows are all just rows of the same shape with text in
different cells. This walks it as a small state machine per column-block,
using TOTAL-marker rows as reconciliation checkpoints against the sheet's
own arithmetic -- not just against our own formula.
"""

from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Optional

import openpyxl

# BOQ sheet column layout (0-indexed), two identical blocks side by side.
# span is the block's own column range -- used to scope marker-text
# detection (e.g. "GRAND TOTAL") to this block only. The two blocks are NOT
# row-aligned with each other (FLAT-2's rows drift relative to FLAT-1's
# partway down the sheet), so anything that scans outside a block's own
# columns risks reading the other flat's marker text.
LEFT = {"sno": 0, "desc": 1, "length": 4, "breadth": 5, "depth": 6, "nos": 7, "qty": 8, "unit": 9, "span": (0, 11)}
RIGHT = {"sno": 12, "desc": 13, "length": 16, "breadth": 17, "depth": 18, "nos": 19, "qty": 20, "unit": 21, "span": (12, 25)}

SECTION_HEADERS = {"BRICK WORK", "PLASTERING", "PAINTING", "FLOORING", "WOOD WORK", "WALL CLADDING"}
# Only brick work is parsed for now -- the other sections use different
# column semantics (e.g. plastering's "depth" column is actually height,
# and needs remapping to area calc's length*width, not parsed here yet).
SUPPORTED_SECTIONS = {"BRICK WORK"}


@dataclass
class MeasurementRow:
    description: str
    length: Decimal
    breadth: Decimal
    depth: Decimal
    nos: Decimal
    is_deduction: bool


@dataclass
class CostHeadDraft:
    name: str
    entries: list = field(default_factory=list)
    sheet_stated_total: Optional[Decimal] = None
    computed_total: Optional[Decimal] = None

    @property
    def reconciles(self) -> bool:
        if self.sheet_stated_total is None or self.computed_total is None:
            return False
        return abs(self.sheet_stated_total - self.computed_total) < Decimal("0.01")


def _dec(value) -> Optional[Decimal]:
    if value is None:
        return None
    return Decimal(str(value))


def _is_grand_total(row: tuple, span: tuple) -> bool:
    start, end = span
    return any(isinstance(v, str) and "GRAND TOTAL" in v.upper() for v in row[start : end + 1])


def _net_quantity(rows: list) -> Decimal:
    total = Decimal(0)
    for r in rows:
        qty = r.length * r.breadth * r.depth * r.nos
        total += -qty if r.is_deduction else qty
    return total


def _parse_block(rows: list, cols: dict, flat_label: str) -> list:
    """One column-block (one flat) of the BOQ sheet -> list of CostHeadDraft,
    scoped to BRICK WORK only. `rows` is the full sheet, in order.

    The sheet's own row shapes, not text labels, drive the state machine:
    a "rollup" row (blank description, only the qty cell populated) before
    any DEDUCTION header is a gross subtotal -- discarded, since it isn't
    the group's final figure. A rollup row seen *after* a DEDUCTION header
    is either the deduction subtotal or the group's net total; the sheet
    labels the very first group's net-total row "TOTAL" but leaves later
    groups' net-total rows unlabeled, so the reliable signal is structural:
    the LAST such post-deduction rollup before the next real entry (or
    GRAND TOTAL / section change) is the group's true net total.
    """
    cost_heads: list = []
    current_section: Optional[str] = None
    current_head: Optional[CostHeadDraft] = None
    is_deduction = False
    pending_rollups: list = []

    def close_current_head():
        nonlocal current_head, pending_rollups, is_deduction
        if current_head is not None:
            current_head.sheet_stated_total = pending_rollups[-1] if pending_rollups else None
            current_head.computed_total = _net_quantity(current_head.entries)
            cost_heads.append(current_head)
        current_head = None
        pending_rollups = []
        is_deduction = False

    for row in rows:
        desc = row[cols["desc"]]
        desc_text = str(desc).strip() if desc else ""
        length, nos, qty = row[cols["length"]], row[cols["nos"]], row[cols["qty"]]

        if desc_text.upper() in SECTION_HEADERS:
            close_current_head()
            current_section = desc_text.upper()
            continue

        if current_section not in SUPPORTED_SECTIONS:
            continue

        if _is_grand_total(row, cols["span"]):
            close_current_head()
            continue

        if desc_text.upper().startswith("DEDUCTION"):
            is_deduction = True
            continue

        if desc_text and length is not None and nos is not None:
            # A new entry while we're sitting on post-deduction rollups means
            # the previous group truly ended; a new entry while is_deduction
            # is False (or no rollups pending yet) just continues the group.
            if is_deduction and pending_rollups:
                close_current_head()
            if current_head is None:
                current_head = CostHeadDraft(name=f"{desc_text} ({flat_label})")
            current_head.entries.append(
                MeasurementRow(
                    description=desc_text,
                    length=_dec(length),
                    breadth=_dec(row[cols["breadth"]]) or Decimal(0),
                    depth=_dec(row[cols["depth"]]) or Decimal(0),
                    nos=_dec(nos),
                    is_deduction=is_deduction,
                )
            )
            continue

        if not desc_text and length is None and qty is not None:
            if is_deduction:
                pending_rollups.append(_dec(qty))
            # else: pre-deduction gross subtotal -- not the group's final figure, discard.
            continue

    close_current_head()
    return cost_heads


def parse_narapally_brick_work(xlsx_path: Path) -> list:
    """Returns a flat list of CostHeadDraft across both flats."""
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    ws = wb["BOQ"]
    rows = list(ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True))

    left = _parse_block(rows, LEFT, "FLAT-1")
    right = _parse_block(rows, RIGHT, "FLAT-2")
    return left + right


def to_project_export(cost_heads: list, project_name: str) -> dict:
    """CostHeadDraft list -> the ProjectExport JSON shape consumed by
    POST /companies/{id}/import (see fieldos/routers/portability.py)."""
    return {
        "format": "fieldos.project_export.v1",
        "project": {"name": project_name, "status": "planning"},
        "tasks": [],
        "dpr_entries": [],
        "issues": [],
        "estimations": [
            {
                "name": "Masonry BOQ (imported from Excel)",
                "status": "draft",
                "contractor_profit_percent": None,
                "cost_heads": [
                    {
                        "name": ch.name,
                        "calculation_type": "volume",
                        "raw_unit": "CFT",
                        "billing_unit": "CFT",
                        "conversion_factor": "1",
                        "rate_per_unit": None,
                        "sort_order": i,
                        "measurement_entries": [
                            {
                                "description": e.description,
                                "length": str(e.length),
                                "width": str(e.breadth),
                                "depth": str(e.depth),
                                "nos": str(e.nos),
                                "is_deduction": e.is_deduction,
                            }
                            for e in ch.entries
                        ],
                        "steel_entries": [],
                    }
                    for i, ch in enumerate(cost_heads)
                ],
            }
        ],
    }


if __name__ == "__main__":
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(
        description="Parse a Narapally-style BOQ workbook's brick work sections into a "
        "FieldOS project-export JSON file, importable via the app's 'Import project' button."
    )
    parser.add_argument("xlsx_path", type=Path)
    parser.add_argument("--project-name", default="Narapally S+5")
    parser.add_argument("-o", "--output", type=Path, default=None)
    args = parser.parse_args()

    heads = parse_narapally_brick_work(args.xlsx_path)

    mismatches = [ch for ch in heads if not ch.reconciles]
    for ch in heads:
        status = "ok" if ch.reconciles else "MISMATCH"
        print(f"[{status}] {ch.name}: computed={ch.computed_total} sheet={ch.sheet_stated_total}", file=sys.stderr)

    if mismatches:
        print(
            f"\n{len(mismatches)} cost head(s) don't reconcile against the sheet's own totals -- refusing to "
            "write an export file. Fix the parser or the input before trusting this data.",
            file=sys.stderr,
        )
        sys.exit(1)

    export = to_project_export(heads, args.project_name)
    output_path = args.output or args.xlsx_path.with_suffix(".fieldos-export.json")
    output_path.write_text(json.dumps(export, indent=2), encoding="utf-8")
    print(f"\nWrote {output_path} -- import it via FieldOS's 'Import project' button.", file=sys.stderr)
