/// Each person's own dashboard figures: the default set, choosing and
/// ordering them, kept per person, never showing a figure the person may
/// not see, and every figure matching its library report.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/dashboard/my_dashboard.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

const _uuid = Uuid();

String _today(int dayOffset) {
  final d = DateTime.now().subtract(Duration(days: dayOffset));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  group('choice', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    test('a new person gets the default figures; an engineer loses the money-received one', () async {
      final mine = await loadKpiChoice(db, 'c', 'u', moneyIn: true, manager: true);
      expect([for (final k in mine) k.id], defaultKpis);
      final eng = await loadKpiChoice(db, 'c', 'e', moneyIn: false, manager: false);
      expect([for (final k in eng) k.id], isNot(contains('received')));
      expect([for (final k in eng) k.id], contains('spent'));
    });

    test('the choice and its order are kept per person; unknown or forbidden ids drop out', () async {
      await saveKpiChoice(db, 'c', 'u', ['salaries', 'late-tasks', 'gone', 'spent']);
      expect([for (final k in await loadKpiChoice(db, 'c', 'u', moneyIn: true, manager: true)) k.id], ['salaries', 'late-tasks', 'spent']);
      expect([for (final k in await loadKpiChoice(db, 'c', 'u', moneyIn: false, manager: false)) k.id], ['late-tasks', 'spent']);
      expect([for (final k in await loadKpiChoice(db, 'c', 'someone-else', moneyIn: true, manager: true)) k.id], defaultKpis);
    });

    test('every figure has a report, a unique id, and reads a real column of it', () {
      expect(kpiLibrary.map((k) => k.id).toSet(), hasLength(kpiLibrary.length));
      final empty = ReportInput(sites: const [], from: DateTime(2026), to: DateTime(2027), now: DateTime(2026, 6));
      for (final k in kpiLibrary) {
        expect(reportById(k.reportId), isNotNull, reason: k.id);
        expect(k.value(k.report.build(empty)), 0, reason: k.id);
      }
    });
  });

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
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p-1', companyId: companyId, name: 'Narapally', status: const Value('active')));
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: _uuid.v4(), projectId: 'p-1', category: 'Material', amount: 12500, incurredOn: _today(0), recordedBy: 'u'));
      await db.taskDao.create(TasksCompanion.insert(
          id: 't1', projectId: 'p-1', title: 'Slab', dueDate: Value(DateTime.now().subtract(const Duration(days: 3)))));
    });
    return (container, db, companyId);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
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

  testWidgets('the dashboard shows my figures; I turn one off and it stays off', (tester) async {
    final (container, db, companyId) = await setUpCompany(tester);
    await pumpApp(tester, container, DashboardScreen(companyId: companyId, companyName: 'Sri Sai Constructions'));
    expect(find.byKey(const Key('kpi-spent')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('kpi-spent')), matching: find.textContaining('12,500')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('kpi-late-tasks')), matching: find.text('1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit-kpis')));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byKey(const Key('pick-received')), matching: find.byType(Checkbox)));
    await settle(tester);
    await tester.tap(find.byKey(const Key('kpis-save')));
    await settle(tester);
    expect(find.byKey(const Key('kpi-received')), findsNothing);
    expect(find.byKey(const Key('kpi-spent')), findsOneWidget);

    final me = container.read(sessionProvider).user!.id;
    final kept = await tester.runAsync(() => db.settingsDao.get(kpiPrefKey(companyId, me)));
    expect(kept, isNot(contains('received')));
  });

  testWidgets('Telugu on a 320 px phone fits', (tester) async {
    final (container, _, companyId) = await setUpCompany(tester);
    setCurrentLanguage(AppLanguage.te);
    await pumpApp(tester, container, DashboardScreen(companyId: companyId, companyName: 'Sri Sai Constructions'),
        size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('edit-kpis')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
