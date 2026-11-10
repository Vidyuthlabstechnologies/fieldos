/// Outbox replay safety (audit P0, 2026-11-10), against the local Supabase
/// stack (skips itself if it is not running): a write the server already
/// committed is not left looking unsent, an update that touched nothing is
/// not marked sent, one refused write does not hold up the rest, and being
/// offline never parks a write.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<({CloudPhone owner, String companyId, Project project})> ownerWithSite() async {
    final owner = await CloudPhone.signUp('owner');
    final company = await owner.db.companyDao.create('Replay Co');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Tower A', status: const Value('active')));
    expect((await owner.engine.pushPending()).failed, 0);
    return (owner: owner, companyId: company.id, project: project);
  }

  test('an insert the server committed before the answer was lost is done on replay', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final s = await ownerWithSite();
    final task = await s.owner.db.taskDao.create(TasksCompanion.insert(
        id: uuid.v4(), projectId: s.project.id, title: 'Shuttering, 3rd slab'));
    // The request reached Postgres and committed, then the phone lost the
    // response: the row is on the server and the outbox entry is still here.
    await s.owner.client.from('tasks').insert(taskToSupabaseJson(task));
    expect(await s.owner.db.syncOutboxDao.pendingCount(), 1);

    final replay = await s.owner.engine.pushPending();
    expect(replay.failed, 0);
    expect(replay.succeeded, 1);
    expect(await s.owner.db.syncOutboxDao.pendingCount(), 0);
    expect(await s.owner.db.syncOutboxDao.parkedCount(), 0);
    final rows = await s.owner.client.from('tasks').select().eq('id', task.id);
    expect(rows, hasLength(1));
    await s.owner.close();
  });

  test('an update the server refused (zero rows) stays queued with the reason, not marked sent', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final s = await ownerWithSite();
    final engineer = await CloudPhone.signUp('engineer');
    final cloud = await s.owner.service.registerCompany(companyId: s.companyId, name: 'Replay Co');
    await engineer.service.joinCompany(cloud.joinCode!);
    // The owner's expense reaches the engineer's phone.
    await s.owner.db.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: s.project.id, category: 'Material', amount: 1200, incurredOn: '2026-11-09',
        recordedBy: s.owner.localUserId));
    expect((await s.owner.engine.pushPending()).failed, 0);
    await engineer.engine.pullAll();
    final theirs = (await engineer.db.expenseDao.forProject(s.project.id)).single;

    // Only the writer or an owner/PM may correct it; the server's
    // row-level security makes the engineer's update match zero rows.
    await engineer.db.expenseDao.edit(theirs.id, const SiteExpensesCompanion(amount: Value(99)), by: engineer.localUserId);
    final push = await engineer.engine.pushPending();
    expect(push.succeeded, 0);
    expect(push.failed, 1);
    final queued = (await engineer.db.syncOutboxDao.pending()).single;
    expect(queued.lastError, contains('Not applied on the server'));
    expect(queued.retryCount, 1);
    final server = await s.owner.client.from('site_expenses').select('amount').eq('id', theirs.id).single();
    expect((server['amount'] as num).toDouble(), 1200);
    await engineer.close();
    await s.owner.close();
  });

  test('an update after access was taken away is not marked sent', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final s = await ownerWithSite();
    await adminClient().from('company_members').delete().eq('company_id', s.companyId).eq('user_id', s.owner.remoteUserId);
    await s.owner.db.projectDao.setLocation(s.project.id, lat: 17.44, lng: 78.38, radiusM: 150);
    final push = await s.owner.engine.pushPending();
    expect(push.failed, 1);
    expect((await s.owner.db.syncOutboxDao.pending()).single.lastError, contains('no longer shared with you'));
    await s.owner.close();
  });

  test('one refused write does not hold up unrelated ones; its dependants wait', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final s = await ownerWithSite();
    // A project in a company this account is not a member of: refused.
    final stranger = await s.owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: uuid.v4(), name: 'Not mine', status: const Value('active')));
    final childOfRefused = await s.owner.db.taskDao.create(
        TasksCompanion.insert(id: uuid.v4(), projectId: stranger.id, title: 'Depends on the refused project'));
    final unrelated = await s.owner.db.taskDao.create(
        TasksCompanion.insert(id: uuid.v4(), projectId: s.project.id, title: 'Unrelated, should go'));

    final push = await s.owner.engine.pushPending();
    expect(push.succeeded, 1);
    expect(push.failed, 2);
    final left = await s.owner.db.syncOutboxDao.pending();
    expect(left.map((e) => e.recordId), unorderedEquals([stranger.id, childOfRefused.id]));
    expect(left.firstWhere((e) => e.recordId == childOfRefused.id).retryCount, 0,
        reason: 'a write waiting on a refused one is not blamed for it');
    expect(await s.owner.client.from('tasks').select().eq('id', unrelated.id), hasLength(1));
    await s.owner.close();
  });

  test('offline: no try is counted, so an offline phone never parks its writes', () async {
    final db = AppDatabase.memory();
    // Nothing listens on this port: every request fails at the socket.
    final engine = SyncEngine(db: db, client: SupabaseClient('http://127.0.0.1:9', 'anon'));
    final p = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Offline', status: const Value('active')));
    await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Queued'));
    for (var i = 0; i < 8; i++) {
      final r = await engine.pushPending();
      expect(r.succeeded, 0);
    }
    final pending = await db.syncOutboxDao.pending();
    expect(pending, hasLength(2));
    expect(pending.every((e) => e.retryCount == 0), isTrue);
    expect(pending.first.lastError, isNotNull);
    expect(await db.syncOutboxDao.parkedCount(), 0);
    await engine.dispose();
    await db.close();
  });

  test('error classification', () {
    expect(isTransientSyncError(const PostgrestException(message: 'dup', code: '23505')), isFalse);
    expect(isTransientSyncError(const PostgrestException(message: 'rls', code: '42501')), isFalse);
    expect(isTransientSyncError(const PostgrestException(message: 'gateway', code: '503')), isTrue);
    expect(isTransientSyncError(SyncNotAppliedException('tasks', 'x', 'y')), isFalse);
  });
}
