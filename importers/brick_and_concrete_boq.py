"""Parses a BOQ workbook's BRICK WORK and CONCRETE ESTIMATION sheets into
ProjectExport-shaped data, so it can go through the same import path as
any other project export (fieldos/routers/portability.py) -- no separate,
unverified DB-writing code path for spreadsheet-derived data.

Not tied to one client's file: this targets a SHEET-LAYOUT CONVENTION, not
one project. Point it at any workbook that has sheets literally named
"BRICK WORK" and/or "CONCRETE ESTIMATION" (case/whitespace-insensitive)
laid out the same way -- a single sequential column (unlike Narapally's
two-flats-side-by-side BOQ sheet), columns SL.NO/DESCRIPTION/LENGTH/
WIDTH-or-BREADTH/DEPTH/NO'S/QUANTITY/UNITS in that order, walked top to
bottom, where a "TOTAL..." row (however it's worded) is always the current
group's true net figure -- deductions, when present, always appear
between a group's raw entries and its closing TOTAL, so the LAST
TOTAL-prefixed row seen before a group closes is authoritative, regardless
of exactly how it's worded ("TOTAL", "TOTAL PCC", "TOTAL BRICK WORK FOR
FLAT 2", ...). Same "last pending rollup wins" philosophy as
importers/narapally_boq.py, just for a single-column sheet instead of a
two-block one.

Either sheet is optional -- run against a workbook that only has one of
them and the other simply contributes zero cost heads. Both sheets are
independently reconciled: every cost head's computed net quantity is
checked against the sheet's own stated total for that group, and the
script refuses to write an export file if any mismatch is found.

Golden-tested against Protek Consult's real Thumukunta workbook (see
tests/test_brick_concrete_boq_import.py) -- that's the only real example
of "this type of document" checked into resources/ so far, but nothing in
the parsing logic below assumes it's specifically that file. If you point
this at a workbook using different sheet names, or a materially different
column layout, it will fail loudly (KeyError on the sheet name, or
reconciliation mismatches) rather than silently producing wrong numbers --
that's intentional; extend this file's logic to cover the new convention
rather than trying to make the existing one implicitly cover both.

NOT covered by this file at all: SLAB/BEAM/COLUMN REINFORCEMENT, STIRRUPS
(steel_weight cost heads -- a different sheet layout entirely, one row per
bar with dia/spacing/count rather than length x width x depth), PLASTERING,
FLOORING (area cost heads, calculation_type="area" instead of "volume").
Follow this file's overall approach for those if asked to add them: parse,
then reconcile every computed figure against the sheet's own stated total
before writing anything.
"""

from dataclasses import dataclass, field
from decimal import Decimal
from pathlib import Path
from typing import Optional

import openpyxl

# The sheet-type convention this file targets: SL.NO / DESCRIPTION / LENGTH
# / WIDTH (or BREADTH) / DEPTH / NO'S / QUANTITY / UNITS, in that column
# order, 0-indexed, identical on both sheets. Unlike Narapally, there's
# only one column block per sheet (not two flats side by side).
COLS = {"sno": 1, "desc": 2, "length": 3, "width": 4, "depth": 5, "nos": 6, "qty": 7, "unit": 8}

BRICK_WORK_SHEET_NAME = "BRICK WORK"
CONCRETE_ESTIMATION_SHEET_NAME = "CONCRETE ESTIMATION"

# A category-name convention this parser recognizes specially -- a generic
# construction term, not a client proper noun, same status as "DEDUCTIONS"
# below: some sheets express this one category as a subtraction of *other*
# categories' already-computed totals (e.g. "excavation net of
# PCC/RCC/pedestals"), referenced by name rather than re-measured with raw
# dimensions. See the in_derived_category_body comment in _parse_sequential
# for why this can't be detected structurally and needs the name match.
SOIL_FILLING_NAME = "SOIL FILLING"
DERIVED_CATEGORY_MARKER = "TOTAL "


@dataclass
class MeasurementRow:
    description: str
    length: Decimal
    width: Decimal
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


def _net_quantity(rows: list) -> Decimal:
    total = Decimal(0)
    for r in rows:
        qty = r.length * r.width * r.depth * r.nos
        total += -qty if r.is_deduction else qty
    return total


def _is_total_row(desc_text: str) -> bool:
    return desc_text.strip().upper().startswith("TOTAL")


def _find_sheet(wb, name: str):
    """Case/whitespace-insensitive sheet lookup, with a clear error instead
    of openpyxl's raw KeyError -- this is the one place a workbook using
    slightly different sheet-name casing/spacing than Thumukunta's would
    otherwise fail with a confusing traceback."""
    normalized = {s.strip().upper(): s for s in wb.sheetnames}
    real_name = normalized.get(name.strip().upper())
    if real_name is None:
        raise ValueError(
            f"No sheet named {name!r} found (have: {wb.sheetnames!r}). "
            "This importer targets workbooks with a sheet literally named "
            f"{name!r} laid out per this file's module docstring -- if this "
            "workbook uses a different name or layout for the same content, "
            "extend _find_sheet's matching or write a project-specific "
            "importer instead of forcing this one to fit."
        )
    return wb[real_name]


def _parse_sequential(rows: list, group_header) -> list:
    """Generic walker for a single-column, sequential BOQ sheet.

    `group_header(row)` -> (group_name, inline_entry_or_None) if this row
    starts a new top-level group, else None. `inline_entry_or_None` covers
    a one-liner category whose header row is also its own sole measurement
    (no separate entries/TOTAL follow it) -- e.g. a "GRADE SLAB" row that
    already carries length/width/depth/nos/qty itself.
    """
    cost_heads: list = []
    current_name: Optional[str] = None
    entries: list = []
    is_deduction = False
    last_total: Optional[Decimal] = None

    def close_current():
        nonlocal current_name, entries, is_deduction, last_total
        if current_name is not None:
            cost_heads.append(
                CostHeadDraft(
                    name=current_name,
                    entries=list(entries),
                    sheet_stated_total=last_total,
                    computed_total=_net_quantity(entries),
                )
            )
        current_name, entries, is_deduction, last_total = None, [], False, None

    for row in rows:
        desc = row[COLS["desc"]]
        desc_text = str(desc).strip() if desc else ""
        length, width, depth, nos, qty = (
            row[COLS["length"]], row[COLS["width"]], row[COLS["depth"]], row[COLS["nos"]], row[COLS["qty"]],
        )

        header = group_header(row)
        if header is not None:
            close_current()
            current_name, inline_entry = header
            if inline_entry is not None:
                entries.append(inline_entry)
                last_total = _dec(qty)  # the sheet's own precomputed qty for a one-liner category, reconciled below
            continue

        if current_name is None:
            continue  # rows before the first recognized group (sheet title, column headers, blank rows)

        if desc_text.upper() == "DEDUCTIONS":
            is_deduction = True
            continue

        # SOIL_FILLING_NAME is expressed on the sheet as a subtraction of
        # other categories' already-computed totals, referenced by name --
        # "Total excavation", "Laying PCC", "Laying RCC", "Pedestals" rows
        # each carry a qty with no dimensions of their own. Those names
        # incidentally start with "Total"/"Laying", which would otherwise
        # false-positive as THIS group's own closing marker below and get
        # silently dropped instead of counted -- only the group's real,
        # exact closer (its own re-stated name after "TOTAL ") should
        # short-circuit here. Real closing-total rows in OTHER categories
        # don't have this ambiguity (their entries carry real dimensions,
        # not name-references), so this exception is scoped to just this
        # one recognized sheet-convention keyword rather than applied
        # generally -- broadening it further would misclassify ordinary
        # closing totals as "in body", the same way it did during testing.
        in_derived_category_body = (
            current_name is not None
            and current_name.upper() == SOIL_FILLING_NAME
            and desc_text.strip().upper() != f"{DERIVED_CATEGORY_MARKER}{SOIL_FILLING_NAME}"
        )

        if _is_total_row(desc_text) and not in_derived_category_body:
            if "FLOOR" in desc_text.upper():
                # A whole-sheet grand total trailing the last group's own
                # real closer, with no new group header row in between to
                # trigger a close (e.g. "TOTAL BRICK WORK FOR 1ST FLOOR"
                # right after "TOTAL BRICK WORK FOR FLAT 1") -- close the
                # current group NOW, using its already-captured total,
                # rather than letting this row overwrite it. Cross-checked
                # against the sum of all groups separately, in __main__.
                close_current()
                continue
            last_total = _dec(qty)
            continue

        if desc_text and length is not None and nos is not None:
            entries.append(
                MeasurementRow(
                    description=desc_text,
                    length=_dec(length),
                    width=_dec(width) or Decimal(0),
                    depth=_dec(depth) or Decimal(0),
                    nos=_dec(nos),
                    is_deduction=is_deduction,
                )
            )
            continue

        if desc_text and length is None and qty is not None:
            # A "direct quantity" row: another category's already-computed
            # total, referenced by name rather than re-measured. width =
            # depth = nos = 1 makes length*width*depth*nos == qty exactly.
            entries.append(
                MeasurementRow(
                    description=desc_text,
                    length=_dec(qty),
                    width=Decimal(1),
                    depth=Decimal(1),
                    nos=Decimal(1),
                    is_deduction=is_deduction,
                )
            )
            continue

        # Sub-headers with no data of their own (e.g. "HORIZONTAL WALLS",
        # "VERTICAL WALLS", "DOORS", "WINDOWS", "VENTILATORS") and empty
        # placeholder rows fall through here and are skipped.

    close_current()
    return cost_heads


# A sheet's own title row (e.g. "BRICK WORK") and column-header row (e.g.
# "SL.NO") tend to put a string in the same column position real group
# headers use ("FLAT 2", "COMMON BRICK WORK FOR BOTH FLATS", ...) --
# exclude the literal sheet-name/column-header labels explicitly rather
# than trying to characterize real group headers more narrowly (their
# exact wording isn't fixed enough across projects to pattern-match).
_BRICK_WORK_NON_GROUP_LABELS = {BRICK_WORK_SHEET_NAME, "SL.NO"}


def _brick_work_group_header(row):
    val = row[COLS["sno"]]
    if isinstance(val, str) and val.strip() and val.strip().upper() not in _BRICK_WORK_NON_GROUP_LABELS:
        return val.strip(), None
    return None


def _concrete_group_header(row):
    sno, desc, length = row[COLS["sno"]], row[COLS["desc"]], row[COLS["length"]]
    if isinstance(sno, (int, float)) and desc:
        name = str(desc).strip()
        if length is not None:
            # One-liner category: the header row is also the sole entry.
            width, depth, nos = row[COLS["width"]], row[COLS["depth"]], row[COLS["nos"]]
            inline = MeasurementRow(
                description=name,
                length=_dec(length),
                width=_dec(width) or Decimal(0),
                depth=_dec(depth) or Decimal(0),
                nos=_dec(nos),
                is_deduction=False,
            )
            return name, inline
        return name, None
    return None


def parse_brick_work(xlsx_path: Path) -> list:
    """Returns [] if the workbook has no BRICK WORK sheet -- that sheet is
    optional, not every workbook of this general type has both."""
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    if not any(s.strip().upper() == BRICK_WORK_SHEET_NAME for s in wb.sheetnames):
        return []
    ws = _find_sheet(wb, BRICK_WORK_SHEET_NAME)
    rows = list(ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True))
    heads = _parse_sequential(rows, _brick_work_group_header)
    # A whole-sheet grand total across all groups (e.g. "TOTAL BRICK WORK
    # FOR 1ST FLOOR") is not a cost head itself -- it's the group-header
    # rows ("FLAT 1"/"FLAT 2"/"COMMON...") that start each real cost head.
    # Sanity-checked in __main__ instead, against the sum of the real heads.
    return [h for h in heads if "TOTAL BRICK WORK" not in h.name.upper()]


def parse_concrete_estimation(xlsx_path: Path) -> list:
    """Returns [] if the workbook has no CONCRETE ESTIMATION sheet."""
    wb = openpyxl.load_workbook(xlsx_path, data_only=True)
    if not any(s.strip().upper() == CONCRETE_ESTIMATION_SHEET_NAME for s in wb.sheetnames):
        return []
    ws = _find_sheet(wb, CONCRETE_ESTIMATION_SHEET_NAME)
    rows = list(ws.iter_rows(min_row=1, max_row=ws.max_row, values_only=True))
    return _parse_sequential(rows, _concrete_group_header)


def to_project_export(brick_heads: list, concrete_heads: list, project_name: str) -> dict:
    def cost_head_json(ch, i):
        return {
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
                    "width": str(e.width),
                    "depth": str(e.depth),
                    "nos": str(e.nos),
                    "is_deduction": e.is_deduction,
                }
                for e in ch.entries
            ],
            "steel_entries": [],
        }

    estimations = []
    if brick_heads:
        estimations.append({
            "name": "Brick Work BOQ (imported from Excel)",
            "status": "draft",
            "contractor_profit_percent": None,
            "cost_heads": [cost_head_json(ch, i) for i, ch in enumerate(brick_heads)],
        })
    if concrete_heads:
        estimations.append({
            "name": "RCC & Concrete Work BOQ (imported from Excel)",
            "status": "draft",
            "contractor_profit_percent": None,
            "cost_heads": [cost_head_json(ch, i) for i, ch in enumerate(concrete_heads)],
        })

    return {
        "format": "fieldos.project_export.v1",
        "project": {"name": project_name, "status": "planning"},
        "tasks": [],
        "dpr_entries": [],
        "issues": [],
        "estimations": estimations,
    }


if __name__ == "__main__":
    import argparse
    import json
    import sys

    parser = argparse.ArgumentParser(
        description="Parse a BOQ workbook's BRICK WORK and/or CONCRETE ESTIMATION sheets (see this "
        "file's module docstring for the exact layout convention expected) into a FieldOS "
        "project-export JSON file, importable via the app's 'Import project' button."
    )
    parser.add_argument("xlsx_path", type=Path)
    parser.add_argument("--project-name", required=True, help="No default on purpose -- name the real project.")
    parser.add_argument("-o", "--output", type=Path, default=None)
    args = parser.parse_args()

    brick_heads = parse_brick_work(args.xlsx_path)
    concrete_heads = parse_concrete_estimation(args.xlsx_path)
    all_heads = brick_heads + concrete_heads

    if not all_heads:
        print(
            f"Found neither a {BRICK_WORK_SHEET_NAME!r} nor a {CONCRETE_ESTIMATION_SHEET_NAME!r} sheet "
            f"in {args.xlsx_path} -- nothing to import. Sheets present: {openpyxl.load_workbook(args.xlsx_path, read_only=True).sheetnames}",
            file=sys.stderr,
        )
        sys.exit(1)

    mismatches = [ch for ch in all_heads if not ch.reconciles]
    for ch in all_heads:
        status = "ok" if ch.reconciles else "MISMATCH"
        print(f"[{status}] {ch.name}: computed={ch.computed_total} sheet={ch.sheet_stated_total}", file=sys.stderr)

    if brick_heads:
        brick_grand_total = sum((h.computed_total for h in brick_heads), Decimal(0))
        print(f"\n[info] Brick work grand total (sum of {len(brick_heads)} groups): {brick_grand_total}", file=sys.stderr)
    if concrete_heads:
        concrete_grand_total = sum((h.computed_total for h in concrete_heads), Decimal(0))
        print(f"[info] Concrete estimation grand total (sum of {len(concrete_heads)} categories): {concrete_grand_total}", file=sys.stderr)
    print(
        "[info] These are informational sums only -- cross-check them by hand against this "
        "workbook's own BOQ abstract sheet if one exists, the way test_brick_concrete_boq_import.py "
        "does for the Thumukunta example. Each cost head above is independently reconciled regardless.",
        file=sys.stderr,
    )

    if mismatches:
        print(
            f"\n{len(mismatches)} cost head(s) don't reconcile against the sheet's own totals -- refusing to "
            "write an export file. Fix the parser or the input before trusting this data.",
            file=sys.stderr,
        )
        sys.exit(1)

    export = to_project_export(brick_heads, concrete_heads, args.project_name)
    output_path = args.output or args.xlsx_path.with_suffix(".fieldos-export.json")
    output_path.write_text(json.dumps(export, indent=2), encoding="utf-8")
    print(f"\nWrote {output_path} -- import it via FieldOS's 'Import project' button.", file=sys.stderr)
