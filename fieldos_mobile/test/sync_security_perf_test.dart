/// Security + performance smoke against the real stack.
///
/// Security: the RLS policy suite (supabase/rls_verification_test.sql)
/// checks policies via psql SET LOCAL sessions -- which is exactly the
/// silent no-op the handoff warns about if run outside an explicit
/// transaction. These tests re-prove the load-bearing denials through the
/// SAME path the app uses (PostgREST as an authenticated non-member), so a
/// policy regression can't hide behind psql quirks.
///
/// Performance: generous hang-detection ceilings, not benchmarks -- a
/// broken retry loop or N+1 pull shows up as a timeout failure here.
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

  test('a signed-in outsider cannot read or write another company\'s data', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);

    // Company A + member.
    final insiderEmail = 'sec-insider-${_uuid.v4()}@test.local';
    final insiderId = (await adminClient.auth.admin.createUser(AdminUserAttributes(
      email: insiderEmail,
      password: 'test-password-123!',
      emailConfirm: true,
    )))
        .user!
        .id;
    final companyIdA = _uuid.v4();
    final projectIdA = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyIdA, 'name': 'Company A'});
    await adminClient.from('company_members').insert({'company_id': companyIdA, 'user_id': insiderId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectIdA, 'company_id': companyIdA, 'name': 'Secret Project', 'status': 'active'});
    await adminClient.from('vendors').insert({
      'id': _uuid.v4(),
      'company_id': companyIdA,
      'name': 'Vendor of A',
      'gst_number': '36AAAAA0000A1Z1',
    });

    // Company B's employee. Never granted access to A.
    final outsiderEmail = 'sec-outsider-${_uuid.v4()}@test.local';
    final outsiderId = (await adminClient.auth.admin.createUser(AdminUserAttributes(
      email: outsiderEmail,
      password: 'test-password-123!',
      emailConfirm: true,
    )))
        .user!
        .id;
    final companyIdB = _uuid.v4();
    final projectIdB = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyIdB, 'name': 'Company B'});
    await adminClient.from('company_members').insert({'company_id': companyIdB, 'user_id': outsiderId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectIdB, 'company_id': companyIdB, 'name': 'B Project', 'status': 'active'});

    final outsiderClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await outsiderClient.auth.signInWithPassword(email: outsiderEmail, password: 'test-password-123!');

    // Reads return empty, not errors (PostgREST semantics under RLS).
    final seenProjects = await outsiderClient.from('projects').select().eq('id', projectIdA);
    expect(seenProjects, isEmpty, reason: 'outsider read company A project');
    final seenVendors = await outsiderClient.from('vendors').select().eq('company_id', companyIdA);
    expect(seenVendors, isEmpty, reason: 'outsider read company A vendors');

    // Writes targeting A's rows are rejected by WITH CHECK / FK visibility.
    expect(
      () => outsiderClient.from('vendors').insert({
        'id': _uuid.v4(),
        'company_id': companyIdA,
        'name': 'Injected Vendor',
      }),
      throwsA(isA<PostgrestException>()),
      reason: 'RLS insert policy let an outsider create a row for company A',
    );

    // Pull merges nothing from company A into the outsider's device.
    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: outsiderClient);
    await engine.pullAll();
    final localVendors = await db.supplierDao.forCompany(companyIdA);
    expect(localVendors, isEmpty);
    final remoteViaPull = await outsiderClient.from('projects').select();
    expect(remoteViaPull.any((p) => p['id'] == projectIdA), isFalse);

    await db.close();
    await outsiderClient.dispose();
    await adminClient.dispose();
  });

  test('push+pull+realtime join complete promptly against the local stack', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'perf-${_uuid.v4()}@test.local';
    final signUp = await adminClient.auth.admin.createUser(AdminUserAttributes(
      email: email,
      password: 'test-password-123!',
      emailConfirm: true,
    ));
    final userId = signUp.user!.id;
    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Perf Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: 'test-password-123!');

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final watch = Stopwatch()..start();

    // 20 writes across three tables -> one push.
    for (var i = 0; i < 10; i++) {
      await db.taskDao.create(TasksCompanion.insert(id: _uuid.v4(), projectId: projectId, title: 'T$i'));
    }
    for (var i = 0; i < 5; i++) {
      await db.supplierDao.create(SuppliersCompanion.insert(id: _uuid.v4(), companyId: companyId, name: 'S$i'));
    }
    for (var i = 0; i < 5; i++) {
      await db.workerDao.create(WorkersCompanion.insert(id: _uuid.v4(), projectId: projectId, name: 'W$i'));
    }
    final pushResult = await engine.pushPending();
    final pushMs = watch.elapsedMilliseconds;
    expect(pushResult.failed, 0);

    watch.reset();
    await engine.pullAll();
    final pullMs = watch.elapsedMilliseconds;

    watch.reset();
    await engine.subscribeToProjectTasks(projectId);
    final realtimeJoinMs = watch.elapsedMilliseconds;

    // Hang-detection ceilings (local stack, ~20 rows): orders of magnitude
    // above healthy timings, far below "something is wedged".
    expect(pushMs, lessThan(60000), reason: '20-row push took $pushMs ms');
    expect(pullMs, lessThan(30000), reason: 'full pull took $pullMs ms');
    expect(realtimeJoinMs, lessThan(15000), reason: 'realtime join took $realtimeJoinMs ms');

    // ignore: avoid_print
    print('sync smoke: push20=${pushMs}ms pull=${pullMs}ms realtimeJoin=${realtimeJoinMs}ms');

    await engine.dispose();
    await db.close();
    await userClient.dispose();
    await adminClient.dispose();
  });
}
