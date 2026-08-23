/// Real integration test against the local Supabase dev instance (Docker,
/// `supabase start` -- see supabase/ at the repo root). Not mocked: this
/// makes real HTTP calls to a real local Postgres + GoTrue + PostgREST +
/// Realtime stack and checks real results, the same discipline as
/// supabase/rls_verification_test.sql. Skips itself (not a failure) if the
/// local stack isn't running, so the rest of the suite stays runnable
/// without Docker.
library;


import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

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
    if (!stackUp) {
      // ignore: avoid_print
      print('SKIPPING sync_engine_test.dart: local Supabase stack not reachable at '
          '${SyncConfig.local.url}. Run `supabase start` (see supabase/ at repo root) first.');
    }
  });

  group('SyncEngine against a real local Supabase instance', () {
    test('push: a local project write reaches real Postgres via the outbox', () async {
      if (!stackUp) return;

      // --- Setup: a real company + real authenticated user, via the
      // service-role client (bypasses RLS -- this is legitimate test setup,
      // not something the app itself would ever do with this key).
      final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
      final email = 'sync-push-${_uuid.v4()}@test.local';
      final password = 'test-password-123!';
      final signUp = await adminClient.auth.admin.createUser(
        AdminUserAttributes(email: email, password: password, emailConfirm: true),
      );
      final userId = signUp.user!.id;

      final companyId = _uuid.v4();
      await adminClient.from('companies').insert({'id': companyId, 'name': 'Push Test Co'});
      await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});

      // --- The actual thing under test: sign in as a real (non-admin)
      // authenticated user, exactly as the app would.
      final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
      await userClient.auth.signInWithPassword(email: email, password: password);

      final db = AppDatabase.memory();
      final engine = SyncEngine(db: db, client: userClient);

      final project = await db.projectDao.create(ProjectsCompanion.insert(
        id: _uuid.v4(),
        companyId: companyId,
        name: 'Synced via outbox',
        status: const Value('active'),
      ));

      // Confirm the outbox actually captured it before pushing.
      final pendingBefore = await db.syncOutboxDao.pending();
      expect(pendingBefore.length, 1);
      expect(pendingBefore.first.targetTable, 'projects');
      expect(pendingBefore.first.operation, 'insert');

      final result = await engine.pushPending();
      expect(result.succeeded, 1);
      expect(result.failed, 0);

      // Outbox should be drained on success.
      expect(await db.syncOutboxDao.pending(), isEmpty);

      // The real proof: query real Postgres directly (service-role client,
      // bypassing RLS, to unambiguously confirm the row is really there
      // regardless of the pushing user's own read access).
      final remoteRows = await adminClient.from('projects').select().eq('id', project.id);
      expect(remoteRows.length, 1);
      expect(remoteRows.first['name'], 'Synced via outbox');
      expect(remoteRows.first['company_id'], companyId);

      await userClient.dispose();
      await adminClient.dispose();
    });

    test('push failure (RLS rejection) is recorded, not silently dropped or crashed', () async {
      if (!stackUp) return;

      final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
      final email = 'sync-reject-${_uuid.v4()}@test.local';
      final password = 'test-password-123!';
      await adminClient.auth.admin.createUser(
        AdminUserAttributes(email: email, password: password, emailConfirm: true),
      );

      // Deliberately give this user NO company membership at all -- any
      // project insert they attempt must be rejected by RLS.
      final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
      await userClient.auth.signInWithPassword(email: email, password: password);

      final db = AppDatabase.memory();
      final engine = SyncEngine(db: db, client: userClient);

      await db.projectDao.create(ProjectsCompanion.insert(
        id: _uuid.v4(),
        companyId: _uuid.v4(), // a company this user has no membership in
        name: 'Should be rejected',
        status: const Value('active'),
      ));

      final result = await engine.pushPending();
      expect(result.failed, 1, reason: 'RLS should reject this insert -- the user has no company membership');
      expect(result.succeeded, 0);

      // The failed entry must still be in the outbox (not silently
      // dropped), with the retry count incremented and an error recorded --
      // that's the whole point of an outbox over a fire-and-forget push.
      final stillPending = await db.syncOutboxDao.pending();
      expect(stillPending.length, 1);
      expect(stillPending.first.retryCount, 1);
      expect(stillPending.first.lastError, isNotNull);

      await userClient.dispose();
      await adminClient.dispose();
    });

    test('pull: a project created directly in Postgres (another employee\'s device) merges into local Drift', () async {
      if (!stackUp) return;

      final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
      final email = 'sync-pull-${_uuid.v4()}@test.local';
      final password = 'test-password-123!';
      final signUp = await adminClient.auth.admin.createUser(
        AdminUserAttributes(email: email, password: password, emailConfirm: true),
      );
      final userId = signUp.user!.id;

      final companyId = _uuid.v4();
      await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull Test Co'});
      await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});

      // Simulate a teammate's phone already having synced a project up.
      final remoteProjectId = _uuid.v4();
      await adminClient.from('projects').insert({
        'id': remoteProjectId,
        'company_id': companyId,
        'name': 'Created on a teammate\'s phone',
        'status': 'active',
      });

      final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
      await userClient.auth.signInWithPassword(email: email, password: password);

      // Fresh local database -- this device has never seen this project.
      final db = AppDatabase.memory();
      final engine = SyncEngine(db: db, client: userClient);

      expect(await db.projectDao.byId(remoteProjectId), isNull);

      await engine.pullAll();

      final pulled = await db.projectDao.byId(remoteProjectId);
      expect(pulled, isNotNull);
      expect(pulled!.name, 'Created on a teammate\'s phone');
      expect(pulled.companyId, companyId);

      await userClient.dispose();
      await adminClient.dispose();
    });
  });
}
