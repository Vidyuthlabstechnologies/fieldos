/// Drives CloudSyncService.syncNow() on a timer, so a signed-in device picks
/// up a colleague's changes (and pushes its own) without the user having to
/// remember to tap "Sync now" in Settings every time. Manual sync stays
/// available for "I need this NOW" -- this is the automatic background
/// layer on top of it.
///
/// Deliberately a plain Dart class, not tied to app lifecycle or a widget --
/// keeps it unit-testable with a real (short) Timer in a plain `test()`,
/// no FakeAsync/testWidgets involved. Wiring *when* it starts/stops (e.g.
/// on session sign-in, app foreground/background) is the caller's job.
library;

import 'dart:async';

import 'cloud_sync_service.dart';
import 'sync_engine.dart';

class PeriodicSyncTrigger {
  PeriodicSyncTrigger({required this.service, this.interval = const Duration(minutes: 5), this.onError});

  final CloudSyncService service;
  final Duration interval;

  /// Called with the error from a failed tick. A periodic background sync
  /// must never crash the app over a transient network blip, but silently
  /// swallowing the failure would hide a real, possibly persistent problem
  /// (e.g. an expired session) -- this is the caller's hook to surface it
  /// (a log line, a Settings-screen "last sync failed" indicator, etc.)
  /// rather than the trigger deciding that for every caller.
  final void Function(Object error)? onError;

  Timer? _timer;

  /// The result of the most recent tick, whichever it was -- lets a caller
  /// (e.g. a Settings screen) show "last synced Xm ago" without having to
  /// separately track ticks itself.
  SyncPushResult? lastResult;
  Object? lastError;

  bool get isRunning => _timer != null;

  void start() {
    stop();
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs one sync attempt now, independent of the timer -- what the Timer
  /// calls on each interval, and also callable directly (by a caller, or a
  /// test) without waiting for a real interval to elapse.
  Future<void> tick() async {
    if (!service.isSignedIn) return;
    try {
      lastResult = await service.syncNow();
      lastError = null;
    } catch (e) {
      lastError = e;
      onError?.call(e);
    }
  }
}
