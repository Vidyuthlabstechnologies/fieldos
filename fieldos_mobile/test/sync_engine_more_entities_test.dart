/// Same real-infrastructure discipline as test/sync_engine_test.dart,
/// covering the second wave of wired entities: DPR entries, Issues, and
/// Workers. Deliberately does NOT cover MaterialReceipts -- see
/// lib/sync/sync_mappers.dart's docstring for why that one has no honest
/// mapping to the desktop schema's material_entries shape.
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
  });

  test('DPR entry, Issue, and Worker each push through the outbox and land in real Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-more-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'More Entities Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final dpr = await db.dprDao.create(DprEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      createdBy: userId,
      entryDate: DateTime(2026, 1, 1),
      workSummary: 'Poured foundation',
      manpowerCount: const Value(12),
    ));
    final issue = await db.issueDao.create(IssuesCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      description: 'Cracked beam near column C4',
      severity: const Value('high'),
    ));
    final worker = await db.workerDao.create(WorkersCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      name: 'Ramesh',
      role: const Value('mason'),
    ));

    expect(await db.syncOutboxDao.pendingCount(), 3);

    final result = await engine.pushPending();
    expect(result.succeeded, 3);
    expect(result.failed, 0);
    expect(await db.syncOutboxDao.pending(), isEmpty);

    final remoteDpr = await adminClient.from('dpr_entries').select().eq('id', dpr.id);
    expect(remoteDpr.length, 1);
    expect(remoteDpr.first['work_summary'], 'Poured foundation');
    expect(remoteDpr.first['manpower_count'], 12);

    final remoteIssue = await adminClient.from('issues').select().eq('id', issue.id);
    expect(remoteIssue.length, 1);
    expect(remoteIssue.first['severity'], 'high');

    final remoteWorker = await adminClient.from('workers').select().eq('id', worker.id);
    expect(remoteWorker.length, 1);
    expect(remoteWorker.first['name'], 'Ramesh');

    // Now the update paths: resolve the issue, deactivate the worker.
    await db.issueDao.resolve(issue.id);
    await db.workerDao.setStatus(worker.id, 'inactive');
    final updateResult = await engine.pushPending();
    expect(updateResult.succeeded, 2);

    final resolvedRemote = await adminClient.from('issues').select().eq('id', issue.id);
    expect(resolvedRemote.first['status'], 'resolved');
    expect(resolvedRemote.first['resolved_at'], isNotNull);

    final inactiveRemote = await adminClient.from('workers').select().eq('id', worker.id);
    expect(inactiveRemote.first['status'], 'inactive');

    await userClient.dispose();
    await adminClient.dispose();
  });

  test('pullAll merges DPR entries, Issues, and Workers created directly in Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-more-pull-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull More Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final dprId = _uuid.v4();
    final issueId = _uuid.v4();
    final workerId = _uuid.v4();
    await adminClient.from('dpr_entries').insert({
      'id': dprId,
      'project_id': projectId,
      'created_by': userId,
      'entry_date': '2026-01-02',
      'work_summary': 'Remote-created DPR',
      'manpower_count': 5,
    });
    await adminClient.from('issues').insert({
      'id': issueId,
      'project_id': projectId,
      'description': 'Remote-created issue',
      'severity': 'low',
    });
    await adminClient.from('workers').insert({'id': workerId, 'project_id': projectId, 'name': 'Suresh'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);
    await engine.pullAll();

    final localDpr = await db.dprDao.byId(dprId);
    expect(localDpr, isNotNull);
    expect(localDpr!.workSummary, 'Remote-created DPR');

    final localIssues = await db.issueDao.forProject(projectId);
    expect(localIssues.any((i) => i.id == issueId && i.description == 'Remote-created issue'), isTrue);

    final localWorkers = await db.workerDao.forProject(projectId);
    expect(localWorkers.any((w) => w.id == workerId && w.name == 'Suresh'), isTrue);

    await userClient.dispose();
    await adminClient.dispose();
  });
}
