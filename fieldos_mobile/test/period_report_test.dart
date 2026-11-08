import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reports/period_report.dart';
import 'package:fieldos_mobile/features/reports/period_report_screen.dart';
import 'package:fieldos_mobile/providers.dart';

/// There was no weekly or monthly report: owners copied each day's DPR by
/// hand to send the client a Saturday update.
void main() {
  // Thursday 12 Nov 2026.
  final now = DateTime(2026, 11, 12, 18);

  test('weeks start on Monday and months on the 1st', () {
    final w = periodFor(PeriodKind.thisWeek, now);
    expect(w.start, DateTime(2026, 11, 9));
    expect(w.end, DateTime(2026, 11, 13));
    final lw = periodFor(PeriodKind.lastWeek, now);
    expect(lw.start, DateTime(2026, 11, 2));
    expect(lw.lastDay, DateTime(2026, 11, 8));
    expect(periodFor(PeriodKind.thisMonth, now).start, DateTime(2026, 11, 1));
    final lm = periodFor(PeriodKind.lastMonth, DateTime(2026, 1, 5));
    expect(lm.start, DateTime(2025, 12, 1));
    expect(lm.lastDay, DateTime(2025, 12, 31));
  });

  test('first line is trimmed to fit', () {
    expect(firstLine('\n  Slab casting done \nshuttering next'), 'Slab casting done');
    expect(firstLine('a' * 200, max: 10), '${'a' * 9}…');
  });

  Future<(AppDatabase, Project)> seed() async {
    final db = AppDatabase.memory();
    final p = await db.projectDao.create(ProjectsCompanion.insert(id: 'p', companyId: 'c', name: 'Green Valley'));
    Future<void> dpr(int day, String text, int people) => db.dprDao.create(DprEntriesCompanion.insert(
          id: 'd$day-${text.length}',
          projectId: 'p',
          createdBy: 'u',
          entryDate: DateTime(2026, 11, day, 17),
          workSummary: text,
          manpowerCount: Value(people),
        ));
    await dpr(9, 'Plinth beam shuttering\nmore lines', 12);
    await dpr(10, 'Steel tying for plinth beam', 14);
    await dpr(10, 'Evening: curing', 2);
    await dpr(3, 'Last week work', 9); // outside this week
    for (final w in ['w1', 'w2']) {
      for (final day in [9, 10]) {
        await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: '$w-$day',
          projectId: 'p',
          workerName: w,
          workerId: Value(w),
          recordedBy: 'u',
          punchIn: DateTime(2026, 11, day, 8),
        ));
      }
    }
    await db.taskDao.create(TasksCompanion.insert(id: 't1', projectId: 'p', title: 'Footings', status: const Value('done'), progress: const Value(100)));
    await db.taskDao.create(TasksCompanion.insert(
        id: 't2', projectId: 'p', title: 'Plinth beam', dueDate: Value(DateTime(2026, 11, 5)), progress: const Value(50)));
    // Finished last week, so not in this week's list.
    await db.taskDao.create(TasksCompanion.insert(
        id: 't3', projectId: 'p', title: 'Excavation', status: const Value('done'), progress: const Value(100)));
    await (db.update(db.tasks)..where((t) => t.id.equals('t1'))).write(TasksCompanion(updatedAt: Value(DateTime(2026, 11, 10))));
    await (db.update(db.tasks)..where((t) => t.id.equals('t3'))).write(TasksCompanion(updatedAt: Value(DateTime(2026, 11, 4))));
    await db.issueDao.create(IssuesCompanion.insert(
        id: 'i1', projectId: 'p', description: 'Cement short by 20 bags', createdAt: Value(DateTime(2026, 11, 10))));
    await db.issueDao.create(IssuesCompanion.insert(
        id: 'i2',
        projectId: 'p',
        description: 'Old leak',
        status: const Value('resolved'),
        createdAt: Value(DateTime(2026, 9, 1)),
        resolvedAt: Value(DateTime(2026, 11, 11))));
    for (final (i, q) in [(1, 50.0), (2, 30.0)]) {
      await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: 'r$i',
        projectId: 'p',
        materialName: 'Cement',
        quantity: q,
        unit: const Value('bags'),
        amount: q * 400,
        receivedBy: 'u',
        receivedOn: DateTime(2026, 11, 9 + i),
      ));
    }
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e1', projectId: 'p', category: 'transport', amount: 1500, incurredOn: '2026-11-10', recordedBy: 'u'));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e2', projectId: 'p', category: 'food', amount: 700, incurredOn: '2026-09-30', recordedBy: 'u'));
    await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: 'm1', projectId: 'p', amount: 50000, receivedOn: DateTime(2026, 11, 11), fromParty: 'Client', mode: 'upi', recordedBy: 'u'));
    return (db, p);
  }

  test('this week is put together from the site records', () async {
    final (db, p) = await seed();
    addTearDown(db.close);
    final r = await buildPeriodReport(db, p, periodFor(PeriodKind.thisWeek, now), now: now);
    expect(r.reportsFiled, 2, reason: 'two days, the second with two reports');
    expect(r.workingDays, 4, reason: 'Monday to Thursday');
    expect(r.days.last.text, 'Steel tying for plinth beam / Evening: curing');
    expect(r.days.last.people, 16);
    expect(r.labourDays, 4, reason: 'attendance wins over the headcount');
    expect(r.tasksFinished, ['Footings']);
    expect(r.lateTasks, 1);
    expect(r.progressNow, 83);
    expect(r.issuesRaised, ['Cement short by 20 bags']);
    expect(r.issuesFixed, 1);
    expect(r.issuesOpen, 1);
    expect(r.materials.single.qty, 80);
    expect(r.spent, 1500);
    expect(r.received, 50000);

    final text = periodReportText(r, companyName: 'Sri Sai Constructions');
    expect(text, contains('*Green Valley* – This week'));
    expect(text, contains('Daily reports: 2 of 4 days'));
    expect(text, contains('✔ Footings'));
    expect(text, contains('• Cement: 80 bags'));
    expect(text, contains('*Issues*: 1 raised, 1 fixed, 1 open'));
    expect(text, contains('spent ₹'));
    expect(periodReportText(r, companyName: 'x', showMoney: false), isNot(contains('*Money*')));
  });

  test('without attendance, labour comes from the report headcounts', () async {
    final (db, p) = await seed();
    addTearDown(db.close);
    await db.delete(db.labourAttendance).go();
    final r = await buildPeriodReport(db, p, periodFor(PeriodKind.thisWeek, now), now: now);
    expect(r.labourDays, 28);
  });

  testWidgets('the screen switches period and offers sharing', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late AppDatabase db;
    late Project p;
    await tester.runAsync(() async => (db, p) = await seed());
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: PeriodReportScreen(project: p, now: now)),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('2 of 4 days reported'), findsOneWidget);
    expect(find.text('Footings'), findsOneWidget);
    expect(find.text('Share on WhatsApp'), findsOneWidget);
    expect(find.text('MONEY'), findsNothing, reason: 'no owner signed in');

    await tester.tap(find.text('Last week'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('1 of 7 days reported'), findsOneWidget);
    expect(find.text('Excavation'), findsOneWidget);

    await tester.tap(find.text('Last month'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Nothing recorded in this period'), findsOneWidget);
    expect(find.text('Share on WhatsApp'), findsNothing);
  });
}
