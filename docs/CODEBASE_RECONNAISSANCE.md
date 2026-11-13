# FieldOS Codebase Reconnaissance

Read-only recon. No application code was modified to produce this document. Sources: direct reading of `AGENTS.md` and `docs/*.md`, and nine parallel code-reading passes over `fieldos/`, `frontend/`, `fieldos_mobile/`, `src-tauri/`, `importers/`, `tests/`, and `resources/` (structure only, no real client figures reproduced anywhere below). Every claim below is either **CODE** (verified against source), **ARTIFACT** (verified against the real Protek Consult spreadsheets/PDFs, structure only), **DOCUMENTATION** (what a `docs/*.md`/`AGENTS.md` file states), **CUSTOMER** (something Protek Consult told us, per the task brief), or **INFERENCE** (a conclusion we're drawing, not a fact anyone stated). Tags are given wherever the distinction matters, especially in §22–§24.

---

## 1. Executive architecture

**CODE.** FieldOS is two independent products sharing a construction-domain vocabulary but no runtime connection:

- **Desktop**: Tauri (Rust) shell → loads `frontend/out` (Next.js static export) → spawns a PyInstaller-bundled FastAPI backend as a loopback-only sidecar process (fixed port 8000, no dynamic negotiation) → SQLite file under `%LOCALAPPDATA%\Predictera\FieldOS\fieldos.db` (`platformdirs`). Alembic migrations run automatically on every startup.
- **Mobile**: native Flutter app (`fieldos_mobile/`), fully standalone. Own local username/password auth, own Drift/SQLite database, own independently-maintained Dart port of the BOQ calculation engine. **Makes zero HTTP calls to the FastAPI backend** — confirmed by repo-wide grep, corroborated by three separate agents. The only outbound network call anywhere in the mobile app is to Sarvam AI, and only when voice-to-DPR is actually used.

There is no server, no Postgres, no Redis, no CDN, and — as of this recon — **no working synchronization between the desktop and mobile data stores**. A company using both today has two silently-separate data silos. This is DOCUMENTATION's own stated position (`docs/MOBILE_GUIDE.md`'s "Known architectural gap" section) and CODE confirms it exactly: no export/import consumer exists on the mobile side for the desktop's project-export JSON format, despite a stale comment in `fieldos_mobile/lib/data/tables.dart` claiming table-level parity with the server schema.

The one real online dependency in the whole system is **Sarvam AI**, used identically in spirit (not in wiring) on both platforms for voice-to-DPR transcription + structuring.

## 2. Repository structure

```
fieldos/            FastAPI backend — models, schemas, auth, permissions, routers, calc engine, Sarvam integration
frontend/            Next.js 16 static-export web app (the desktop app's UI layer)
fieldos_mobile/       Native Flutter app — fully independent, offline-first
src-tauri/            Rust desktop shell — wraps frontend/out + the PyInstaller backend sidecar
importers/            Standalone Python scripts that turn real client Excel BOQs into FieldOS project-export JSON
tests/                Backend pytest suite (tests/fieldos/) + top-level importer golden tests
docs/                 This documentation set
resources/            Real Protek Consult client data (gitignored, never committed — see §8)
```

`frontend/android/` (a Capacitor/WebView wrapper) also exists on disk. DOCUMENTATION (`docs/PROJECT_OVERVIEW.md`, `docs/MOBILE_GUIDE.md`) is explicit that this is deprecated in favor of `fieldos_mobile/` and should not be built on. Not independently re-verified by code reading in this recon; taken as DOCUMENTATION at face value since it matches the "native Flutter is canonical" framing every other doc and every mobile-facing agent finding is consistent with.

## 3. Backend map

**CODE.** Top-level `fieldos/*.py`:

| File | Purpose |
|---|---|
| `app.py` | FastAPI app factory: CORS allowlist (4 explicit loopback/Tauri origins, no wildcard), registers 18 routers (19 including `workers._attendance_router`) |
| `models.py` | All SQLAlchemy ORM models (see §4) |
| `schemas.py` | All Pydantic request/response schemas (804 lines) |
| `auth.py` | Opaque session-token auth (not JWT): `secrets.token_urlsafe(32)`, 30-day TTL, SHA-256-prehash + bcrypt password hashing |
| `permissions.py` | Role/membership-based authorization: `require_project_access`, `require_company_role`, `require_any_owner_role` |
| `db.py` | SQLAlchemy engine/session factory (`sqlite:///./fieldos_dev.db` in dev), per-request `get_db()` |
| `paths.py` | `platformdirs`-based app-data/uploads dir resolution for the packaged desktop app (`APP_NAME="FieldOS"`, `APP_AUTHOR="Predictera"`) |
| `config.py` | `pydantic_settings.BaseSettings`: `database_url`, `sarvam_api_key`, `max_upload_mb` |
| `storage.py` | Local file storage: MIME/extension allowlist, size cap, traversal-safe path resolution, collision-proof naming |
| `sarvam.py` | Sarvam AI integration — STT + LLM structuring, the one outbound-internet call on the backend |
| `estimation_calc.py` | Pure, DB-free Decimal-based BOQ math — deliberately kept exact/unrounded so it can be golden-tested against real client sheets |

Routers are covered fully in §5.

## 4. Database/domain model

**CODE**, cross-checked against `docs/DATABASE_SCHEMA.md` (which matches closely — see the one discrepancy noted at the end of this section). All models live in `fieldos/models.py`, SQLite, Decimal for every monetary/quantity column.

```
Company → CompanyMember
Company → Project → Task
                  → DPREntry → DPRPhoto
                  → Issue (optionally → DPREntry via dpr_entry_id)
                  → MaterialEntry → MaterialPhoto
                  → Worker → Attendance
                  → Document
                  → Estimation → CostHead → MeasurementEntry
                                          → SteelEntry
                  → PurchaseRequisition → RFQ → Quote → PurchaseOrder → GRN
                  → Equipment → EquipmentLog
                  → Inspection → InspectionItem
                               → InspectionPhoto
                  → ProjectMember
Company → Vendor (cross-project — referenced by Quote/PurchaseOrder, shared across a company's projects)
Company → CompanySubscription → SubscriptionPlan (referenced)
Company → BillingEvent
User → Session
```

Notable structural facts:
- Almost none of this tree is expressed as ORM `relationship()` objects — only `Company.members` and `CostHead.measurement_entries/steel_entries` are real mapped relationships. Everything else is FK columns queried directly by `project_id`/`company_id` in each router. Not a bug, just means there's no `project.tasks` convenience accessor anywhere.
- **`CompanyMember.user_id` and `ProjectMember.user_id` are plain `String(64)` columns with no `ForeignKey("users.id")`** — membership rows are not referentially tied to `User` at the database level. `docs/DATABASE_SCHEMA.md` quietly reflects this correctly (it annotates every other FK column with `(FK → x.id)` but leaves `user_id` bare in `company_members`/`project_members`) — an accurate detail, not an oversight in the doc.
- Entities checked for and confirmed **NOT IMPLEMENTED**: a distinct RFQ→vendor recipient join table (only `Quote.vendor_id` records who responded, not who was invited, despite `RFQCreate.vendor_ids` existing at the Pydantic layer with nothing behind it); NCR (inspection failure is just `InspectionItem.status == "fail"`, no dedicated entity/workflow); payroll (Worker has `daily_wage`, nothing computes wage × attendance into a payroll record); Notification/AuditLog/ActivityLog; Contract as a distinct entity (only a `Document.category` value); Building/Floor/Room/Structural-Element as modeled entities (these exist only as free-text names on `CostHead`/measurement descriptions, e.g. "FLAT 1" — see §8).
- Domain-entity existence matrix (backend / mobile / frontend / importer):

| Entity | Backend model | Mobile (Drift) | Frontend UI | Importer output |
|---|---|---|---|---|
| Project | EXISTS | EXISTS | EXISTS | EXISTS (name only) |
| Task | EXISTS | EXISTS | EXISTS (embedded, no standalone page) | NOT emitted |
| DPR | EXISTS | EXISTS | EXISTS (embedded) | NOT emitted |
| Issue | EXISTS | EXISTS (via approvals flow) | **NOT IMPLEMENTED** (dashboard count only) | NOT emitted |
| Estimation/CostHead/MeasurementEntry/SteelEntry | EXISTS | EXISTS (schema only, no write UI — §6, §10) | Read-only (§9) | EXISTS — this is the importers' entire purpose |
| Material | EXISTS | Partial (folded into GRN receipts, no catalog) | EXISTS | NOT emitted |
| Worker | EXISTS | **NOT IMPLEMENTED as a table** (free-text names typed at punch-in — see §10, contradicts `docs/MOBILE_GUIDE.md`'s "worker directory" claim) | EXISTS | NOT emitted |
| Attendance | EXISTS | EXISTS (manual lat/lng entry, not device GPS) | EXISTS | NOT emitted |
| Equipment | EXISTS | **NOT IMPLEMENTED** | EXISTS | NOT emitted |
| Inspection/NCR | EXISTS (no NCR) | **NOT IMPLEMENTED** | EXISTS | NOT emitted |
| Document/Drawing | EXISTS (generic, "drawing" is a category value) | **NOT IMPLEMENTED** | EXISTS (upload/list; no download/view link — §13) | NOT emitted |
| Vendor/RFQ/Quote/PO/GRN | EXISTS, full chain | EXISTS, full parallel chain | EXISTS, most fully-wired feature area | NOT emitted |
| Building/Floor/Room/Structural Element | **NOT IMPLEMENTED** anywhere as a modeled entity | — | — | Represented only as free-text cost-head names (ARTIFACT, §8) |

Minor unresolved item: `docs/DATABASE_SCHEMA.md` states "as of 21 Aug 2026" that all 33 tables have migrations; a manual count of the models found in this recon (User, Session, AppSetting, Company, CompanyMember, Project, ProjectMember, Task, DPREntry, DPRPhoto, Issue, MaterialEntry, MaterialPhoto, Worker, Attendance, Document, PurchaseRequisition, RFQ, Quote, PurchaseOrder, GRN, Equipment, EquipmentLog, Inspection, InspectionItem, InspectionPhoto, Estimation, CostHead, MeasurementEntry, SteelEntry, Vendor, SubscriptionPlan, CompanySubscription, BillingEvent) comes to 34. Off-by-one against the doc's stated count — not independently re-verified by directly running Alembic; flagged as a loose end rather than a confirmed defect.

## 5. API/router map

**CODE.** 19 router mounts across 18 files, all behind `get_current_user` except where noted. Full per-router endpoint/auth/model detail (too long to repeat here) confirms **consistent authorization** across every data-touching endpoint: every router resolves back to a project via `require_project_access` or a stricter `require_company_role`, including documents, materials, procurement, inspections, dpr, workers, and the realtime WebSocket. Role-based tiers (e.g., worker-roster mutation and vendor creation require owner/PM; plain viewing/attendance-marking requires only project membership) read as intentional privilege design, not gaps — this is the one place all nine agents' findings agreed with zero contradiction.

Exceptions to bearer-header auth, both deliberate and documented in-code: `/billing/webhook` (Stripe-signature-verified, no user auth), the WebSocket (`?token=` query param, headers unavailable pre-handshake), and `/uploads/{key}` (bearer **or** `?token=`, for `<img>`/`<a>` tags that can't set headers).

**DOCUMENTATION vs CODE disagreements found** (this matters — the task explicitly asked not to trust docs blindly):

- `docs/API_REFERENCE.md` documents `GET /companies`, `GET /companies/{id}`, `POST /companies/{id}/members`, `GET /companies/{id}/members`. **None of these exist.** `fieldos/routers/companies.py` is 37 lines with exactly two endpoints: `POST /companies` and `GET /companies/mine`. Corroborated independently by the frontend-map agent, which found no company-member-management UI *and* no backend route for it anywhere in the routers it grepped.
- `docs/API_REFERENCE.md` documents `PATCH /projects/{id}` (update project). **Does not exist.** `fieldos/routers/projects.py` has exactly 4 endpoints: `POST /projects`, `GET /projects?company_id=`, `GET /projects/{id}`, `POST /projects/{id}/members`.
- `docs/API_REFERENCE.md` documents `POST /projects/{id}/export`. The actual method is **GET** (`fieldos/routers/portability.py:43`) — and `docs/DEVELOPMENT.md`'s own Portability section correctly says `GET /projects/{id}/export`, so this is an internal documentation inconsistency, not just a doc/code one.
- `docs/API_REFERENCE.md`'s WebSocket section documents the message-type union (`task_update|dpr_update|material_update|...`) as if these are what the server actually sends. **They are not currently sent by anything** — see §12. The doc describes the intended/aspirational shape of the feature, not its current behavior.
- Minor omissions (not contradictions): `GET /auth/me` and `POST /projects/{id}/dpr/{dpr_id}/photos` both exist in code but aren't listed in `docs/API_REFERENCE.md`.

## 6. Estimation engine

**CODE, this was traced in depth (high priority per the task brief).**

**Model layers**: `Estimation` → `CostHead` (one of `calculation_type` ∈ {`volume`, `area`, `steel_weight`, `count`}) → `MeasurementEntry` (volume/area/count heads) or `SteelEntry` (steel_weight heads, mutually exclusive, enforced at the API layer with a 422 if the wrong entry type is posted to a cost head).

**Quantity/rate storage**: `MeasurementEntry.length/width/depth/nos` are `Numeric(14,6)`; `SteelEntry.bar_dia_mm` is `Numeric(6,2)`, `nos`/`length_ft` are `Numeric(14,6)`; `CostHead.conversion_factor` is `Numeric(18,10)`; `CostHead.rate_per_unit` is `Numeric(14,2)`, nullable (a cost head can exist un-priced). All map to Python `Decimal`. Pydantic schemas mirror these bounds via `Field(max_digits=..., decimal_places=...)` — a deliberate guard, since SQLite doesn't enforce `NUMERIC` precision/scale itself and an out-of-bounds value would otherwise reach `Decimal.quantize()` deep in the calc engine and 500. This guard exists for the estimation subsystem specifically; procurement/material/equipment/worker schemas do **not** have the equivalent bound even though their DB columns are also `Numeric` (a real, if minor, consistency gap — see §24).

**Amount calculation, exact formula path** (`fieldos/estimation_calc.py`, pure/DB-free):
1. `measurement_entry_quantity()` — volume = `length×width×depth×nos`, area = `length×width×nos`, count = `nos`; deduction rows return the negated quantity.
2. `cost_head_raw_quantity()` — sums entry quantities (or, for steel, sums `steel_entry_weight_kg()`: `weight_kg = nos × (length_ft / 3.28) × (bar_dia_mm² / 162)`, the `162` divisor being the IS 1786 standard unit-weight formula, and `3.28` a deliberately rounded ft→m factor chosen to match Protek's real sheets rather than the precise 0.3048).
3. `cost_head_billing_quantity()` — `raw_quantity × conversion_factor` (unit conversion, e.g. CFT→CUM).
4. `cost_head_amount()` — `billing_quantity × rate_per_unit`, or `None` if unpriced.
5. `build_boq()` — sums non-null amounts into `subtotal`; `profit_amount = subtotal × contractor_profit_percent / 100` if set; `grand_total = subtotal + profit_amount`.

No rounding happens inside the calc engine by design (module docstring is explicit this avoids compounding error across hundreds of line items). Rounding happens only at the API boundary in `fieldos/routers/estimation.py` (`ROUND_HALF_UP` to 2dp for money, 6dp for quantities), because SQLite's `Numeric` read-back pads to full declared scale and unrounded products would otherwise be unusable in a UI.

**Import path, traced end to end**: Excel workbook → `importers/*.py` parses rows into `MeasurementRow`/`CostHeadDraft` dataclasses → each `CostHeadDraft.reconciles` checks `abs(sheet_stated_total − computed_total) < Decimal("0.01")` (hardcoded absolute tolerance, not relative) → `__main__` refuses to write any output file if any head fails to reconcile → `to_project_export()` builds `{"format": "fieldos.project_export.v1", ..., "estimations": [...]}` → `POST /companies/{company_id}/import` (`fieldos/routers/portability.py`, owner/PM only) validates the format tag and bulk-creates `Project → Estimation → CostHead → MeasurementEntry/SteelEntry` rows, with **no re-reconciliation on the API side** — the import endpoint trusts the payload's format tag and the caller's company role, not the importer's own reconciliation guarantee (worth noting: the safety property lives entirely in the offline importer script, not in the API that actually writes to the database).

**A real, notable gap**: the frontend has fully-built `BOQTable.tsx`/`CostHeadForm.tsx`/`MeasurementEntryForm.tsx`/`SteelEntryForm.tsx` components, each with a passing test file, and `frontend/lib/api.ts` exports `createCostHead`/`createMeasurementEntry`/`createSteelEntry` — **none of it is imported or called by any page**. The estimation detail page renders its own inline `<table>` instead. The only wired-up estimation UI is "create a new (empty) estimation." **There is currently no interactive path in the shipped frontend to add a cost head or a measurement/steel entry — that only happens through the importer → import-API path.** Mobile mirrors this exactly: a full write-side `EstimationDao` exists (`create`/`addCostHead`/`addMeasurement`/`addSteel`) and is never called from any screen.

## 7. Importer architecture

**CODE.** Both importers live at the repo root under `importers/` and share one design: parse → build dataclasses → reconcile against the sheet's own stated totals → refuse to write output on any mismatch → emit the same `fieldos.project_export.v1` JSON shape consumed by the portability import endpoint.

- `importers/narapally_boq.py` — targets a **two-flats-side-by-side** sheet layout (two 8/9-column blocks per row, not row-aligned partway down the sheet). `SUPPORTED_SECTIONS = {"BRICK WORK"}` only, even though the same BOQ sheet also has PLASTERING/PAINTING/FLOORING/WOOD WORK/WALL CLADDING sections it recognizes as boundaries but doesn't parse (comment: plastering's "depth" column is actually height and needs remapping, not done).
- `importers/brick_and_concrete_boq.py` — a **general, not-client-specific** parser (deliberately generalized this session, was previously `thumukunta_boq.py`) targeting any workbook with sheets literally named "BRICK WORK" and/or "CONCRETE ESTIMATION" in a **single sequential column** layout. `--project-name` is a required CLI arg, no client default. Explicitly does not cover reinforcement/stirrups (steel_weight layout) or plastering/flooring (area layout).

Both are golden-tested against the real client files (`tests/test_narapally_boq_import.py`, `tests/test_brick_concrete_boq_import.py`), gated by `pytest.mark.skipif(not XLSX_PATH.exists())` — **these tests do not run in CI or on any machine without `resources/` present locally**, since that directory is gitignored. This is a real coverage gap: the only tests that validate the importers against real data are silently skipped everywhere except the original author's machine.

## 8. Protek artifact analysis

**ARTIFACT** (structure only — no real figures reproduced, per the task's absolute rule). Cross-checked against AGENTS.md's coverage table: **no disagreements found** between AGENTS.md's claims and direct inspection of the workbooks.

| Project | Workbooks | Sheets found | Layout convention | Importer coverage |
|---|---|---|---|---|
| Narapally | 1 (masonry) | RATE EST (summary), BOQ (two-flats-side-by-side, 6 sections), SHUTTERING AREA (two-block, upto-plinth vs typical-floor), " COMMON AREA BRICK WORK (SFT)" | two-column-block, feet-based | Only BOQ's BRICK WORK section |
| Thumukunta | 1 (combined) | SLAB/BEAM/COLUMN REINFORCEMENT + STIRRUPS (per-bar steel layout), CONCRETE ESTIMATION + BRICK WORK (single-sequential-column, feet-based), PLASTERING + FLOORING (same single-column shape, area concept), BOQ (abstract) | single sequential column | BRICK WORK + CONCRETE ESTIMATION only |
| Vidyanagar | 2 (concrete + steel, separate files) | CONCRETE: DETAILED (metric, per-element-ID blocks) + ABSTRACT (narrative BOQ, includes a contractor-profit line); STEEL: BEAMS + SLABS (per-bar, metric-ish) + an empty stray `Sheet1` | metric units (unlike the other two projects' feet-based sheets), per-element-ID blocks rather than sequential | **None at all**, either workbook |

Common structural vocabulary across all three: `TOTAL ...` rows (however worded) mark a group's net rollup; `DEDUCTIONS` sections (door/window/ventilator openings) sit between raw entries and a group's closing total; deeper "GRAND TOTAL"/whole-sheet rollups sit above per-group totals. Thumukunta's CONCRETE ESTIMATION sheet has one distinctive pattern not seen elsewhere: a "SOIL FILLING" category expressed as a subtraction of *other* already-computed categories' totals (referenced by name, e.g. "Total excavation"), not re-measured with its own dimensions — the trickiest part of that importer's parsing logic.

The PDFs (`NARAPALLY.pdf` ~122KB, `THUMUKUNTA.pdf` ~140KB, `VIDYANAGAR.pdf` ~86KB) could not be structurally inspected in this pass — no PDF-parsing library is installed in the venv and none was installed per the read-only constraint. Their contents relative to the spreadsheets remain unverified (see §23).

Coverage matrix (see also §6/§7):

| Feature | Narapally importer | Thumukunta/general importer | Vidyanagar | Tested |
|---|---|---|---|---|
| Brick work (volume) | Yes (BOQ sheet, brick section only) | Yes (BRICK WORK sheet) | No importer | Yes, both |
| Concrete/RCC/excavation (volume) | No | Yes (CONCRETE ESTIMATION sheet) | No importer | Yes |
| Plastering/painting/flooring (area) | No (sections recognized but skipped) | No (explicitly out of scope) | No importer | No |
| Wood work/wall cladding | No | N/A | No importer | No |
| Shuttering area | No | N/A | No importer | No |
| Steel reinforcement (steel_weight) | N/A | No (different layout, out of scope) | No importer | No |
| Concrete (metric, per-element-ID) | N/A | N/A | No importer at all | No |
| Steel (beams/slabs) | N/A | N/A | No importer at all | No |

## 9. Frontend map

**CODE.** Next.js 16 app router, static export (`output: "export"`), no dynamic route segments — every project-scoped page uses a `?id=` query string plus a `*Gate`/`Suspense` wrapper (a direct consequence of static export). No global state library; every page is local `useState`/`useEffect` against `frontend/lib/api.ts`.

Fully wired end-to-end (UI → API client → endpoint → model): login/register, dashboard (embedded widget), tasks (embedded), DPR (embedded, incl. voice), materials (incl. photos), workers + attendance, documents (upload/list only — see §13), procurement (the most completely wired feature area — every backend endpoint has a frontend caller across a 6-tab vendor→requisition→RFQ→quote→PO→GRN flow), equipment (mostly — no delete UI), inspections (create/list/photos — no complete/update-item UI), settings (Sarvam key only; desktop app, the mobile app has no key setting), project export/import.

**Confirmed NOT IMPLEMENTED in the frontend despite full backend support**: Issues (zero UI beyond a dashboard count — `listIssues` is defined and never called), Billing/Stripe (zero UI — `listPlans`/`createCheckoutSession`/etc. all defined, never called), Realtime/WebSocket (a complete `useProjectWebSocket` hook exists in `frontend/lib/realtime.ts` and is never imported anywhere), Company member management (no UI, and per §5, no backend route either).

Declared-but-unused frontend dependencies found in `package.json`: `chart.js`, `react-chartjs-2`, `leaflet`, `i18next`/`react-i18next` — no import of any of them found anywhere in `frontend/app`, `frontend/components`, or `frontend/lib`.

## 10. Mobile map

**CODE.** Riverpod state management, Drift/SQLite persistence, plain `Navigator.push` (no named routing). 28 Dart source files under `lib/`.

Feature classification:

| Feature | Status |
|---|---|
| Auth (local) | IMPLEMENTED |
| Projects | IMPLEMENTED |
| Tasks | IMPLEMENTED |
| DPR (incl. voice) | IMPLEMENTED |
| **Estimation/BOQ** | **DATABASE ONLY** — full calc engine + tables exist and are genuinely consumed by the dashboard's budget card, but zero UI anywhere creates an estimation/cost head/entry. Any project created on mobile will show a ₹0 budget unless something outside this recon populates the tables directly. |
| Materials | PARTIALLY IMPLEMENTED — folded into procurement's GRN tab, no standalone catalog |
| Procurement | IMPLEMENTED — full local Suppliers→RFQ→PO→GRN chain |
| **Workers** | **PARTIALLY IMPLEMENTED / effectively DATABASE-ABSENT** — no `Workers` table or DAO exists at all; attendance punch-in takes a free-typed name. Contradicts `docs/MOBILE_GUIDE.md`'s claim of a "worker directory." |
| Attendance | IMPLEMENTED, but geofencing is **manual lat/lng text entry**, not a device GPS/location plugin — no `geolocator`/`location` package in `pubspec.yaml`. The haversine distance math itself is real. |
| Equipment | **NOT IMPLEMENTED** |
| Inspections | **NOT IMPLEMENTED** |
| Documents | **NOT IMPLEMENTED** |
| Photo capture | **DATABASE ONLY** — a `DprPhotos` table and DAO exist, no camera package in `pubspec.yaml`, no UI calls them |
| Voice/audio | IMPLEMENTED (local recording always; Sarvam transcription requires internet + a configured key) |
| Settings | IMPLEMENTED, narrow (Sarvam key only, owner-gated; desktop app only) |

Beyond the requested list: a real multi-level **Approvals** queue exists (including an automatic budget-overrun approval), a **Subcontractor** directory exists, and lightweight offline **agents** (`lib/agents/`) do keyword-based DPR issue/delay detection and cost-head linking that has **no equivalent on the backend at all** (not a duplication — a genuine mobile-only capability).

Android manifest requests only `RECORD_AUDIO` — no camera, no location permission, consistent with the above.

## 11. Voice pipeline

**CODE.** A real, working, parallel implementation on both platforms — not a stub on either side.

**Desktop**: `VoiceDPRRecorder.tsx` (browser `MediaRecorder`) → `POST /projects/{id}/dpr/voice-draft` (multipart) → `fieldos/sarvam.py`: `transcribe_audio()` (Sarvam STT, model `saaras:v3`) → `structure_dpr_from_transcript()` (Sarvam chat completion, model `sarvam-105b`, fixed system prompt extracting `work_summary`/`manpower_count`/`weather` as JSON) → returned as an unsaved `DPRVoiceDraft` → prefills an editable `DPRForm` → explicit "Submit DPR" click → `POST /projects/{id}/dpr` persists a `DPREntry`.

**Mobile**: `record` package (local `.m4a`, 2-minute cap) → `sarvam_service.dart` calls the **same two Sarvam endpoints directly from the device** (no backend involved at all) → result reviewed in an editable confirmation dialog (incl. a checklist of keyword-detected issues from `DprIntakeAgent`) → on confirm, `dprDao.create(...)` writes straight to local Drift storage with `source: 'voice'`.

Both platforms: STT and structuring are two separate sequential calls, not one. Malformed/`None` LLM output (a real observed failure mode — `sarvam-105b` is a reasoning model that can burn its token budget on hidden `reasoning_content` before emitting `content`, empirically fixed by raising `max_tokens` to 2000) degrades gracefully on both platforms to `{work_summary: raw transcript, manpower_count: 0}` rather than failing — the transcript is never silently lost. No internet → both platforms surface an error with no retry/queue (the recorded audio is discarded on desktop; not found to be queued on mobile either) — this is the one deliberately-online feature in an otherwise fully-offline system on both platforms. Empty/no-speech transcript is explicitly rejected (422) before the second LLM call is even made, on desktop; mobile throws a `SarvamException` at the same point.

**Two confirmed platform divergences, both real bugs/gaps rather than intentional differences**:
1. **`source` mislabeling on desktop**: `create_dpr_entry` (`fieldos/routers/dpr.py`) hardcodes `source="manual"` unconditionally — a DPR that started as a voice draft is saved indistinguishable from a hand-typed one. Mobile correctly tags `source: 'voice'`.
2. **`weather` field silently dropped on desktop**: both the backend schema and the voice draft carry `weather`, but `DPRForm`'s prefill type and `createDprEntry`'s payload type both omit it — it never reaches the saved `DPREntry`. Mobile's confirmation dialog carries `weather` through correctly.

Desktop has no equivalent of mobile's `DprIntakeAgent` (keyword issue/delay detection, cost-head linkage) — a capability gap, not a bug.

## 12. Realtime architecture

**CODE.** `fieldos/routers/realtime.py`: `WS /projects/{project_id}/ws`, authenticated via `?token=` query param (resolved directly against the `Session` model, since WebSocket handshakes can't carry headers), authorized via `require_project_access` (closes 4003 on failure). Room model: `project_rooms: dict[project_id -> dict[user_id -> WebSocket]]`, correctly isolated per project.

**The only traffic that actually flows is a raw, unvalidated client-to-client relay**: whatever a connected client sends is rebroadcast verbatim (re-tagged with `sender`/`timestamp`) to every other member of that project's room — the server does not validate `type`/`payload` shape.

**The feature `docs/PROJECT_OVERVIEW.md` and `docs/API_REFERENCE.md` describe — server-generated push notifications on task/DPR/material/worker/equipment/inspection/procurement changes — does not exist in practice.** Seven `broadcast_*_update` helper functions are defined for exactly this (`realtime.py:108-154`) but a repo-wide grep found **zero call sites** anywhere outside their own file — no other router imports or invokes them. This is dead/unwired plumbing, confirmed independently by two separate agents. On the frontend side, `frontend/lib/realtime.ts`'s `useProjectWebSocket()` hook is fully built and equally unused — zero imports anywhere in `frontend/app` or `frontend/components`. **Net effect: connecting to the WebSocket today gets you a working, authorized, project-isolated relay for whatever your own client chooses to send — and nothing else. No real-time notification of actual data changes exists on either end**, despite `docs/PROJECT_OVERVIEW.md` listing "Real-time Collaboration... Live updates for tasks, DPR, materials, workers, equipment, inspections, procurement" as a shipped feature. This is the clearest DOCUMENTATION-overclaims-CODE finding in this recon.

## 13. File/upload architecture

**CODE.** `fieldos/storage.py`: `validate_upload()` enforces a size cap (default 25MB) and MIME+extension allowlist; `save_upload()` writes to `uploads_dir()/subdir/{uuid4}{ext}` with traversal-safe path resolution; `public_url(key)` returns `/uploads/{key}`. Download: `GET /uploads/{key:path}` (`fieldos/routers/uploads.py`) resolves the physical file, matches the trailing filename against `Document.file_path`/`InspectionPhoto.photo_url`/`MaterialPhoto.photo_url` to find the owning project, and enforces `require_project_access` — converting an authenticated-but-unauthorized 403 into a 404 deliberately, so file existence can't be probed by an unauthorized project non-member.

**Two confirmed broken paths**:
1. `documents.py` stores `Document.file_path` as the **absolute filesystem path**, not the relative `/uploads/{key}` form the other two upload types use — the download endpoint only still works because of its filename-matching fallback (explicitly flagged as a workaround in its own docstring).
2. **Photo display in the shipped frontend is broken.** `frontend/app/project/materials/page.tsx` and `.../inspections/page.tsx` render `<img src={photo.photo_url}>` verbatim — a bare `/uploads/...` path with no origin prefix and no auth token. Since the frontend is served from a different origin than the backend (`NEXT_PUBLIC_API_BASE_URL`, typically `localhost:8000` vs. `localhost:3000`/the Tauri webview origin), this resolves against the wrong origin and, even if it coincidentally hit the right one, carries no `?token=` — the download endpoint would 401 it. **Uploaded material/inspection photos cannot currently be viewed in the app as shipped.**
3. Additionally, `frontend/app/project/documents/page.tsx` lists uploaded documents but has **no download or view link at all** — `file_path` is never consumed by any UI.

## 14. Authentication/authorization

**CODE.** Auth: opaque `secrets.token_urlsafe(32)` session tokens (not JWT), stored server-side in `sessions`, 30-day hard TTL, no refresh/rotation. Passwords: SHA-256 pre-hash (works around bcrypt's 72-byte truncation) then bcrypt.

Authorization: three roles (`owner`, `project_manager`, `site_engineer`). `require_project_access` = company owner gets automatic access to every project in their company, else an explicit `ProjectMember` row is required; 403/404 otherwise. `require_company_role` gates company-scoped mutations by an explicit allowed-role set. `require_any_owner_role` is used for the one install-wide (non-project) setting, deliberately excluding a bare "any authenticated user" check.

Verified consistently enforced across every data-touching router (§5) with intentional, not accidental, role-tier variation (e.g., worker-roster edits and vendor creation require owner/PM even though viewing/attendance-marking only requires membership — and this specific worker-edit gate is the subject of an explicit regression test, per §18, closing a previously-real payroll-editing gap). Auth on the WebSocket and file downloads is handled via the same `require_project_access` call, just with a query-param token instead of a header, for the documented reason that neither WebSocket handshakes nor `<img>`/`<a>` tags can set custom headers.

Mobile has a structurally different, non-interoperable role vocabulary (`owner`/`manager`/`member`/`viewer` vs. the backend's `owner`/`project_manager`/`site_engineer`) and a different password-hashing algorithm (pbkdf2 vs. SHA-256+bcrypt) — not a bug since the two systems share no data today, but a real obstacle if user/credential portability between desktop and mobile is ever attempted (§19, §24).

## 15. Offline architecture

**CODE + DOCUMENTATION** (both agree here). Desktop: fully offline except the Sarvam voice call — SQLite is local, no server round-trip for anything else. Mobile: fully offline except the same Sarvam call — confirmed by repo-wide grep, no HTTP client pointed at any FieldOS backend URL anywhere in `fieldos_mobile/lib`. Both platforms explicitly self-document this in code comments (`fieldos/sarvam.py`, `voice_service.dart`, `sarvam_service.dart` all describe themselves as "the one network call"). This claim held up under independent code verification on both platforms and is one of the more reliable things in the documentation set.

## 16. Desktop packaging

**CODE.** Tauri's Rust `setup()` spawns the `FieldOS-backend` sidecar (`app.shell().sidecar(...).spawn()`), no port/args passed — port is hardcoded to 8000 on the Python side (`desktop_app.py`), matched statically by the frontend's baked-in `NEXT_PUBLIC_API_BASE_URL`. On `ExitRequested`, Tauri explicitly `.kill()`s the stored child process, so no orphaned backend process survives app close. The sidecar binary is produced by PyInstaller (`desktop_app.spec`), bundling `desktop_app.py` plus the Alembic `env.py`/`versions/` directory as data files. Migrations run automatically every startup (`alembic.command.upgrade(cfg, "head")`) before the FastAPI app is constructed; the migration script location resolves differently when frozen (`sys._MEIPASS`) vs. running from source. DB lives at `platformdirs.user_data_dir("FieldOS", "Predictera", roaming=False)/fieldos.db`. CORS is locked to exactly 4 literal origins (`tauri://localhost`, `http://tauri.localhost`, `https://tauri.localhost`, `http://localhost:3000`) — the `tauri.localhost` (not `tauri://`) entries exist specifically for Windows/WebView2, per an in-code comment citing Tauri's own docs and matching a recent real fix in this repo's git history (`4f0164c`).

## 17. Mobile packaging

**CODE.** Flutter → Riverpod → Drift → SQLite, fully local. Confirmed zero backend HTTP calls (§10, §15). No sync mechanism to the desktop's data exists — the backend's project export/import format (`fieldos.project_export.v1`) has no consumer anywhere in `fieldos_mobile/lib`, despite a stale table-comment implying schema parity was meant to enable exactly this. Voice/audio requires internet only for the Sarvam transcription step; local recording itself is fully offline.

## 18. Test coverage

**CODE.** Backend: ~34 test files under `tests/fieldos/` plus 2 importer golden-test files at the repo root. Coverage is genuinely strong and includes multiple deliberate regression tests for real bugs previously found (a registration race condition, a `Numeric` precision-overflow 500, a broken equipment-status PATCH schema, a workers payroll-editing authorization gap, an unvalidated inspection-result field, a wrong-table bug in vendor listing). Frontend: 11 Vitest files, all shallow component-rendering/prop-callback tests — no integration test exercises a real page against even a mocked API flow, and `frontend/lib/pdf.ts` is completely untested. Mobile: 10 Flutter test files, notably deep for an offline app (golden BOQ figures matching the Python tests exactly, full procurement-chain tests, geofencing math, Sarvam parsing edge cases).

**Two coverage gaps worth flagging explicitly**:
1. `tests/fieldos/test_billing_webhook_security.py`'s own docstring claims valid-event processing is covered by `test_billing_api.py`. **That claim is false** — `test_billing_api.py` only covers not-configured/403/404 paths. No test anywhere posts a validly-signed Stripe event and asserts a subscription actually gets created/updated. The webhook's security wrapper (signature verification, idempotency) is thoroughly tested; its actual business logic is not tested at all.
2. Both importer golden-test files are gated by `pytest.mark.skipif(not XLSX_PATH.exists())`, and `resources/` is gitignored — **these tests silently do not run in CI or on any machine without the real client files present.**

## 19. Duplicated logic

**CODE.** The one duplication that carries real divergence risk: the BOQ calculation engine is independently reimplemented in Dart (`fieldos_mobile/lib/estimation/estimation_calc.dart`, explicitly self-described as "a faithful Dart port"). Both are golden-tested against the same real spreadsheet figures and currently agree — but they use **different Decimal precision models**: Python's `decimal.Decimal` division is governed by significant-digit precision (default 28 significant digits, `ROUND_HALF_EVEN`); Dart's `Decimal` package division uses `scaleOnInfinitePrecision: 28` — 28 digits *after* the decimal point, a different rounding regime. For typical BOQ magnitudes these coincide; for an unusually large or small raw quantity they would not. **No cross-language parity test exists** — each suite is golden-tested against the spreadsheet independently, never against each other, so a future edit to one side's rounding could pass its own tests while silently diverging from the other. `docs/MOBILE_GUIDE.md` itself names this exact risk as a "Future work" item, which is a reassuring sign the team is already aware of it.

Other duplications found, assessed as lower-risk: authorization role vocabulary (Python's 3 roles vs. Dart's different 4 roles — structural mismatch, no runtime divergence risk since the systems don't share data); password hashing (SHA-256+bcrypt vs. pbkdf2 — different by design, no shared credential store); Sarvam JSON-parsing fallback logic (independently reimplemented on both platforms, currently matching, no shared client library so a future Sarvam API change would need fixing twice). Validation rules (password length, numeric magnitude bounds) were checked and are **not** duplicated — both frontend and mobile simply forward input and rely on the single backend/local-DB source of truth. No BOQ math duplication was found in the TypeScript frontend — it only formats already-computed server-returned values.

## 20. Construction vocabulary

**ARTIFACT + CODE.** Vocabulary FieldOS's estimation engine already understands (calculation types, units): volume (CFT/CUM), area (SFT), steel weight (KG/TONNES), count; measurement dimensions length/width(or breadth)/depth/nos; deduction; conversion factor; contractor profit %; bar diameter (mm), IS-1786 unit-weight formula.

Vocabulary present in the real Protek artifacts but **not yet represented in FieldOS's data model or importers**: category/group names as free text only, never a modeled entity — "FLAT 1"/"FLAT 2"/"COMMON [AREA] FOR BOTH FLATS" (a floor/unit concept), "TYPICAL FLOOR" vs. "UPTO PLINTH" (a building-stage concept), per-element IDs like F1/F2/F3 (footings), C1/C2/C3 (columns), BH/BV (horizontal/vertical beams), S1–S4 (slabs) — a structural-element identification scheme that exists richly in the spreadsheets and has no corresponding entity anywhere in FieldOS (§4); reinforcement-specific vocabulary (bar type, spacing, legs/stirrup count, TOP/BOTTOM/EXTRA reinforcement) which the steel_weight calculation type only partially models (bar dia + length + nos, no spacing/legs concept); plastering/flooring-specific vocabulary (skirting, wall cladding, waterproof flooring, vitrified flooring) with no `calculation_type="area"` importer coverage yet, though the model itself supports `area` as a type.

## 21. Existing capabilities vs missing capabilities

A consolidated view, backend/frontend/mobile side by side (CODE):

| Capability | Backend | Frontend | Mobile |
|---|---|---|---|
| Auth | Session tokens, thorough tests | Wired, shallow tests | Local-only, different role/hash scheme |
| Projects/Tasks | Full CRUD | Wired (Tasks embedded) | Wired |
| DPR incl. voice | Full, both text+voice paths, `source`/`weather` bugs (§11) | Wired | Wired, more capable (issue/delay detection) than desktop |
| Issues | Full CRUD, role-gated resolve | **Not implemented** | Via approvals flow only |
| Estimation/BOQ entry | Full CRUD API | **Read-only, no entry UI** (§6) | **DB-only, no entry UI** (§10) |
| Estimation/BOQ import (from Excel) | Working, reconciliation-gated | Wired (upload button) | N/A |
| Materials | Full, incl. photos | Wired | Partial (folded into GRN) |
| Workers/Attendance | Full, role-gated roster edits | Wired | Attendance yes; worker directory **absent** |
| Documents | Full, versioned | Upload/list only, **no view/download UI** (§13) | **Not implemented** |
| Procurement (Vendor→RFQ→PO→GRN) | Full chain | Most fully-wired area | Full parallel local chain |
| Equipment | Full CRUD + logs | Wired (no delete UI) | **Not implemented** |
| Inspections | Full, incl. photos | Create/list only (no complete/update-item UI) | **Not implemented** |
| Realtime | Auth+authz work; broadcast logic **dead code** (§12) | Hook built, **never used** | N/A |
| Billing/Stripe | Full integration, webhook-security-tested | **Not implemented**, by design per docs | N/A |
| Photo capture (device camera) | N/A (server-side upload only) | Standard file input | **DB-only, no camera code** |
| GPS/location | N/A | N/A | **Manual coordinate entry, not device sensor** |

## 22. Customer evidence

**CUSTOMER**, per the task brief — treated as given fact about what Protek Consult said, not re-derived from anything in this recon:
- Protek Consult currently uses **Onsite** (a third-party product) for construction management.
- They consider Onsite good/adequate for their current needs.
- The pain point they identified is **manual data entry**.
- They specifically asked for **voice-based input**.

Everything else about Onsite — whether it has an API, whether it's technically integrable with FieldOS, whether Protek wants to replace it, whether FieldOS should aim to replace it — is **not customer evidence** and is not asserted anywhere in this recon. See §23.

## 23. Unknowns

- Whether Onsite has any integration surface (API, export format, webhook) — **unknown**, not investigated in this recon (out of scope: this was codebase reconnaissance only).
- The real content/structure of the three Protek PDFs (`NARAPALLY.pdf`, `THUMUKUNTA.pdf`, `VIDYANAGAR.pdf`) — could not be inspected in this pass (no PDF library installed, none installed per the read-only constraint). Whether they duplicate, supplement, or contradict the Excel workbooks is unverified.
- `docs/DATABASE_SCHEMA.md`'s "33 tables" claim vs. this recon's manual count of 34 — not resolved (§4).
- Whether `docs/MOBILE_GUIDE.md`'s "27/27 tests passing" figure for `flutter test` is current — not independently re-run in this recon (test-file-level review found 10 files with what appears to be more than 27 individual test cases combined, but "27" may refer to a different unit of counting, e.g. test groups; not investigated further).
- Whether the desktop app's `Document.file_path`-as-absolute-path issue (§13) causes real failures for end users today, or whether it's latent because the filename-matching fallback happens to always succeed in practice — not tested at runtime in this recon.
- Real-world performance/behavior of the voice pipeline against actual site audio (background noise, regional accent/language coverage of Sarvam's `saaras:v3` model for construction-site Hindi/Telugu/etc.) — not evaluated, this recon only read code.

## 24. Architectural risks

**INFERENCE**, drawn from the CODE findings above, ranked by how directly they could produce a wrong or silently-broken user-facing outcome:

1. **BOQ precision divergence between Python and Dart** (§19) — currently invisible because nothing tests the two engines against each other, only against the same fixed real-world numbers. A change to either side's rounding logic could pass its own test suite while silently producing a different total on the other platform, and neither platform would talk to the other to catch it, since they share no data path.
2. **Realtime/WebSocket feature is entirely non-functional for its documented purpose** (§12) — if anyone builds on the assumption from `docs/PROJECT_OVERVIEW.md`/`docs/API_REFERENCE.md` that live updates on data changes work, they'll be building on dead code.
3. **Estimation/BOQ data entry has no UI on either desktop or mobile** (§6, §10) — the fully-built calc engine and DB schema on both platforms are currently reachable only via the offline importer/import-API path. Any user story that assumes an engineer can add a cost head by hand is currently false.
4. **Broken photo display for materials/inspections in the shipped frontend** (§13) — a straightforward, unambiguous bug (missing origin + missing token on `<img src>`), not an architectural gray area, but worth flagging here because it means a feature that *looks* complete (upload works, list works) silently fails at the last step.
5. **Billing webhook business logic is untested** (§18) — masked by thorough security-wrapper tests that could give false confidence the feature works end to end.
6. **Precision-bound inconsistency across schema families** (§6) — the Decimal-overflow guard pattern exists for estimation schemas but not procurement/material/equipment/worker schemas, which share the same underlying SQLite-doesn't-enforce-NUMERIC risk.
7. **Mobile/desktop are two silently-separate data silos with incompatible auth systems** (§1, §14, §17) — already self-documented as a known gap in `docs/MOBILE_GUIDE.md`, listed here because it underlies several of the above (any future sync effort inherits the precision-divergence and role-vocabulary-mismatch risks simultaneously).

## 25. Recommended next investigation

Per the task's explicit instruction not to propose a roadmap, this is the single most useful next question, not a plan:

**Which of these already-built-but-disconnected pieces is actually the smallest step toward "voice-based input, less manual data entry" — the one thing the customer explicitly asked for?**

The voice pipeline itself (§11) is real, working, and exists on both platforms today. The gap between what Protek asked for and what would ship isn't "build voice input" — it's two small, already-scoped bugs (`source` mislabeling, dropped `weather` field, both in `fieldos/routers/dpr.py`/`frontend/components/DPRForm.tsx`) plus a decision about which platform (desktop web, used at a site office, vs. mobile, used in-hand on site) is the one Protek would actually use for this. That decision needs customer input, not more code reading — the next investigation is a conversation with Protek about *where* they'd actually use voice-to-DPR day to day, not a further code audit.
