# Mobile Development Guide (Flutter)

## Overview

FieldOS's mobile app is a native Flutter app at `fieldos_mobile/` — not a
wrapper around the web frontend. It's a fully offline-first, standalone app
with its own local auth, its own local database, and its own port of the
BOQ estimation/reconciliation engine, built specifically for site-level use
where connectivity can't be assumed.

**This supersedes the earlier Capacitor-based approach** (`frontend/android/`,
`frontend/capacitor.config.ts`, `frontend/MOBILE.md`), which wrapped the
Next.js web frontend in a WebView. That code is still present on disk for
reference but is not the maintained mobile path going forward — see
`frontend/MOBILE.md` for its deprecation note.

## Architecture

```
Flutter app (fieldos_mobile/)
  ├─ lib/auth/          local username/password auth, session tokens (own DB, no server call)
  ├─ lib/data/           drift (SQLite) local database — 20 tables: BOQ/DPR plus a
  │                      full site-ops backbone (suppliers, purchase requests/orders,
  │                      material receipts, GPS-geofenced labour attendance,
  │                      subcontractors, work orders, multi-level approvals)
  ├─ lib/estimation/     a faithful Dart port of fieldos/estimation_calc.py's
  │                      calculation rules and BOQ reconciliation logic
  ├─ lib/agents/         voice-DPR intake and a cost-control agent
  ├─ lib/services/       Sarvam STT/LLM integration (the only outbound network call
  │                      this app makes today)
  └─ lib/features/       screens: dashboard, procurement, labour, subcontractors,
                         approvals, company setup, settings
```

State management is Riverpod; local persistence is `drift` over SQLite via
`drift_flutter`. `lib/data/app_database.g.dart` is drift's generated code —
regenerate it after touching `lib/data/tables.dart` (see below), don't hand-edit it.

## ⚠️ Known architectural gap: no backend sync

As of this writing, `fieldos_mobile` talks to **no FastAPI endpoint at all**.
Auth, projects, DPR, procurement, and approvals are entirely local to the
device — the only outbound network call anywhere in `lib/` is to the Sarvam
API for voice transcription (`lib/services/sarvam_service.dart`). It does
not read or write the same database as the desktop app (`fieldos/` +
SQLite), and there is currently no mechanism to reconcile the two.

This means: a company using the desktop app and the mobile app today has
**two separate, non-syncing data silos**. Building a real sync layer (which
data flows which direction, conflict resolution, auth unification) is a
distinct, not-yet-scoped project — treat it as a prerequisite before mobile
and desktop are used side-by-side on the same real project data.

A second, smaller consequence of the standalone estimation port: any future
change to the calculation rules or reconciliation tolerance in
`fieldos/estimation_calc.py` must be manually mirrored in
`lib/estimation/estimation_calc.dart`, or the two platforms will compute
different numbers for the same BOQ. There is no shared test fixture between
them today — if you change one, check the other.

## Setup

### Prerequisites

- Flutter SDK (stable channel) — this repo was last verified against Flutter 3.44.9 / Dart 3.12.2
- Android Studio + Android SDK, for building/running on Android
- No JDK/Node/Capacitor tooling needed — this is a plain Flutter project

### First-time setup

```bash
cd fieldos_mobile
flutter pub get
```

Add one line to `android/local.properties` (gitignored, machine-specific, alongside your
`flutter.sdk` line) before your first Android build:

```properties
flutter.compileSdkVersion=36
```

Without this, `flutter_plugin_android_lifecycle` (a transitive dependency of `file_picker`)
fails the build with an AAR-metadata error demanding compileSdk >=36 — this Flutter SDK's own
default resolves to 34. This has to live in `local.properties`, not any `build.gradle.kts`
file: Flutter's plugin loader computes one shared `compileSdk` value for the app *and* every
plugin subproject (including ones living in the pub cache, outside this repo) from this exact
property, so overriding only `app/build.gradle.kts`'s own `compileSdk` isn't enough.

### Running

```bash
flutter analyze          # static analysis — should report "No issues found!"
flutter test              # unit/widget test suite
flutter run                # launch on a connected device/emulator
```

### Building a release APK/AAB

```bash
flutter build apk --release
# or, for Play Store:
flutter build appbundle --release
```

## Regenerating drift code

If you change `lib/data/tables.dart` (add/modify a table), regenerate the
generated database code:

```bash
cd fieldos_mobile
dart run build_runner build --delete-conflicting-outputs
```

This regenerates `lib/data/app_database.g.dart` (committed to git — it's
large, ~18.7k lines, but that's normal for drift codegen).

## Features implemented today

- Local account registration/login, company setup, role model (mirrors the
  desktop app's role names: owner / project_manager / site_engineer)
- BOQ estimation entry and reconciliation, matching the desktop app's rules
- Dashboard with project cost summary (estimation vs. actuals, overrun status)
- Procurement chain: RFQ → PO → GRN
- Labour: worker directory, GPS-geofenced attendance punch-in/out
- Subcontractor directory
- Multi-level approvals
- Voice DPR: records audio, sends to Sarvam for transcription + structuring
  into a DPR draft (same Sarvam integration pattern as the desktop app's
  `fieldos/sarvam.py`, requires a Sarvam API key configured in-app under Settings)
- Cost-control agent (`lib/agents/cost_control_agent.dart`)

## Testing

The test suite (`fieldos_mobile/test/`) covers: offline auth (register →
login → session resolution, duplicate-username rejection), labour geofencing
math, the full procurement chain, the estimation → BOQ → actuals → dashboard
pipeline, subcontractor CRUD, and Sarvam response parsing. Run `flutter test`
before any change — as of this writing it's 27/27 passing.

## Future work

- Design and build a real sync protocol to the FastAPI backend, so mobile
  and desktop share one source of truth instead of two silos
- Extract the estimation/reconciliation rules into a single shared
  specification (or generate one implementation from the other) so the
  Python and Dart implementations can't silently diverge
- Decide the long-term fate of `frontend/android/` / Capacitor — either
  formally retire it (delete the generated Android project, keep
  `frontend/MOBILE.md` purely as a historical note) or find it a distinct
  purpose that doesn't overlap with this app
