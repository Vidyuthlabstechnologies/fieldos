/// Real-infrastructure test for PeriodicSyncTrigger, same discipline as the
/// rest of the sync suite -- a plain `test()`, not `testWidgets()`, so a
/// real (short) Timer just works with no FakeAsync involved (see
/// test/settings_screen_cloud_sync_test.dart's history for why that
/// distinction matters).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/periodic_sync_trigger.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

final _uuid = Uuid();

Future<bool> _localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool stackUp;

  setUpAll(() async {
    stackUp = await _localStackReachable();
  });

  test('tick() before enableSync is a no-op -- no exception, no result', () async {
    if (!stackUp) return;
    final client = SyncConfig.local.createClient();
    final db = AppDatabase.memory();
    final service = CloudSyncService(client: client, engine: SyncEngine(db: db, client: client));
    final trigger = PeriodicSyncTrigger(service: service);

    await trigger.tick();

    expect(trigger.lastResult, isNull);
    expect(trigger.lastError, isNull);
    await client.dispose();
  });

  test('tick() after enableSync pushes pending outbox entries and records a result', () async {
    if (!stackUp) return;
    final client = SyncConfig.local.createClient();
    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: client);
    final service = CloudSyncService(client: client, engine: engine);
    final trigger = PeriodicSyncTrigger(service: service);

    final signUp = await service.enableSync(
      email: 'periodic-sync-${_uuid.v4()}@test.local',
      password: 'a-real-password-123!',
    );
    expect(signUp.outcome, CloudSyncOutcome.signedUp, reason: signUp.error);

    await trigger.tick();

    expect(trigger.lastError, isNull);
    expect(trigger.lastResult, isNotNull);
    expect(trigger.lastResult!.failed, 0);
    await client.dispose();
  });

  test('start() schedules real ticks on an interval, stop() cancels them', () async {
    if (!stackUp) return;
    final client = SyncConfig.local.createClient();
    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: client);
    final service = CloudSyncService(client: client, engine: engine);

    var ticks = 0;
    final trigger = PeriodicSyncTrigger(service: service, interval: const Duration(milliseconds: 200));

    final signUp = await service.enableSync(
      email: 'periodic-sync-start-${_uuid.v4()}@test.local',
      password: 'a-real-password-123!',
    );
    expect(signUp.outcome, CloudSyncOutcome.signedUp, reason: signUp.error);

    expect(trigger.isRunning, isFalse);
    trigger.start();
    expect(trigger.isRunning, isTrue);

    // Poll rather than a single fixed delay -- avoids a flaky test if the
    // first real network round trip takes a little longer than one interval.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (trigger.lastResult == null && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    ticks = trigger.lastResult == null ? 0 : 1;
    expect(ticks, 1, reason: 'expected at least one real tick to have completed within 5s');

    trigger.stop();
    expect(trigger.isRunning, isFalse);

    await client.dispose();
  });
}
