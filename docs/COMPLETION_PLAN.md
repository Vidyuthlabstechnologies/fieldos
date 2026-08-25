# FieldOS Completion Plan

**For:** the next Claude agent picking this project up next.
**Read `docs/AGENT_HANDOFF.md` first** — it has the absolute rules, exact
architecture, the entity-sync recipe, and every gotcha already found.
This document doesn't repeat that; it's the forward-looking plan on top of
it — what's left, in what order, with a real effort estimate and a
concrete "done" definition for each item.

**Verified against, directly, right now — not from commit messages or a
prior doc's claims:** commit `b97bd2c`, 2026-08-24.

- `flutter analyze`: clean (1 pre-existing, unrelated deprecation warning
  in `labour_screen.dart`).
- `flutter test` (full suite, real local Supabase stack, all 9 containers
  healthy including Storage): **302/303 passing.** The 1 failure
  (`sync_engine_realtime_test.dart`) reproduced the exact warm-up flake
  `AGENT_HANDOFF.md` already documents — the Realtime container needs a
  moment right after Docker/the stack restarts. Retried in isolation
  immediately after: passed clean. Treat 302/303 as the honest number for
  that run, not 303/303 — the flake is real and documented, not swept
  under the rug, but it isn't a code defect either.
- Keystore (`android/app/fieldos-upload.keystore`) and
  `key.properties` exist on disk, confirmed gitignored and never
  committed to any branch's history (`git log --all` on both paths:
  empty).
- CI (`.github/workflows/mobile.yml`) genuinely starts a real Supabase
  stack via `supabase start` before running `flutter analyze` + the full
  test suite — not a mocked or skipped pipeline.
- `docs/SUPABASE_PRODUCTION_RUNBOOK.md` exists and is a real, usable
  cutover guide, not a stub.

## Honest completion, by pillar

Recomputed from scratch against the verified state above, not carried
forward from an earlier session's number.

| Pillar | % | What moved since the last checkpoint |
|---|---|---|
| 01 · Offline-first core | **88%** | Camera-first photo capture landed for DPR (`lib/features/shared/photo_capture.dart`, via `image_picker`) — inspections and materials still use a generic file picker, not camera-first. |
| 02 · Cross-device cloud sync | **85%** | Entity coverage jumped 10→18 of ~20 tables. Documents now sync their actual file bytes through Supabase Storage, not just a metadata row. Concurrency-safety (a real double-push race, found and fixed with a mutex) and cross-tenant security are now both under real-infra test, not assumed. Sync status (pending count, last-synced time) is visible in Settings. Remaining: 2 genuine gaps below, plus the production cutover itself. |
| 03 · Feature breadth vs. Kraaft/Onsite | **45%** | Photo capture improved for DPR only. Chat, maps, and push notifications are still entirely unbuilt — the biggest remaining gap against the competitor research. |
| 04 · Production readiness | **68%** | CI, signed release builds, and a production runbook all now exist and are real, not placeholders. Remaining: the production Supabase project itself (user's account) and the Play Store listing (user's account). |

**Weighted overall: ~66%.** Cloud sync and production readiness — the two
pillars the user cares most about (sync at zero cost, actually shippable)
— both made large, genuinely verified jumps. Feature breadth is now the
laggard, not sync.

## What's fully done (don't redo this)

- **Offline-first CRUD** for every module: auth, companies, projects,
  tasks, DPR, issues, workers/attendance, equipment, inspections,
  subcontractors, work orders, approvals, documents, procurement,
  estimation/BOQ. Real screens, real DAOs, real tests.
- **The BOQ calc engine, cross-checked two ways**: a pure-Dart port for
  every screen, Chaquopy-embedded Python for the one calculation where
  precision matters, and now a 241-case differential test
  (`test/estimation_differential_test.dart`) proving they agree to the
  documented tolerance. This closes what was previously just an assertion
  — it's now a regression-tested contract.
- **Cloud sync core mechanism**: transactional outbox, push/pull, RLS on
  every table, Realtime subscriptions, auth bridge, background periodic
  trigger, manual "Sync now", sync-status UI, and — as of this build —
  proven safe under real concurrency (`sync_engine_concurrency_test.dart`)
  and real cross-tenant attack attempts
  (`sync_security_perf_test.dart`).
- **18 of ~20 syncable entities**, each independently verified against
  real Postgres: Project, Task, DPR, Issue, Worker, Equipment, Inspection,
  Subcontractor, WorkOrder, Approval, Supplier/Vendor, the full estimation
  tree (Estimation/CostHead/MeasurementEntry/SteelEntry), the procurement
  core (PurchaseRequest, PurchaseOrder), and Documents (file bytes via
  Supabase Storage, not just metadata).
- **CI**: `.github/workflows/mobile.yml` runs the real thing on every
  push — starts Supabase, runs `flutter analyze` + the full test suite.
  No mocking, no skipping.
- **Release signing**: a real upload keystore exists, gitignored, with
  Gradle wired to use it when present and fall back to debug signing
  otherwise. `flutter build apk --release` / `appbundle --release` both
  produce a properly-signed artifact today.
- **The production cutover path is fully documented and is genuinely just
  configuration** (`docs/SUPABASE_PRODUCTION_RUNBOOK.md`) — create the
  Supabase project, `supabase db push`, fill two config values, done. No
  new engineering required for that step.

## What's partial — exact remaining steps

### 1. Two real entity-sync gaps (not just "more of the same")

- **`grns` / MaterialReceipts**: the mobile `MaterialReceipts` table is
  shaped around a simple consumption log; the desktop/Postgres side is
  shaped around the procurement chain (po_id/supplier_id/cost_head_id).
  **This needs a real reconciliation decision, not a mechanical mapping**
  — either redesign the mobile table to match the procurement shape (a
  breaking local-schema change, needs a Drift migration + backfill), or
  accept these stay desktop-only. Recommend: decide this explicitly with
  the user before touching it; don't guess.
- **`attendance` / LabourAttendance**: mobile stores punch-events, Postgres
  expects a daily summary row. Needs a real aggregation step (punches →
  one row per worker per day) before it can sync at all — this is design
  work, not a mapping. Effort: medium (a new aggregation function + its
  own test, then the standard sync recipe on top).
- **`rfqs` / `quotes`**: **no mobile tables exist for these at all.**
  This isn't a sync gap, it's a missing feature — building RFQ/Quote
  screens and Drift tables is prerequisite before there's anything to
  sync. Effort: medium-large (new tables, new screens, then sync).

### 2. Realtime UI hookups beyond Tasks and Vendors

The engine-level mechanism (`on*Changed` callbacks in `SyncEngine`)
already exists for every synced table. Only `ProjectDetailScreen`'s task
list and `ProcurementView`'s Suppliers tab actually consume it — everything
else refreshes only via periodic/manual sync. **This is pure glue work,
low risk, high value**: for each remaining screen, subscribe on
`initState`/screen-open, call `ref.invalidate(theRelevantProvider)` in the
callback, unsubscribe on dispose. Follow `project_detail_screen.dart`'s
existing pattern exactly. Do DPR and Issues first — they're the
highest-frequency data on an active site.

### 3. Photo capture for inspections and materials

DPR has camera-first capture (`lib/features/shared/photo_capture.dart`).
Inspections and materials still use a generic file picker. Wire the same
shared widget into both screens — this is now a proven pattern, not new
design work. Effort: small, an hour or two per screen.

### 4. Production Supabase cutover

Fully documented, zero new engineering — see
`docs/SUPABASE_PRODUCTION_RUNBOOK.md`. Blocked entirely on the user
creating the Supabase account (absolute rule: you cannot do this for
them). Once they hand you a project URL + anon key: fill
`SyncConfig.production` in `lib/sync/sync_config.dart`, `supabase db
push`, done. Budget a real two-device smoke test afterward — everything
so far has been verified against one local Docker stack, never against
two actual physical Android devices talking through a real production
Supabase project.

## What's not started — real scope, not hand-waved

- **Conflict resolution.** Pull is unconditionally server-wins today. Fine
  while each record has one real-world owner (today's usage pattern);
  breaks the day two people edit the same task/DPR/estimate offline at the
  same time. This needs actual design (field-level merge? last-write-wins
  with a visible conflict banner? something else?) before it's safe to
  promise "real-time collaboration" as a headline feature. Don't build this
  speculatively — wait until it's a real, reported problem, per the
  established "no guessing" discipline, but flag it to the user as a known
  limitation before they lean on concurrent multi-user editing.
- **Chat / team communication.** Kraaft's entire product positioning is
  "augmented WhatsApp for construction" — FieldOS has nothing here. The
  cloud-sync backbone (Postgres + Realtime, already proven) is the right
  foundation: a per-project `messages` table + a Realtime subscription is
  architecturally a small extension of what already exists, not a new
  system. The UI (a real chat screen, read receipts, etc.) is the actual
  effort. Scope: medium-large, genuinely new feature.
- **Map view / location awareness.** A geofence radius check exists for
  attendance punch-in; there's no map UI at all. `flutter_map` with OSM
  tiles fits the zero-cost constraint (no Google Maps API billing). Scope:
  medium — start with one screen (project location + geofence radius,
  read-only), don't attempt live crew tracking until that's requested.
- **Push notifications.** No FCM or equivalent. Needed for anything
  time-sensitive (an approval waiting on someone, a new issue raised) to
  actually reach a phone that isn't open. Scope: medium — FCM's free tier
  covers this at zero cost, consistent with the project's cost constraint.
- **Play Store listing.** Signed builds exist; nothing has been uploaded.
  Needs: a Play Console developer account (user's, one-time $25), store
  listing copy + screenshots, a data-safety declaration (the app now
  touches the network for sync, so this has to be accurate), and a first
  closed-testing track upload before production. Scope: small-medium,
  mostly non-engineering work plus one real upload.
- **A true widget-level regression test for a network-touching screen.**
  `test/settings_screen_cloud_sync_test.dart` was built and then
  deliberately not committed after repeatedly hitting Flutter's
  `testWidgets`/FakeAsync limitations (fully documented in
  `AGENT_HANDOFF.md`'s gotchas). If this is worth having, it needs
  `integration_test/` (`IntegrationTestWidgetsFlutterBinding`, no
  FakeAsync) rather than another attempt at the same approach. Scope:
  small if using `integration_test/`, but needs a real Android
  emulator/device to run — not just `flutter test`.

## Suggested execution order

Roughly highest-value-per-hour first, not strictly dependency order (most
of these are independent and can be reordered freely):

1. **Realtime UI hookups for DPR and Issues** (small, immediate visible
   value — "why isn't this updating live" is the kind of thing a real
   user notices fast).
2. **Photo capture for inspections and materials** (small, mechanical,
   reuses an already-proven pattern).
3. **Decide and resolve the two real sync gaps** (MaterialReceipts shape,
   LabourAttendance aggregation) — needs a real decision conversation with
   the user first for MaterialReceipts specifically; don't unilaterally
   redesign a schema.
4. **Production Supabase cutover**, the moment the user hands over
   credentials — this unblocks real multi-device validation, which
   everything else has been a proxy for until now.
5. **RFQ/Quote mobile feature** — genuinely new work, size it properly
   rather than squeezing it in alongside smaller items.
6. **Chat, maps, push notifications** — the three real feature-breadth
   gaps. Each is its own scoped project; don't attempt all three at once.
7. **Play Store listing** — mostly parallel-able with the above once a
   release build the user is happy with exists.
8. **Conflict resolution design** — only once it's an actual reported
   problem, not preemptively.

## What "done" looks like for the stated vision

Not "every box checked" — the stated vision was specific: *every
construction-site workflow, every employee's phone in sync, zero ongoing
infrastructure cost, safe.* A reasonable "v1 shippable" bar, distinct from
"every gap above closed":

- [ ] Production Supabase project exists and the app points at it (user
      action + one config edit)
- [ ] Two real physical devices, same company account, verified syncing
      live (not just against the local Docker stack)
- [ ] Every entity that has a mobile screen at all either syncs or has a
      documented, deliberate reason it doesn't (this is nearly true today
      — MaterialReceipts and LabourAttendance are the two open questions)
- [ ] Realtime hookups on at least the highest-traffic screens (DPR,
      Issues, Tasks — Tasks already done)
- [ ] A signed release build the user has actually installed and used on
      a real site, even before any Play Store listing exists (sideloaded
      APK is a legitimate first distribution channel for a handful of
      known users)
- [ ] Zero recurring infrastructure cost confirmed in practice, not just
      by design — Supabase's free tier has real limits (500MB DB, pauses
      after a week idle on some tiers); worth a deliberate check-in once
      real usage data exists, not just a "should be fine" assumption

Everything else in this document — chat, maps, push, Play Store — is real,
valuable, and worth doing, but is expansion beyond that bar, not blocking
it.
