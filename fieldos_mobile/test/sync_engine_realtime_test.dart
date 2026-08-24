/// Real integration test against local Supabase Realtime -- same discipline
/// as sync_engine_test.dart. SyncEngine.subscribeToProjectTasks/
/// subscribeToCompanyProjects existed as code with zero test coverage and
/// nothing in the app UI calling them yet; this verifies the mechanism
/// itself actually works against a real Postgres logical-replication feed
/// before anything is built on top of it.
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

/// Polls an async probe until it returns true or the timeout elapses.
/// Realtime delivery is genuinely asynchronous (a websocket event, not a
/// direct response to a call this test makes) -- a fixed delay would either
/// waste time or flake under load, so poll instead.
Future<void> _pollUntilTrue(Future<bool> Function() probe, {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await probe()) return;
    await Future.delayed(const Duration(milliseconds: 150));
  }
  throw StateError('Condition not met within $timeout');
}

void main() {
  late bool stackUp;

  setUpAll(() async {
    stackUp = await _localStackReachable();
  });

  test('subscribeToProjectTasks receives a task inserted directly in Postgres by another device', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-realtime-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Realtime Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    // This device: subscribes, then waits for a change it never pushed itself.
    final deviceClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await deviceClient.auth.signInWithPassword(email: email, password: password);
    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: deviceClient);

    // A UI layer (e.g. ProjectDetailScreen) has no way to know local data
    // changed underneath it unless SyncEngine tells it -- verify the
    // onTasksChanged hook actually fires, not just that the row lands.
    var callbackFired = false;
    engine.onTasksChanged = () => callbackFired = true;

    await engine.subscribeToProjectTasks(projectId);

    // Another device: creates a task directly in Postgres, the way
    // pushPending() would from a colleague's phone.
    final taskId = _uuid.v4();
    await adminClient.from('tasks').insert({
      'id': taskId,
      'project_id': projectId,
      'title': 'Remote-created via Realtime',
      'status': 'todo',
    });

    await _pollUntilTrue(() async {
      final local = await db.taskDao.forProject(projectId);
      return local.any((t) => t.id == taskId);
    });

    final local = await db.taskDao.forProject(projectId);
    final matched = local.firstWhere((t) => t.id == taskId);
    expect(matched.title, 'Remote-created via Realtime');
    expect(matched.status, 'todo');
    expect(callbackFired, isTrue, reason: 'onTasksChanged should fire so a UI layer knows to refresh');

    await engine.dispose();
    await deviceClient.dispose();
    await adminClient.dispose();
  });
}
