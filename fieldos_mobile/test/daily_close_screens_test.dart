/// The daily close screens: Today shows what is missing and sends a quiet
/// day in a couple of taps; the manager's board says "not received", never
/// zero activity, and shows when the supervisor's phone last synced.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/daily/daily_reports_screen.dart';
import 'package:fieldos_mobile/features/daily/today_screen.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  Future<(ProviderContainer, AppDatabase, Project)> setUpSite(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late Project p;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      final companyId = (await session.createCompany('Sri Sai Constructions')).id;
      p = await db.projectDao.create(
          ProjectsCompanion.insert(id: 'p1', companyId: companyId, name: 'Tower B', status: const Value('active')));
    });
    return (container, db, p);
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('Today lists what is missing; "Site closed" sends a quiet day', (tester) async {
    final (container, db, p) = await setUpSite(tester);
    await pumpApp(tester, container, TodayScreen(project: p, day: DateTime.now()));
    expect(find.text('Tower B'), findsOneWidget);
    expect(find.textContaining('Still to do: Attendance, Deliveries, Expenses, Work done'), findsOneWidget);
    expect(find.text('No deliveries'), findsOneWidget);
    expect(find.text('No expenses'), findsOneWidget);
    final send = find.widgetWithText(FilledButton, "Send today's report");
    expect(tester.widget<FilledButton>(send).onPressed, isNull);

    await tester.tap(find.text('Site closed today'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Still to do'), findsNothing);
    expect(tester.widget<FilledButton>(send).onPressed, isNotNull);

    // Sending records the day (the share sheet has no plugin in tests).
    await tester.tap(send);
    await settle(tester);
    final events = await tester.runAsync(() => db.dayCloseDao.eventsFor(p.id));
    expect(events!.single.kind, 'submitted');
    expect(events.single.siteClosed, isTrue);
  });

  testWidgets('the board says "not received" with the last sync, never zero activity', (tester) async {
    final (container, db, p) = await setUpSite(tester);
    final now = DateTime.now();
    // A cutoff that has already passed today (unless it's just after
    // midnight, when nothing is due yet).
    final cutoff = now.hour * 60 + now.minute - 1;
    await tester.runAsync(() async {
      await db.dayCloseDao.saveSettings(
          projectId: p.id, cutoffMinutes: cutoff < 0 ? 0 : cutoff, supervisorId: 'cloud-sup', by: 'pm');
      await db.dayCloseDao.replaceSyncStatus(p.companyId, [
        MemberSyncStatusCompanion.insert(
            userId: 'cloud-sup', companyId: p.companyId, lastSyncedAt: DateTime(now.year, now.month, now.day, 0, 0)),
      ]);
    });
    await pumpApp(tester, container, DailyReportsScreen(companyId: p.companyId));
    expect(find.text('Tower B'), findsOneWidget);
    if (cutoff >= 1) {
      // Today's line (and, before the next-morning cut-off, yesterday's
      // too: it isn't counted as missed until then).
      expect(find.textContaining('Report not received · last synced Today, 12:00 am'), findsWidgets);
      expect(find.textContaining('0 submitted, 1 not received'), findsOneWidget);
    }
    expect(find.textContaining('0 people'), findsNothing);
  });
}
