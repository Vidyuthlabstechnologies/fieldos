# Agent Handoff — FieldOS

Read this first if you're a fresh AI agent picking up this project. It's the
one place that stays current with what's actually true right now, as
opposed to `docs/*.md`, some of which has drifted (flagged below where
known). Verify anything load-bearing against the code rather than trusting
any doc, including this one, at face value — that discipline is what
produced every real bug caught so far.

**Last verified against:** commit `9c04d8e`, 2026-08-23.

## What this actually is

FieldOS is a construction-site management platform for **Predictera Pvt
Ltd**, built against **Protek Consult's** real project data. It's a real
product being built to eventually sell to construction companies in India —
not a demo or portfolio project. Treat correctness and honesty about
completion state accordingly; there's a standing user preference (see
`.claude`/memory if your harness has it) to never round up or fabricate
progress.

**The stated vision, in the user's own words** (this is the actual product
target, not the current desktop-only architecture docs/PROJECT_OVERVIEW.md
describes): a native Android app that covers every construction-site
workflow, with every employee's phone staying in sync with the rest of the
company, **at zero ongoing infrastructure cost** — no paid server, no cloud
instance the user has to pay for.

## Absolute rules — do not violate these

- **`resources/`** (Protek Consult's real BOQ/estimation spreadsheets and
  PDFs) must never be committed, logged, or have real figures quoted in any
  file that gets committed. It's gitignored; keep it that way.
- **`.env`** (real Sarvam API key) must never be committed or echoed.
- **Never create third-party accounts on the user's behalf** — not a
  Supabase account, not a Play Console account, not anything. If the next
  step needs one, say so explicitly and wait for the user to create it and
  hand you credentials/URLs.
- **Report honest completion percentage, broken down by pillar, never
  rounded up** — this was an explicit standing user instruction. See the
  published "FieldOS Completion Ledger" artifact if you have access to it
  (link may not survive across sessions/agents — regenerate from the state
  below if not).

## Repo map

```
fieldos/              FastAPI backend (desktop-only, SQLite) — see docs/PROJECT_OVERVIEW.md
frontend/              Next.js frontend (desktop-only, wrapped by Tauri)
src-tauri/              Desktop shell (Rust/Tauri) → ships as a Windows installer
fieldos_mobile/         Native Flutter mobile app — THE ACTIVE, CANONICAL MOBILE PATH
supabase/                Postgres schema + RLS policies for cross-device sync (local Docker
                        dev stack today; no production project exists yet)
docs/                   Documentation. Some of it (MOBILE_GUIDE.md's sync section
                        especially) was stale until this handoff's own edits — see below.
resources/               GITIGNORED. Real client data. Never touch its contents in anything
                        that gets committed.
```

**`fieldos_mobile/` is where essentially all current work happens.** The
desktop app (`fieldos/` + `frontend/` + `src-tauri/`) is feature-complete-ish
and not where the active vision work is. Don't confuse the two — a lot of
`docs/*.md` was written when desktop was the only app and hasn't fully
caught up to mobile being primary.

## fieldos_mobile/ architecture

- **Flutter, Android-only by explicit user decision** ("focus only on
  android" — iOS is out of scope, not an oversight).
- State: Riverpod. Local persistence: `drift` over SQLite
  (`lib/data/app_database.dart`, generated code in
  `app_database.g.dart` — regenerate after touching `lib/data/tables.dart`
  via `dart run build_runner build --delete-conflicting-outputs`, don't
  hand-edit the generated file).
- Local auth is pbkdf2-based, fully offline, no server round-trip
  (`lib/auth/`).
- The BOQ/estimation calc engine exists **twice, deliberately**: a pure-Dart
  port (`lib/estimation/estimation_calc.dart`) for every UI screen, and the
  desktop's exact `fieldos/estimation_calc.py` embedded on-device via
  **Chaquopy** for the one calculation where floating-point drift would
  matter. See `docs/CHAQUOPY_FEASIBILITY.md` for why the *narrow* Chaquopy
  scope is a confirmed GO but a full FastAPI-backend-on-device is a
  confirmed NO-GO (no Chaquopy wheel for `pydantic-core`/`bcrypt`, no iOS
  path, real APK/latency cost) — don't re-litigate that without new
  evidence, it was tested, not guessed.
- Voice-to-DPR via Sarvam is the only feature that needs the network on its
  own, independent of cloud sync.

## Cloud sync — the actual current state

**This is the part `docs/MOBILE_GUIDE.md` gets wrong as of the version
before this handoff was written** — it claims "no backend sync exists,
not yet scoped." That's false. A real, tested sync layer exists:

- **Backend:** Supabase (Postgres + Auth + Realtime + RLS), local Docker dev
  stack via `supabase start` / `supabase db reset`. **No production Supabase
  project exists yet** — `lib/sync/sync_config.dart`'s `SyncConfig.production`
  is empty. Creating one is the user's own action (see Absolute Rules).
- **Schema + RLS:** `supabase/migrations/20260823000000_initial_schema.sql` —
  30 tables mirroring `fieldos/models.py`'s numeric precision exactly, RLS
  enabled on every table with helper functions (`is_company_member`,
  `has_project_access`, etc.).
- **Sync mechanism:** a hand-rolled transactional outbox
  (`lib/sync/sync_engine.dart`, `lib/sync/sync_mappers.dart`,
  `lib/data/app_database.dart`'s DAOs). Every local write that matters
  enqueues a `SyncOutbox` row **in the same Drift transaction** as the
  business write, so the two can never silently diverge. `SyncEngine`
  drains the outbox (push), fetches everything RLS allows (pull), and
  subscribes to Realtime `postgres_changes` for live updates.
- **Auth bridge:** `lib/sync/cloud_sync_service.dart` bridges local pbkdf2
  auth to a real Supabase Auth session (sign-in-first, fall back to sign-up).
  Reachable from the app at Settings → Cloud sync (`enable sync` / `sync now`).
- **Entity coverage — 18 of ~20 syncable tables, all verified against real
  Postgres/Storage:** Project, Task, DPR entry, Issue, Worker, Equipment,
  Inspection, Subcontractor, WorkOrder, Approval, Supplier (→ `vendors`;
  local table extended for full column parity), the estimation tree
  (Estimation/CostHead/MeasurementEntry/SteelEntry), the procurement core
  (PurchaseRequest → `purchase_requisitions`, PurchaseOrder →
  `purchase_orders` — mobile schemas were aligned to the remote CHECK
  vocabularies first; see `lib/data/tables.dart`), and Documents — the only
  entity that moves its FILE through Supabase Storage (private bucket,
  path `{projectId}/{documentId}`, upload-before-insert so a visible row
  always has a downloadable object; byte-for-byte round-trip tested).
- **Deliberately NOT wired** (see `lib/sync/sync_mappers.dart`'s docstring
  for the full reasoning per table): MaterialReceipts (shape doesn't map to
  desktop's `material_entries`), Documents (would sync a metadata row
  pointing at a file that only exists on one phone — needs Supabase Storage
  upload first, not just a column mapping), LabourAttendance (punch-events
  vs. a daily summary — needs real aggregation, not a mapping).
- **Realtime:** engine-level subscriptions exist for project tasks, company
  projects, and company vendors; live-update UI consumers are the
  `ProjectDetailScreen` task list and `ProcurementView`'s Suppliers tab.
  The publication carries `tasks, projects, vendors,
  purchase_requisitions, purchase_orders`. Other synced tables' `on*Changed`
  hooks are ready for screens to consume.
- **Sync visibility exists now:** Settings → Cloud sync shows the pending
  outbox count and last-synced timestamp (persisted in AppSettings as
  `last_sync_at`, written after each successful `syncNow()`).
- **No conflict resolution beyond "pull is server-wins."** Fine today
  because each record has one real-world owner; will need real design work
  the day two people edit the same record offline.

### The exact recipe to sync a new entity

This is now a proven, repeatable pattern — follow it exactly rather than
inventing a new approach:

1. Confirm the Drift table's columns correspond 1:1 to the Postgres table
   (check `supabase/migrations/20260823000000_initial_schema.sql` by hand).
   If they don't correspond cleanly, don't force it — document why not,
   the way `sync_mappers.dart`'s docstring does for the three deliberate
   omissions above.
2. Add `<entity>ToSupabaseJson()` and `<entity>FromSupabaseJson()` functions
   to `lib/sync/sync_mappers.dart`.
3. In the entity's DAO (`lib/data/app_database.dart`), wrap every
   create/update method that should sync in `transaction()`, and after the
   local write, call
   `db.syncOutboxDao.enqueue(targetTable:, recordId:, operation:, payloadJson: jsonEncode(...ToSupabaseJson(row)))`
   in the **same transaction**. Add an `upsertFromRemote(...)` method using
   `insertOnConflictUpdate`.
4. Add the pull loop for the new table to `SyncEngine.pullAll()`.
5. **Check the RLS policies for the table cover `select`, `insert`, AND
   `update`** (see Known Gotchas below — this exact gap caused a real,
   silent bug once already). Add whichever's missing.
6. Write a real-infra test following `test/sync_engine_equipment_inspections_test.dart`'s
   or `test/sync_engine_subcontractors_test.dart`'s pattern: real
   `service_role` admin client seeds a company/project, a real user client
   signs in, push then assert the row landed in real Postgres with the
   right values (not just "push didn't throw" — assert the actual synced
   value), then a second test asserts `pullAll()` merges a remotely-created
   row into local Drift.
7. `flutter analyze`, run the new test against the real local Supabase
   stack (`supabase start` first if it's not already running — check with
   `docker ps`), run the full suite, commit.

## Known gotchas — don't rediscover these

- **`SyncEngine.pushPending`/`pullAll` are serialized by `_synchronized` —
  keep it that way.** Without the lock, an overlapping periodic tick +
  manual "Sync now" drained the same outbox rows twice; the loser hit
  duplicate-id violations and marked already-succeeded entries as FAILED
  (silent retry-forever poisoning). Proven by
  `test/sync_engine_concurrency_test.dart`, fixed with a chained-Future
  mutex.
- **The two estimation engines agree to ~25 significant digits, then
  diverge — by design.** Python's `Decimal` applies a 28-significant-digit
  context rounding per operation; Dart's decimal package is exact. The
  differential suite (`test/estimation_differential_test.dart`, fixtures
  from `scripts/generate_estimation_fixtures.py`) enforces value equality
  for single ops and a 1e-9 tolerance for rollups. Don't "fix" either
  engine toward the other without revisiting that contract; desktop
  remains canonical at extreme precision (the Chaquopy path exists for it).
- **Gitleaks runs against git history** (`gitleaks git .`); the only
  allowlisted token is Supabase's public local-dev default in
  `lib/sync/sync_config.dart` (see `.gitleaks.toml`). Any other jwt/key
  finding is real — rotate and remove.
- **frontend npm audit**: the serialize-javascript RCE chain was killed via
  an `overrides` entry in frontend/package.json. The remaining 3 moderates
  all sit inside the deprecated Capacitor CLI (`@capacitor/cli`→xcode→uuid)
  — accepted risk until that wrapper is deleted, since forcing uuid ≥11
  risks breaking the legacy build for zero runtime exposure.

Real bugs found and fixed this build, in case future work touches the same
surface again:

- **RLS policies must cover select, insert, AND update independently.**
  `work_orders` had select+insert but no update policy — an outbox push
  reported success (no exception, Postgrest just matched zero rows under
  RLS and called that "success") while the actual value never changed in
  Postgres. Silent, undetectable without a test that asserts the real
  synced value. Audit all three per table, not just per feature.
- **`supabase_realtime` publication starts empty on a fresh local stack.**
  A table has to be explicitly added
  (`alter publication supabase_realtime add table X;`) or
  `postgres_changes` subscriptions never fire, regardless of RLS or client
  correctness. Currently only `tasks, projects` are in it — add more as
  `SyncEngine` grows more `subscribeTo*` methods.
- **`service_role` needs explicit table GRANTs too** — RLS bypass via
  Supabase's `bypassrls` and Postgres `GRANT`/`REVOKE` are separate
  mechanisms; a new table's default privileges don't extend to
  `service_role` automatically.
- **`SET LOCAL` in a raw `psql` script needs an explicit `BEGIN`/`COMMIT`**
  — psql runs each statement in its own implicit transaction by default,
  so `set local request.jwt.claims = ...` for RLS testing is a silent no-op
  outside an explicit transaction block.
- **`SupabaseClient`'s default `authFlowType` is `pkce`**, which asserts on
  missing async storage the first time `signUp()` is called. Use
  `SyncConfig.createClient()` (implicit flow) for any direct
  email+password auth — see `sync_config.dart`'s docstring for why implicit
  is correct here, not a workaround.
- **Flutter `testWidgets` + real network calls is a real minefield**, hit
  repeatedly building `test/settings_screen_cloud_sync_test.dart` (which
  was ultimately *not* committed — see that commit's message for the full
  postmortem): `TestWidgetsFlutterBinding` runs inside a FakeAsync zone
  where real Timers never fire unless wrapped in `tester.runAsync()`
  (including a reachability check, not just the interesting call); it also
  installs a global `HttpOverrides` that fakes all HTTP as 400, which has
  to be cleared *before* anything constructs an `HttpClient` (i.e. before
  the first `pumpWidget`, not around the tap that uses it); and a
  successful sign-up leaves GoTrue's auto-refresh `Timer` running in a way
  that neither `dispose()` nor `signOut()` reliably cancels before
  `TestWidgetsFlutterBinding`'s post-test "no pending timer" assertion
  fires. If you need a real widget-level regression test for a
  network-touching screen, consider `integration_test/`
  (`IntegrationTestWidgetsFlutterBinding`, no FakeAsync) instead of
  fighting this again.
- **Any new Drift column/table needs a migration step, not just a table
  edit.** `schemaVersion` is 4 and `AppDatabase.migration`'s `onUpgrade`
  handles v3→v4 (suppliers parity + procurement alignment columns,
  including a `TableMigration` backfill for the now-NOT-NULL unit).
  Before that existed, an additive change shipped with no upgrade path —
  the default drift migrator only creates missing tables, never alters
  existing ones. Bump the version and add a step for every schema change.
- **A `supabase db reset` restarts the realtime container, and
  `postgres_changes` tests can fail once immediately afterwards** (channel
  join/event delivery not warm yet). The realtime test passed on immediate
  re-run with no code change. If you reset the DB and then see exactly one
  realtime-test failure, re-run before diagnosing.
- **Windows + orphaned `dart.exe`/`flutter_tester.exe` processes.**
  Stopping a backgrounded `flutter test` command (timeout, manual stop)
  doesn't always kill its child processes. Check
  `Get-Process | Where-Object { $_.ProcessName -match 'dart|flutter' }`
  and force-kill stragglers before starting a new test run, or you'll get
  confusing hangs with near-zero CPU usage.
- **The Drift "you've created the database class AppDatabase multiple
  times" warning in test output is benign** — it fires whenever a test
  file opens two `AppDatabase.memory()` instances (e.g. simulating two
  devices), which is intentional in the multi-client sync tests. Don't
  chase it.

## How to verify anything

Real infrastructure only — this codebase has a hard "no mocks" discipline
for sync-layer tests, and it's caught bugs a mocked suite would have
missed. Don't introduce mocks here without a very good reason.

```bash
# Docker + local Supabase stack (from repo root)
docker ps                      # confirm Docker's running
supabase start                 # first time / if stopped
supabase db reset              # after any migration file change

cd fieldos_mobile
flutter analyze                # should be clean except one pre-existing,
                                # unrelated deprecation warning in labour_screen.dart
flutter test                   # full suite — 303 tests as of this commit
flutter test test/estimation_differential_test.dart   # Dart engine vs Python engine, 241 cases
flutter test test/sync_security_perf_test.dart        # RLS denials via the app's own client + latency smoke
flutter test test/some_file.dart   # a single file
```

`test/*_test.dart` files self-skip (return early) if the local Supabase
stack isn't reachable — check `_localStackReachable()` in any of them for
the pattern. This means a green run with the stack down isn't proof of
anything; confirm `docker ps` shows the `supabase_*` containers healthy
before trusting a passing run.

## Where things actually stand — prioritized gaps

In rough priority order (highest-value next work first). Full detail with
"how to do it" per item is in the published "FieldOS Completion Ledger"
artifact if it's reachable from your session; if not, this list is the
same content in prose:

1. **More entities into cloud sync** — 18 of ~20 wired (see entity
   coverage). Remaining, each with its blocker: `grns`/MaterialReceipts and
   `attendance`/LabourAttendance (shape mismatches — see
   `sync_mappers.dart`'s docstring), `rfqs`/`quotes` (no mobile tables —
   building them is a feature, not a mapping).
2. **~~Sync visibility in the UI~~ DONE** — the "Team & sync" screen
   (`lib/features/team/team_sync_screen.dart`, open to every role) shows
   last sync, waiting and failed counts, Sync now and Retry failed.
3. **Realtime UI hookups beyond the task list** — Suppliers tab is live
   now; remaining synced tables still refresh via periodic/manual sync.
4. **Photo evidence capture** — DPR entries have camera-first capture
   (`image_picker`) via `lib/features/shared/photo_capture.dart`;
   inspections/materials still use generic pickers. Needs on-device
   verification of the camera intent.
5. **~~Feature-breadth gaps~~ mostly DONE (Nov 2026)** — per-project
   team chat (`project_messages`, Realtime), a site map (flutter_map + OSM),
   GPS punch-in, DPR PDF share, and local alerts for colleagues' issues,
   approvals and messages raised on sync. Not done: true push while the app
   is closed (needs FCM + a server), Indic-script text inside PDFs.
6. **A real production Supabase project** — blocked on the user's own
   account; the exact cutover steps are written up in
   `docs/SUPABASE_PRODUCTION_RUNBOOK.md`, so it's configuration once done.
7. **Play Store presence** — signed release builds work (upload key in
   gitignored `android/app/key.properties`; falls back to debug signing
   without it). CI runs `flutter analyze`, the full real-infra test suite
   and a debug APK build on every push (`.github/workflows/mobile.yml`).
   Everything left is on the owner's accounts and is listed step by step
   in `docs/PLAY_STORE_LAUNCH.md` (listing copy, privacy policy, data
   safety answers, two-phone smoke test). iOS stays out of scope.

## Stale docs to be aware of

- `docs/MOBILE_GUIDE.md`'s "Known architectural gap: no backend sync"
  section was corrected alongside this handoff being written — if you're
  reading a version of that file from before this commit, the sync layer
  described above already existed and that section was wrong.
- `docs/README.md`'s architecture diagram still shows mobile as "entirely
  standalone... NO connection to the FastAPI backend" — that line is about
  the desktop FastAPI backend specifically (still true, mobile never talks
  to `fieldos/`) but reads as implying no sync exists at all, which is
  no longer accurate now that Supabase-based cross-device sync exists.
  Worth a light edit if you're touching that file anyway.
