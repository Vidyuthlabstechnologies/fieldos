# BOQ / Estimation Automation Module — Design

Status: Approved (2026-08-13)

## 1. Context & Goal

Protek Consult currently produces Bills of Quantities (BOQ) by hand in Excel —
see `resources/` for real examples (Narapally, Thumukunta, Vidyanagar). Each
project's estimation spreads across multiple spreadsheets and sheets
(earthwork, PCC, RCC/concrete, steel reinforcement with bar-bending
schedules, brick work, plastering, flooring, painting, doors/windows,
waterproofing, shuttering...), each computed by hand with
`Length × Width × Depth × Nos` formulas, unit conversions, opening
deductions, and rate multiplication — taking multiple people per project and
prone to silent arithmetic/transcription error.

This module replaces that with a single calculation engine inside FieldOS:
structured dimension entry in, quantities + priced BOQ out, computed once,
correctly, every time.

**In scope:** quantity takeoff (volume/area/steel-weight/count) for all cost
categories observed in the real sheets, rate-based pricing, BOQ rollup with
optional contractor profit %.

**Out of scope (explicitly, for this spec):** extracting dimensions from
floor-plan drawings/PDFs automatically (a much harder computer-vision
problem, deferred) — a person still enters the L×W×D×Nos numbers, same as
today, but the system does every calculation from there.

## 2. Core Insight: One Engine, Not Twelve Categories

Every category in the real sheets reduces to one of four calculation
patterns:

| Pattern | Formula | Examples from real sheets |
|---|---|---|
| **Volume** | `L × W × D × Nos → CFT` | Excavation, PCC, RCC, brick masonry |
| **Area** | `L × W × Nos → SFT` | Plastering, painting, flooring, waterproofing, shuttering |
| **Steel weight** | `dia → kg/m` (via `d²/162`, IS 1786 standard formula — verified this is exactly the formula Thumukunta's sheets use: e.g. `10²/162 = 0.6172839506172839`, matching the sheet's "WEIGHT(KG/M)" column for 10mm bars exactly), `Nos × Length(ft→m) × kg/m → kg` | Slab/beam/column reinforcement, stirrups (including bent-up bar rows, which are just additional entries with a different length) |
| **Count** | `Nos × Rate → Amount` directly | Doors, windows, ventilators |

So instead of 12 hardcoded category tables, there's one generic **CostHead**
(a BOQ line item, tagged with which pattern it uses) containing many
**MeasurementEntry** rows (the actual L×W×D×Nos data people type in, same
shape as the real sheets — including deduction rows for door/window
openings, exactly like Narapally's BOQ sheet) or **SteelEntry** rows (dia,
nos, length — steel needs its own shape since the weight formula is
different).

This means adding a new cost category (e.g. "false ceiling", seen in
Vidyanagar's ABSTRACT) never requires new code or a migration — it's just a
new `CostHead` row with the right `calculation_type`.

## 3. Data Model

- `estimations` — `id, project_id (FK), name, contractor_profit_percent (nullable Decimal), status (draft|final), created_by, created_at`
- `cost_heads` — `id, estimation_id (FK), name (e.g. "Brick Work - 9\" Walls"), calculation_type (volume|area|steel_weight|count), raw_unit (CFT|SFT|KG|NOS — computed directly from entries), billing_unit (CUM|SFT|TONNES|NOS — what the rate applies to), conversion_factor (Decimal — raw→billing, e.g. 1/35.3147 for CFT→CUM, 1/1000 for KG→TONNES, 1 otherwise), rate_per_unit (nullable Decimal), sort_order (int)`
- `measurement_entries` — `id, cost_head_id (FK), description, length (nullable Decimal), width (nullable Decimal), depth (nullable Decimal), nos (Decimal), is_deduction (bool, default False)`. Used for volume/area/count cost heads. Which of `length`/`width`/`depth` matter is determined by the parent `CostHead.calculation_type` (volume uses all three, area uses length×width, count uses `nos` alone).
- `steel_entries` — `id, cost_head_id (FK), description (e.g. "X-STRAIGHT BARS", "TOP MAIN"), bar_dia_mm (Decimal), nos (Decimal), length_ft (Decimal)`. Unit weight (kg/m) is *computed*, not entered, via `dia_mm² / 162` — removing a manual lookup-table error source entirely.

All quantity/rate/amount fields use `Decimal`, never `float` — floating
point rounding error compounding across hundreds of line items is exactly
the kind of silent mistake this module exists to eliminate.

## 4. Calculation Engine

Pure functions, no DB access, fully unit-testable in isolation:

- `entry_quantity(entry, calculation_type) -> Decimal` — per-row quantity (respects `is_deduction`, sign-flips deducted rows)
- `cost_head_raw_quantity(cost_head) -> Decimal` — sums all entries (or steel entries) belonging to a cost head
- `cost_head_billing_quantity(cost_head) -> Decimal` — `raw_quantity × conversion_factor`
- `cost_head_amount(cost_head) -> Decimal` — `billing_quantity × rate_per_unit` (or `None` if no rate set yet — quantities can exist before pricing)
- `estimation_boq(estimation) -> BOQResult` — per-cost-head line items + subtotal + contractor profit amount + grand total, mirroring the shape of the real Vidyanagar ABSTRACT sheet

## 5. Precision Verification ("ultra precision")

The test suite includes **golden tests using real numbers from
`resources/`**, not invented examples — e.g.:

- Narapally BOQ sheet, Wall(9") row: `108.25 × 0.75 × 8.85 × 1 = 718.509375 CFT` becomes a literal assertion.
- Thumukunta SLAB REINFORCEMENT, 10mm bar: `10² / 162 = 0.6172839506172839 kg/m` becomes a literal assertion on the weight-formula function.
- Thumukunta COLUMN REINFORCEMENT, C1 25mm bar: `25² / 162 = 3.8580246913580245 kg/m` — same formula, different diameter, cross-checks the formula isn't accidentally hardcoded to one value.

If the engine doesn't reproduce these exact real numbers, it's wrong —
that's the precision bar.

## 6. API Surface

New router `fieldos/routers/estimation.py`, mounted alongside the existing
Plan 1 routers, reusing the same `require_project_access` permission check
(an estimation belongs to a project, so project membership governs access —
no new role logic needed):

- `POST /projects/{project_id}/estimations` — create
- `GET /projects/{project_id}/estimations` — list
- `POST /estimations/{id}/cost-heads` — add a cost head
- `POST /cost-heads/{id}/entries` — add a measurement or steel entry (endpoint picks the right table based on the parent cost head's `calculation_type`)
- `GET /estimations/{id}/boq` — computed BOQ (quantities, amounts, total, profit)

## 7. Non-Goals

- Extracting dimensions from drawings automatically (noted above — future work).
- Rate-card management / historical rate database (rates are entered per cost head for now; a shared rate library is a natural future addition once this core engine is proven).
- Multi-currency (INR only, matching the real data).
