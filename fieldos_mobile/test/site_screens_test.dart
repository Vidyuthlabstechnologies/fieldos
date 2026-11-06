import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/labour/attendance_list.dart';
import 'package:fieldos_mobile/providers.dart';

LabourAttendanceData _punch(String name, DateTime inAt, {DateTime? out, bool? onSite = true}) => LabourAttendanceData(
      id: '$name$inAt',
      projectId: 'p',
      workerName: name,
      recordedBy: 'u',
      punchIn: inAt,
      punchOut: out,
      withinGeofence: onSite,
      createdAt: inAt,
    );

void main() {
  group('attendance list', () {
    final now = DateTime(2026, 11, 6, 12);

    Future<List<LabourAttendanceData>> pump(WidgetTester tester, List<LabourAttendanceData> rows) async {
      final punchedOut = <LabourAttendanceData>[];
      final timeSet = <LabourAttendanceData>[];
      await tester.pumpWidget(MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AttendanceList(rows: rows, now: now, onPunchOut: punchedOut.add, onSetOutTime: timeSet.add),
          ),
        ),
      ));
      return [...punchedOut, ...timeSet];
    }

    testWidgets('groups by day, newest first, with times in words', (tester) async {
      await pump(tester, [
        _punch('Suresh', DateTime(2026, 11, 5, 8), out: DateTime(2026, 11, 5, 17, 30)),
        _punch('Ramesh', DateTime(2026, 11, 6, 9, 5)),
      ]);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Today')).dy, lessThan(tester.getTopLeft(find.text('Yesterday')).dy));
      expect(find.textContaining('In 9:05 am · not out yet'), findsOneWidget);
      expect(find.textContaining('In 8:00 am · out 5:30 pm · 9 h 30 min'), findsOneWidget);
      expect(find.text('Punch out'), findsOneWidget);
      expect(find.textContaining('2026-11'), findsNothing);
    });

    testWidgets('a punch left open on an earlier day goes to the top and asks for the time out', (tester) async {
      await pump(tester, [
        _punch('Ramesh', DateTime(2026, 11, 6, 9)),
        _punch('Mahesh', DateTime(2026, 11, 3, 9)),
      ]);
      expect(find.text('Not punched out'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Not punched out')).dy, lessThan(tester.getTopLeft(find.text('Today')).dy));
      expect(find.text('Set time out'), findsOneWidget);
      expect(find.textContaining('In 3 Nov, 9:00 am'), findsOneWidget);
    });

    testWidgets('shows a week at a time', (tester) async {
      await pump(tester, [
        _punch('Ramesh', DateTime(2026, 11, 6, 9), out: DateTime(2026, 11, 6, 11)),
        _punch('Old', DateTime(2026, 10, 10, 9), out: DateTime(2026, 10, 10, 17)),
      ]);
      expect(find.textContaining('Old'), findsNothing);
      await tester.tap(find.text('Show earlier days (1 more)'));
      await tester.pump();
      expect(find.text('Old'), findsOneWidget);
    });
  });

  group('approvals and dashboard', () {
    Future<(ProviderContainer, AppDatabase, String)> setUpCompany(WidgetTester tester) async {
      final db = AppDatabase.memory();
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      late String companyId;
      await tester.runAsync(() async {
        final session = container.read(sessionProvider.notifier);
        await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
        companyId = (await session.createCompany('Sri Sai Constructions')).id;
        await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: companyId, name: 'Tower B'));
      });
      return (container, db, companyId);
    }

    Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildFieldOsTheme(Brightness.dark), home: home),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('an approval names its project, and the owner can approve it', (tester) async {
      final (container, db, companyId) = await setUpCompany(tester);
      await tester.runAsync(() async {
        await raiseBudgetOverrunApproval(db, 'p1', -25000);
        // Another company's approval on the same phone stays out of the list.
        await db.projectDao.create(ProjectsCompanion.insert(id: 'other', companyId: 'someone-else', name: 'Not ours'));
        await raiseBudgetOverrunApproval(db, 'other', -1);
      });
      await pumpApp(tester, container, ApprovalsScreen(companyId: companyId));
      expect(find.text('Site over budget'), findsOneWidget);
      expect(find.textContaining('Tower B · raised today'), findsOneWidget);
      expect(find.text('Spending is ₹25,000 over the BOQ budget.'), findsOneWidget);
      expect(find.textContaining('Not ours'), findsNothing);
      expect(find.textContaining('p1'), findsNothing);

      await tester.tap(find.text('Approve'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a site engineer sees what is waiting but cannot decide it', (tester) async {
      final (container, db, companyId) = await setUpCompany(tester);
      await tester.runAsync(() async {
        await raiseBudgetOverrunApproval(db, 'p1', -100);
        await container.read(sessionProvider.notifier).setLocalRole(companyId, 'site_engineer');
      });
      await pumpApp(tester, container, ApprovalsScreen(companyId: companyId));
      expect(find.text('Site over budget'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.textContaining('The owner or a project manager decides these'), findsOneWidget);
    });

    testWidgets('a new site with no BOQ is "no budget yet", never "over budget"', (tester) async {
      final (container, db, companyId) = await setUpCompany(tester);
      await tester.runAsync(() async {
        await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: 'e1',
          projectId: 'p1',
          category: 'materials',
          amount: 125000,
          incurredOn: '2026-11-01',
          recordedBy: 'u1',
          note: const Value('cement'),
        ));
      });
      await pumpApp(tester, container, DashboardScreen(companyId: companyId, companyName: 'Sri Sai Constructions'));
      expect(find.text('No budget yet'), findsOneWidget);
      expect(find.text('Over budget'), findsNothing);
      expect(find.text('₹1,25,000'), findsOneWidget);
      expect(find.text('Ask for approval'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
