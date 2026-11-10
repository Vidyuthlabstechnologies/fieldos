# Chaquopy Feasibility — Embedding fieldos/ on Android

> **Removed in 1.7.4 (2026-11-11, issue #144).** Nothing in the app called the on-device Python engine: estimation runs on the Dart port (`lib/estimation/estimation_calc.dart`), which `test/estimation_differential_test.dart` still checks against fixtures from the Python reference. Bundling Python 3.13 cost every install a large runtime, started an interpreter on each launch, and kept the app off 32-bit (`armeabi-v7a`) phones because Chaquopy's 3.13 has no 32-bit build. The plugin, `src/main/python/`, `NativeCalcBridge` and its integration test are gone. What follows is the original study, kept for the record.

**Verdict: NO-GO for the "full backend as-is over an on-device HTTP server" scope (§1-4 below,
unchanged). The narrower "just the calc engine" scope (§5) is a confirmed GO — built, and
verified end-to-end on a real emulator: `fieldos/estimation_calc.py` runs unmodified on-device
via Chaquopy, called from Kotlin via a platform channel, with real Decimal precision (including
the IS 1786 steel-weight formula's repeating decimals) round-tripping intact across the
boundary. See `fieldos_mobile/android/app/src/main/python/`,
`fieldos_mobile/lib/estimation/native_calc_bridge.dart`, and
`fieldos_mobile/integration_test/native_calc_bridge_test.dart` (4/4 passing on a real device).**

**Provenance:** researched by the `hermes` agent CLI (nemotron-3-ultra-free via OpenCode Zen,
web tools) on 2026-08-23 against this exact project's real Gradle setup (AGP 9.0.1, Kotlin
2.3.20, `settings.gradle.kts`-based plugin management) and `requirements.txt`. The single most
consequential claim — that Chaquopy's native package repository has no Android build of
`pydantic`/`pydantic-core` — was independently re-fetched and confirmed directly from
chaquo.com/pypi-13.1/ by a second, separate fetch. Not every secondary claim in this document
has been independently re-verified beyond that spot check.

## Two independent blockers, not one

### 1. Two required dependencies have no Android build and can't get one without patching upstream

| Package | Required | Chaquopy repo has | Why it's blocked |
|---|---|---|---|
| `pydantic` (FastAPI 0.115+ requires v2) | ≥2.7 | Nothing — no `pydantic`/`pydantic-core` directory at all | `pydantic-core` is a Rust extension (PyO3/maturin). Compiling it for Android needs PyO3's `abi3` limited API, which doesn't expose the datetime types pydantic-core needs — this is an upstream `pydantic-core` limitation (tracked in their own issue #1607), not a Chaquopy gap they can just close. Chaquopy's own maintainers' documented workaround is pinning `pydantic<2` — which FastAPI 0.115+ doesn't support. |
| `bcrypt` (this codebase's auth uses ≥4.1) | ≥4.1 | Only up to `3.2.2` (Oct 2024) | bcrypt 4.x rewrote its native backend from C to Rust; no Android wheel exists for the Rust version. Downgrading to `bcrypt<4` is possible but is genuinely an old, security-sensitive dependency to pin to indefinitely. |

Independently confirmed: fetching Chaquopy's package index directly shows no `pydantic`,
`pydantic-core`, `sqlalchemy`, or `uvloop` directories. `sqlalchemy`'s absence isn't itself
fatal the same way — it's pure-Python-fallback-capable and could install from plain PyPI —
but `pydantic-core` and `uvloop` genuinely need a compiled wheel that doesn't exist.

`uvicorn[standard]`'s extras (`uvloop`, `httptools`) are in the same boat — plain `uvicorn`
(no extras, pure Python, slower) would be the only installable option.

### 2. Even if every dependency installed, running a persistent server hits a platform-level constraint

This is the more fundamental problem, and it's not a dependency issue at all: CPython's
signal-handling machinery (`set_wakeup_fd`) requires running on the **main thread of the main
interpreter**. A documented real Chaquopy issue (#1243) walked through exactly this: running
uvicorn in `Activity.onCreate()` blocks the UI thread (ANR); running it on a background
`Thread` or a Kotlin coroutine both hit `RuntimeError: set_wakeup_fd only works in main thread
of the main interpreter`. No working solution was posted in that issue — it was closed without
one. The maintainer-recommended pattern for genuinely long-running Python work is a **separate
Android Service process** communicating over IPC (not simply threading), which is a materially
bigger and more fragile piece of engineering than "run uvicorn on a background thread," and
still doesn't cleanly solve the underlying constraint.

## What would actually change this to a GO

1. Pin `pydantic<2` and `bcrypt<4` and downgrade FastAPI accordingly — technically buildable,
   but locks the on-device backend to old, and in bcrypt's case security-sensitive, dependency
   versions indefinitely.
2. Wait for upstream fixes (pydantic-core Android wheels, bcrypt Rust backend Android wheels,
   or Chaquopy adding either to their curated repo) — not actionable on any timeline we control.
3. **Narrow the scope to what has zero risky dependencies.** `fieldos/estimation_calc.py`
   specifically — the one concrete problem this whole investigation started from (Python/Dart
   BOQ precision divergence) — imports nothing but the stdlib `decimal` module. That's
   genuinely, verifiably buildable via Chaquopy today, with none of the blockers above. This is
   the "just the calc engine" scope from the earlier architecture discussion, not the "full
   backend as-is" scope that was actually chosen.

## Recommendation

Don't spend engineering effort on "full FastAPI backend + on-device HTTP server" right now —
the evidence says it doesn't build, independent of how it's wired up. If eliminating the
calc-engine precision-divergence risk is still the actual goal, embedding just
`estimation_calc.py` via Chaquopy (called directly from Kotlin via a platform channel — no
server, no pydantic, no bcrypt, no threading problem since it's a short synchronous
computation, not a long-running process) is the one piece of this idea that's real today.

## 5. The narrow scope: built, and verified end-to-end (2026-08-23)

`fieldos/estimation_calc.py` is copied verbatim into
`fieldos_mobile/android/app/src/main/python/`, wrapped by a thin `calc_bridge.py` that marshals
every `Decimal` across the boundary as a string (never a float, to not reintroduce the precision
risk this exists to eliminate). `MainActivity.kt` starts the Python runtime and exposes it over
a `MethodChannel`; `lib/estimation/native_calc_bridge.dart` is the Dart-side API. Not yet wired
into any screen's actual computation — this pass built and proved the bridge, it hasn't replaced
`estimation_calc.dart`'s usage at any call site (that's a separate, larger follow-up with real
implications: platform-channel calls are async and don't run under `flutter test`'s pure-Dart
VM, so every call site touching it needs a design for how existing widget tests handle that).

Real, non-obvious build issues hit and fixed along the way (all now encoded in the actual Gradle
config, not just this doc):

- Flutter's own default NDK `abiFilters` includes `armeabi-v7a`, which Chaquopy 17's Python 3.13
  distribution doesn't support — `ndk.abiFilters += [...]` **adds** to Flutter's default list
  rather than replacing it; needed `abiFilters.clear()` first.
- `PyObject.callAttr(...)` with a raw Kotlin `null` argument returns a null `PyObject` reference
  itself, not a `PyObject` wrapping Python `None` — calling `.toJava()` on that null crashes.
  Must check for the null argument before calling, not rely on Chaquopy converting it safely.
- Two unrelated, pre-existing Android/Gradle problems surfaced the moment this session did its
  first *real* Gradle build of `fieldos_mobile` (previously only `flutter analyze`/`flutter
  test` had ever run, both pure-Dart, neither touches Android Gradle at all):
  - `file_picker` <11 hardcodes `compileSdk 34` in its own `android/build.gradle`, breaking once
    any dependency needs 36+. Fixed by upgrading — but 11.x turned out to have its own bug:
    it unconditionally skips applying its own Kotlin plugin under AGP 9+, assuming AGP's
    built-in Kotlin compilation will handle it — while `flutter_plugin_android_lifecycle` (a
    near-universal transitive dependency) still unconditionally applies the *traditional*
    Kotlin plugin, which AGP 9 rejects once built-in Kotlin is enabled. The two assumptions are
    mutually exclusive under a single `android.builtInKotlin` setting. Pinned `file_picker` to
    `12.0.0-beta.7` specifically because it's the first version that actually reads and respects
    the `android.builtInKotlin` gradle property instead of assuming.
  - `flutter.compileSdkVersion` (Flutter's own computed default) resolves to 34 for this Flutter
    SDK version, too low for the above — must be overridden via `flutter.compileSdkVersion=36`
    in `android/local.properties` specifically (gitignored, machine-specific, same category as
    the already-present `flutter.sdk` line) — overriding `compileSdk` in `app/build.gradle.kts`
    alone does NOT propagate to plugin subprojects like `file_picker`'s, which read the same
    Flutter-computed value independently. Documented in `docs/MOBILE_GUIDE.md`'s setup section
    so this isn't a "works on my machine" fix.
