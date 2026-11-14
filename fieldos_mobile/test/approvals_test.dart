import 'package:drift/drift.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('budget overrun raises a pending approval, then can be decided', () async {
    final db = AppDatabase.memory();
    await raiseBudgetOverrunApproval(db, 'p1', -650.0, requestedBy: 'u1');

    var pending = await db.approvalDao.pendingFor(null);
    expect(pending.length, 1);
    expect(pending.first.entityType, 'budget_overrun');

    await db.approvalDao.decide(pending.first.id, true, 'approver1', null);
    pending = await db.approvalDao.pendingFor(null);
    expect(pending.length, 0);

    final decided = (await db.approvalDao.pendingFor(null)); // empty
    expect(decided, isEmpty);
  });

  test('a decided approval is not decided again', () async {
    // A manager approves; a second manager whose list was opened before the
    // pull taps Reject on the same request. The first decision stands.
    final db = AppDatabase.memory();
    await raiseBudgetOverrunApproval(db, 'p1', -650.0, requestedBy: 'u1');
    final id = (await db.approvalDao.pendingFor(null)).single.id;

    expect(await db.approvalDao.decide(id, true, 'pm1', null), isTrue);
    final queued = (await db.syncOutboxDao.pending()).length;
    expect(await db.approvalDao.decide(id, false, 'pm2', 'Too costly'), isFalse);

    final row = await (db.select(db.approvals)..where((a) => a.id.equals(id))).getSingle();
    expect(row.status, 'approved');
    expect(row.approverId, 'pm1');
    expect(row.decisionNote, isNot(contains('Too costly')));
    expect((await db.syncOutboxDao.pending()).length, queued);
    await db.close();
  });

  test('DPR-detected issue links back to its DPR entry', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));
    final dprId = _uuid.v4();
    await db.dprDao.create(DprEntriesCompanion.insert(
      id: dprId,
      projectId: project.id,
      createdBy: 'u1',
      entryDate: DateTime.now(),
      workSummary: 'Crack found in wall',
      manpowerCount: const Value(5),
      source: const Value('voice'),
    ));
    await db.issueDao.create(IssuesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      dprEntryId: Value(dprId),
      description: 'Cracks observed',
      severity: const Value('medium'),
      status: const Value('open'),
    ));

    final issues = await db.issueDao.forProject(project.id);
    expect(issues.length, 1);
    expect(issues.first.dprEntryId, dprId);
  });
}
