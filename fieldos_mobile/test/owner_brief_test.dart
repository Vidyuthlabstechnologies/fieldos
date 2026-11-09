import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/brief/owner_brief.dart';

/// Owners phone every site each evening to ask how the day went. The
/// brief answers that from what the sites recorded, worst site first.
void main() {
  // Tuesday 10 Nov 2026, 7:30 pm.
  final now = DateTime(2026, 11, 10, 19, 30);
  final today = DateTime(2026, 11, 10);

  Future<AppDatabase> seed() async {
    final db = AppDatabase.memory();
    Future<void> site(String id, String name, {String status = 'active'}) async => db.projectDao
        .create(ProjectsCompanion.insert(id: id, companyId: 'c', name: name, status: Value(status)));
    await site('good', 'Asha Villa');
    await site('bad', 'Reddy House');
    await site('old', 'Finished Flats', status: 'completed');

    // Asha Villa: a normal day.
    await db.dprDao.create(DprEntriesCompanion.insert(
        id: 'd1', projectId: 'good', createdBy: 'u', entryDate: DateTime(2026, 11, 10, 17), workSummary: 'Slab shuttering\nmore'));
    for (final w in ['w1', 'w2', 'w3']) {
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: 'a-$w', projectId: 'good', workerName: w, workerId: Value(w), recordedBy: 'u', punchIn: DateTime(2026, 11, 10, 8)));
    }
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'r1', projectId: 'good', materialName: 'Cement', quantity: 40, unit: const Value('bags'), amount: 16000,
        receivedBy: 'u', receivedOn: DateTime(2026, 11, 10, 11)));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e1', projectId: 'good', category: 'transport', amount: 1200, incurredOn: '2026-11-10', recordedBy: 'u'));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e2', projectId: 'good', category: 'food', amount: 999, incurredOn: '2026-11-09', recordedBy: 'u'));
    await db.taskDao.create(TasksCompanion.insert(
        id: 't1', projectId: 'good', title: 'Column casting', dueDate: Value(DateTime(2026, 11, 11))));

    // Reddy House: no report, nobody in, a late task and a serious issue.
    await db.taskDao.create(TasksCompanion.insert(
        id: 't2', projectId: 'bad', title: 'Plinth beam', dueDate: Value(DateTime(2026, 11, 2)), progress: const Value(40)));
    await db.issueDao.create(IssuesCompanion.insert(
        id: 'i1', projectId: 'bad', description: 'Crack in column C3', severity: const Value('high'),
        createdAt: Value(DateTime(2026, 11, 10, 10))));
    return db;
  }

  test('ranks the site that needs the owner first and skips finished sites', () async {
    final db = await seed();
    final briefs = await buildOwnerBrief(db, 'c', day: today, now: now);
    expect(briefs.map((b) => b.project.name), ['Reddy House', 'Asha Villa']);

    final bad = briefs.first;
    expect(bad.level, BriefLevel.needsYou);
    expect(bad.flags.map((f) => f.kind),
        [FlagKind.seriousIssues, FlagKind.noReport, FlagKind.nobodyIn, FlagKind.lateTasks]);
    expect(bad.newIssues, ['Crack in column C3']);

    final good = briefs.last;
    expect(good.level, BriefLevel.onTrack);
    expect(good.people, 3);
    expect(good.spent, 1200);
    expect(good.materials, ['Cement 40 bags']);
    expect(good.reportLine, 'Slab shuttering');
    expect(good.dueTomorrow, ['Column casting']);
    await db.close();
  });

  test('yesterday reads as it stood that evening', () async {
    final db = await seed();
    final briefs = await buildOwnerBrief(db, 'c', day: DateTime(2026, 11, 9), now: now);
    final good = briefs.firstWhere((b) => b.project.id == 'good');
    expect(good.spent, 999);
    expect(good.people, 0);
    expect(good.flags.map((f) => f.english), contains('No report that day'));
    await db.close();
  });

  test('the WhatsApp text leads with the totals and hides money when asked', () async {
    final db = await seed();
    final briefs = await buildOwnerBrief(db, 'c', day: today, now: now);
    final text = ownerBriefText(briefs, companyName: 'Sri Sai', day: today);
    expect(text, contains('2 sites · 3 people on site · 1 of 2 reported · ₹1,200 spent'));
    expect(text.indexOf('Reddy House'), lessThan(text.indexOf('Asha Villa')));
    expect(text, contains('⚠ 1 serious issue open, No report yet today'));
    expect(text, contains('Material: Cement 40 bags'));
    final noMoney = ownerBriefText(briefs, companyName: 'Sri Sai', day: today, showMoney: false);
    expect(noMoney, isNot(contains('₹')));
    await db.close();
  });

  test('flags weigh budget, issues, reports, lateness and attendance', () {
    final flags = briefFlags(
        reported: true, people: 4, lateTasks: 9, openHighIssues: 0, newIssues: 2, costStatus: 'at_risk', isToday: true);
    expect(flags.map((f) => f.english), ['9 tasks late', 'Close to budget', '2 new issues']);
    expect(flags.first.weight, 4);
  });
}
