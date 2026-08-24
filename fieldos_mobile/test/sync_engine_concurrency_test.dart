/// Concurrency tests for the sync engine against the real stack.
///
/// These exist because the app genuinely runs concurrent sync paths:
/// PeriodicSyncTrigger's timer overlaps manual "Sync now" taps, and
/// Realtime callbacks upsert local rows mid-push. Two pushPending() calls
/// that drain the same outbox entry must not both hit Postgres -- the
/// loser used to mark an already-succeeded entry as failed (duplicate-id
/// violation), leaving it to retry forever and park as poisoned.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _serviceRoleKey = localServiceRoleKey;

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

  test('concurrent pushPending calls never double-push or poison an outbox entry', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'race-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Race Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    for (var i = 0; i < 3; i++) {
      await db.taskDao.create(TasksCompanion.insert(
        id: _uuid.v4(),
        projectId: projectId,
        title: 'Task $i',
      ));
    }
    expect(await db.syncOutboxDao.pendingCount(), 3);

    // Fire three pushes concurrently -- what happens when the periodic tick,
    // a manual "Sync now", and a post-write flush all land together.
    final results = await Future.wait([
      engine.pushPending(),
      engine.pushPending(),
      engine.pushPending(),
    ]);

    // Exactly one call drains each entry; nobody reports a failure, and no
    // entry ends up marked failed (the old behavior poisoned them here).
    final totalSucceeded = results.fold<int>(0, (a, r) => a + r.succeeded);
    expect(totalSucceeded, 3);
    for (final r in results) {
      expect(r.failed, 0, reason: 'a concurrent push reported failures: $results');
    }

    final outbox = await db.syncOutboxDao.pending();
    expect(outbox, isEmpty);
    final failedRows = await db.syncOutboxDao.parked();
    expect(failedRows, isEmpty, reason: 'outbox entries were poisoned by the race');

    // Exactly one remote row per task -- no duplicates slipped through.
    final remote = await adminClient.from('tasks').select().eq('project_id', projectId);
    expect(remote.length, 3);

    await db.close();
    await userClient.dispose();
    await adminClient.dispose();
  });
}
