/// The stores, tools and salaries screens on a phone: an owner adds a
/// store, brings cement in and sends it to a site whose Stock tab counts it
/// in; adds a tool and hands it over; adds staff and makes the month's
/// salaries. Also in Telugu on a small phone without overflow.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/payroll/payroll_screen.dart';
import 'package:fieldos_mobile/features/procurement/stock_view.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase, String, String)> setUpCompany(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String companyId;
    late String me;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      me = container.read(sessionProvider).user!.id;
      await db.projectDao.create(ProjectsCompanion.insert(
          id: 'p-1', companyId: companyId, name: 'Narapally', status: const Value('active')));
    });
    return (container, db, companyId, me);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home,
      {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await settle(tester);
  }

  testWidgets('a store, cement in, sent to a site, counted in on the site', (tester) async {
    final (container, db, companyId, me) = await setUpCompany(tester);
    await pumpApp(tester, container, WarehouseScreen(companyId: companyId, userId: me));
    expect(find.text('No store yet'), findsOneWidget);

    await tester.tap(find.text('Add store').last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('store-name')), 'Main yard');
    await tester.tap(find.byKey(const Key('store-save')));
    await settle(tester);
    expect(find.text('Main yard'), findsWidgets);

    await tester.tap(find.byKey(const Key('store-inward')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('move-supplier')), 'Balaji Traders');
    await tester.enterText(find.byKey(const Key('move-material')), 'Cement');
    await tester.enterText(find.byKey(const Key('move-qty')), '100');
    await tester.enterText(find.byKey(const Key('move-unit')), 'bags');
    await tester.enterText(find.byKey(const Key('move-rate')), '390');
    await tester.ensureVisible(find.byKey(const Key('move-save')));
    await tester.tap(find.byKey(const Key('move-save')));
    await settle(tester);
    expect(find.text('100 bags'), findsOneWidget);
    expect(find.text('₹39,000'), findsWidgets);

    // Tap the line to send some of it to the site.
    await tester.tap(find.text('Cement').first);
    await settle(tester);
    await tester.tap(find.byKey(const Key('move-to')));
    await settle(tester);
    await tester.tap(find.text('Narapally').last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('move-qty')), '40');
    await tester.ensureVisible(find.byKey(const Key('move-save')));
    await tester.tap(find.byKey(const Key('move-save')));
    await settle(tester);
    expect(find.text('60 bags'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'On the way'));
    await settle(tester);
    expect(find.text('Not yet received'), findsOneWidget);

    // The site counts it in from its Stock tab.
    await pumpApp(tester, container, Scaffold(body: StockView(projectId: 'p-1', userId: me)));
    expect(find.text('On the way here'), findsOneWidget);
    final move = (await tester.runAsync(() => db.warehouseDao.movesForSite('p-1')))!.single;
    await tester.tap(find.byKey(Key('receive-${move.id}')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('receive-qty')), '38');
    await tester.tap(find.byKey(const Key('receive-save')));
    await settle(tester);
    expect(find.text('On the way here'), findsNothing);
    expect(find.text('38 bags'), findsOneWidget);
    expect(find.textContaining('Came in 38'), findsOneWidget);
  });

  testWidgets('a tool is added and handed over', (tester) async {
    final (container, _, companyId, me) = await setUpCompany(tester);
    await pumpApp(tester, container, WarehouseScreen(companyId: companyId, userId: me));
    await tester.tap(find.widgetWithText(Tab, 'Tools'));
    await settle(tester);
    expect(find.text('No tools yet'), findsOneWidget);
    await tester.tap(find.text('Add tool').last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('tool-name')), 'Drill machine');
    await tester.enterText(find.byKey(const Key('tool-value')), '6500');
    await tester.tap(find.byKey(const Key('tool-save')));
    await settle(tester);
    expect(find.text('Drill machine · T-001'), findsOneWidget);
    expect(find.text('In store'), findsOneWidget);

    await tester.tap(find.text('Drill machine · T-001'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('tool-issue')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('issue-person')), 'Ravi');
    await tester.tap(find.byKey(const Key('issue-save')));
    await settle(tester);
    expect(find.text('With someone'), findsWidgets);
    expect(find.textContaining('Ravi'), findsOneWidget);
  });

  testWidgets('staff added and the month made', (tester) async {
    final (container, _, companyId, me) = await setUpCompany(tester);
    await pumpApp(tester, container, StaffSalariesScreen(companyId: companyId, userId: me, month: '2026-11'));
    expect(find.text('No staff yet'), findsOneWidget);
    await tester.tap(find.text('Add staff').last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('staff-name')), 'Anil');
    await tester.enterText(find.byKey(const Key('staff-basic')), '18000');
    await tester.enterText(find.byKey(const Key('staff-hra')), '7000');
    await tester.enterText(find.byKey(const Key('staff-other')), '3000');
    await tester.ensureVisible(find.byKey(const Key('staff-save')));
    await tester.tap(find.byKey(const Key('staff-save')));
    await settle(tester);

    expect(find.text('November 2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('make-month')));
    await settle(tester);
    expect(find.text('Anil'), findsOneWidget);
    expect(find.text('₹26,000'), findsWidgets);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('stores and salaries in Telugu on a small phone', (tester) async {
    final (container, db, companyId, me) = await setUpCompany(tester);
    await tester.runAsync(() async {
      final yard = await db.warehouseDao.addStore(companyId: companyId, name: 'Main yard', by: me);
      await db.warehouseDao.addMove(
          companyId: companyId, kind: 'inward', materialName: 'Cement', unit: 'bags', quantity: 100, rate: 390,
          toStoreId: yard.id, by: me);
      await db.warehouseDao.addTool(companyId: companyId, name: 'Drill machine', value: 6500, by: me);
      await db.payrollDao.addStaff(companyId: companyId, name: 'Anil', basic: 12000, hra: 4000, otherAllowance: 2000);
      await db.payrollDao.makeMonth(companyId, '2026-11', by: me);
    });
    setCurrentLanguage(AppLanguage.te);
    await pumpApp(tester, container, WarehouseScreen(companyId: companyId, userId: me), size: const Size(320, 640));
    expect(find.text('స్టోర్లు మరియు పనిముట్లు'), findsOneWidget);
    expect(find.text('100 bags'), findsOneWidget);
    await tester.tap(find.text('పనిముట్లు').first);
    await settle(tester);
    expect(find.text('స్టోర్‌లో'), findsOneWidget);

    await pumpApp(tester, container, StaffSalariesScreen(companyId: companyId, userId: me, month: '2026-11'),
        size: const Size(320, 640));
    expect(find.text('నవంబర్ 2026'), findsOneWidget);
    expect(find.text('చెల్లించాల్సింది'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
