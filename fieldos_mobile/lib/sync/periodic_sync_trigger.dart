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
  PeriodicSyncTrigger({
    required this.service,
    this.interval = const Duration(minutes: 5),
    this.maxInterval = const Duration(minutes: 60),
    this.onError,
    this.onSuccess,
  });

  final Future<void> Function(SyncPushResult result)? onSuccess;

  final CloudSyncService service;
  final Duration interval;

  /// The longest the wait grows to while syncing keeps failing.
  final Duration maxInterval;

  /// How long to wait before the next try after [failures] failures in a row:
  /// [interval] while all is well, then doubling up to [maxInterval]. A phone
  /// with no signal for hours (a basement, a site out of range) stops
  /// spending its battery on tries that cannot work, and the very first
  /// success, or any manual sync, brings the normal rhythm back at once.
  static Duration delayAfter(int failures, Duration interval, Duration maxInterval) {
    if (failures <= 0) return interval;
    var d = interval;
    for (var i = 0; i < failures && d < maxInterval; i++) {
      d *= 2;
    }
    return d < maxInterval ? d : maxInterval;
  }

  int _failures = 0;
  bool _active = false;
  bool _syncing = false;

  /// Failed syncs in a row (0 after a success).
  int get consecutiveFailures => _failures;

  /// The wait before the next scheduled try.
  Duration get currentDelay => delayAfter(_failures, interval, maxInterval);

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

  bool get isRunning => _active;

  void start() {
    stop();
    _failures = 0;
    _active = true;
    _arm();
  }

  void stop() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  /// One shot, re-armed after each try (not a fixed periodic timer) so the
  /// wait can grow while syncing fails.
  void _arm() {
    _timer?.cancel();
    _timer = Timer(currentDelay, () async {
      await tick();
      if (_active) _arm();
    });
  }

  /// Runs one sync attempt now, independent of the timer -- what the Timer
  /// calls on each interval, and also callable directly (by a caller, or a
  /// test) without waiting for a real interval to elapse.
  Future<void> tick() async {
    if (!service.isSignedIn) return;
    // A sync already under way (a slow upload on a weak link) is not started a
    // second time by the timer or by the app coming back to the front.
    if (_syncing) return;
    _syncing = true;
    try {
      lastResult = await service.syncNow();
      lastError = null;
      _failures = 0;
      await onSuccess?.call(lastResult!);
    } catch (e) {
      lastError = e;
      _failures++;
      onError?.call(e);
    } finally {
      _syncing = false;
    }
  }
}
