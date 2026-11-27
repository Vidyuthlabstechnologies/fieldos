/// A phone with no signal must not keep trying every five minutes for hours
/// (customer review, performance: battery on a site out of range), and a sync
/// still in progress must not be started again. No network is used: a fake
/// stands in for the server.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/periodic_sync_trigger.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

class _FakeService extends CloudSyncService {
  _FakeService(SupabaseClient client, SyncEngine engine) : super(client: client, engine: engine);

  int calls = 0;
  Future<SyncPushResult> Function() behaviour = () async => const SyncPushResult(succeeded: 0, failed: 0);

  @override
  bool get isSignedIn => true;

  @override
  Future<SyncPushResult> syncNow() {
    calls++;
    return behaviour();
  }
}

void main() {
  late AppDatabase db;
  late SupabaseClient client;
  late _FakeService service;

  setUp(() {
    db = AppDatabase.memory();
    client = SupabaseClient('http://localhost:1', 'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
    service = _FakeService(client, SyncEngine(db: db, client: client));
    addTearDown(() async {
      await service.dispose();
      await client.dispose();
      await db.close();
    });
  });

  test('the wait doubles while syncing keeps failing, up to an hour, and is five minutes when all is well', () {
    const five = Duration(minutes: 5), hour = Duration(minutes: 60);
    expect([for (var n = 0; n <= 6; n++) PeriodicSyncTrigger.delayAfter(n, five, hour).inMinutes], [5, 10, 20, 40, 60, 60, 60]);
    expect(PeriodicSyncTrigger.delayAfter(-1, five, hour), five);
    // A short interval for a test, and a cap that is not a multiple of it.
    expect(PeriodicSyncTrigger.delayAfter(3, const Duration(seconds: 10), const Duration(seconds: 50)).inSeconds, 50);
  });

  test('failures lengthen the wait, and the first success brings the normal rhythm back at once', () async {
    final t = PeriodicSyncTrigger(service: service);
    service.behaviour = () async => throw StateError('no signal');
    for (var i = 1; i <= 3; i++) {
      await t.tick();
      expect(t.consecutiveFailures, i);
    }
    expect(t.currentDelay, const Duration(minutes: 40));
    expect(t.lastError, isA<StateError>());

    service.behaviour = () async => const SyncPushResult(succeeded: 2, failed: 0);
    await t.tick();
    expect(t.consecutiveFailures, 0);
    expect(t.currentDelay, const Duration(minutes: 5));
    expect(t.lastError, isNull);
    expect(t.lastResult?.succeeded, 2);
  });

  test('a manual or resume-triggered sync is never held back by the backoff', () async {
    final t = PeriodicSyncTrigger(service: service);
    service.behaviour = () async => throw StateError('no signal');
    for (var i = 0; i < 5; i++) {
      await t.tick();
    }
    expect(t.currentDelay, const Duration(minutes: 60));
    final before = service.calls;
    await t.tick();
    expect(service.calls, before + 1, reason: 'tick() always tries; only the timer waits longer');
  });

  test('a sync still under way is not started a second time', () async {
    final t = PeriodicSyncTrigger(service: service);
    final slow = Completer<SyncPushResult>();
    service.behaviour = () => slow.future;
    final first = t.tick();
    await t.tick(); // the timer, or the app coming back to the front, while the first is still uploading
    await t.tick();
    expect(service.calls, 1);
    slow.complete(const SyncPushResult(succeeded: 1, failed: 0));
    await first;
    await t.tick();
    expect(service.calls, 2, reason: 'and the next one runs once the first is done');
  });

  test('start schedules tries, stop really stops them, even one in flight', () async {
    final t = PeriodicSyncTrigger(service: service, interval: const Duration(milliseconds: 30));
    t.start();
    expect(t.isRunning, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.calls, greaterThanOrEqualTo(2));
    t.stop();
    expect(t.isRunning, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 60)); // let any try already under way finish
    final after = service.calls;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(service.calls, after, reason: 'nothing more after stop');
  });

  test('start resets the wait: signing in again after a long outage syncs on the normal rhythm', () async {
    final t = PeriodicSyncTrigger(service: service, interval: const Duration(minutes: 5));
    service.behaviour = () async => throw StateError('no signal');
    for (var i = 0; i < 4; i++) {
      await t.tick();
    }
    expect(t.currentDelay, const Duration(minutes: 60));
    t.start();
    addTearDown(t.stop);
    expect(t.consecutiveFailures, 0);
    expect(t.currentDelay, const Duration(minutes: 5));
  });
}
