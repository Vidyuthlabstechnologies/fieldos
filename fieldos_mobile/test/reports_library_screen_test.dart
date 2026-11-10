/// The report library on a phone: an owner finds a report, sees it for all
/// sites, narrows it to one site and to last month, and the screen shows
/// the right total. A site engineer does not see the money-received,
/// salary or sales reports. Telugu on a 320 px phone fits.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/reports_library_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

const _uuid = Uuid();

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));
  final now = DateTime(2026, 11, 20, 10);

  Future<(ProviderContainer, AppDatabase, String)> setUpCompany(WidgetTester tester, {String? role}) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String companyId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      if (role != null) await session.setLocalRole(companyId, role);
      for (final (id, name) in [('p-1', 'Narapally'), ('p-2', 'Kompally')]) {
        await db.projectDao.create(ProjectsCompanion.insert(id: id, companyId: companyId, name: name, status: const Value('active')));
      }
      for (final (site, day, amount) in [('p-1', '2026-11-03', 12000.0), ('p-2', '2026-11-04', 5000.0), ('p-1', '2026-10-20', 7000.0)]) {
        await db.expenseDao.create(SiteExpensesCompanion.insert(
            id: _uuid.v4(), projectId: site, category: 'Material', amount: amount, incurredOn: day, recordedBy: 'u'));
      }
    });
    return (container, db, companyId);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home, {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await settle(tester);
  }

  testWidgets('find a report, see it for all sites, then one site and last month', (tester) async {
    final (container, _, companyId) = await setUpCompany(tester);
    await pumpApp(tester, container, ReportsLibraryScreen(companyId: companyId), size: const Size(412, 9000));
    expect(find.byKey(const Key('report-received')), findsOneWidget, reason: 'the owner sees money received');

    await tester.enterText(find.byKey(const Key('report-search')), 'by site');
    await settle(tester);
    expect(find.byKey(const Key('report-expense-sites')), findsOneWidget);
    expect(find.byKey(const Key('report-received')), findsNothing);

    // Open it directly with a fixed "today", as the library would.
    await pumpApp(tester, container, ReportScreen(report: reportById('expense-sites')!, companyId: companyId, now: now));
    expect(find.byKey(const Key('report-table')), findsOneWidget);
    expect(find.text('Narapally'), findsOneWidget);
    expect(find.text('Kompally'), findsOneWidget);
    expect(find.textContaining('17,000'), findsOneWidget, reason: 'total for this month, both sites');

    await tester.tap(find.byKey(const Key('report-sites')));
    await settle(tester);
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Kompally'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('sites-done')));
    await settle(tester);
    expect(find.text('Kompally'), findsNothing);
    expect(find.textContaining('12,000'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('period-lastMonth')));
    await tester.tap(find.byKey(const Key('period-lastMonth')));
    await settle(tester);
    expect(find.textContaining('7,000'), findsWidgets);
  });

  testWidgets('a site engineer does not see money received, salaries or sales', (tester) async {
    final (container, _, companyId) = await setUpCompany(tester, role: 'site_engineer');
    // Tall enough that the whole list is built.
    await pumpApp(tester, container, ReportsLibraryScreen(companyId: companyId), size: const Size(412, 9000));
    expect(find.byKey(const Key('report-expenses')), findsOneWidget);
    for (final id in ['received', 'site-margin', 'salary-register', 'pipeline', 'store-stock']) {
      expect(find.byKey(Key('report-$id')), findsNothing, reason: id);
    }
  });

  testWidgets('Telugu on a 320 px phone fits', (tester) async {
    final (container, _, companyId) = await setUpCompany(tester);
    setCurrentLanguage(AppLanguage.te);
    await pumpApp(tester, container, ReportsLibraryScreen(companyId: companyId), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await pumpApp(tester, container, ReportScreen(report: reportById('expenses')!, companyId: companyId, now: now),
        size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('ఖర్చులు'), findsWidgets);
  });
}
