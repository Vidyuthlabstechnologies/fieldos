import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/providers.dart';

/// The money book on screen: voucher numbers, a filter with its total,
/// GST worked out while typing, and cancelling a wrong entry.
void main() {
  Future<(ProviderContainer, AppDatabase, String)> setUp(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String userId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      final companyId = (await session.createCompany('Sri Sai Constructions')).id;
      userId = container.read(sessionProvider).user!.id;
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: companyId, name: 'Tower B'));
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: 'fuel', projectId: 'p1', category: 'Fuel', amount: 300, incurredOn: '2026-11-01', recordedBy: userId,
          note: const Value('JCB diesel')));
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: 'cement', projectId: 'p1', category: 'Material', amount: 1180, incurredOn: '2026-11-02',
          recordedBy: userId, paidTo: const Value('Balaji Hardware'), gstPct: const Value(18)));
    });
    return (container, db, userId);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, String userId) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: Scaffold(body: MoneyView(projectId: 'p1', userId: userId)),
      ),
    ));
    await settle(tester);
  }

  String totalText(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('money-filtered-total'))).data!;

  testWidgets('voucher numbers show, and a search shows its own total', (tester) async {
    final (container, _, userId) = await setUp(tester);
    await pump(tester, container, userId);

    expect(find.textContaining('V-1'), findsOneWidget);
    expect(find.textContaining('V-2 · '), findsOneWidget);
    expect(find.textContaining('GST 18%'), findsOneWidget);
    expect(find.text('Material · Balaji Hardware'), findsOneWidget);
    expect(totalText(tester), '2 entries · ₹1,480');

    await tester.enterText(find.byKey(const Key('money-search')), 'diesel');
    await tester.pumpAndSettle();
    expect(totalText(tester), '1 entry · ₹300');
    expect(find.text('Material · Balaji Hardware'), findsNothing);
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('money-search')), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches these filters.'), findsOneWidget);
    expect(find.text('Clear filters'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Clear filters'));
    await tester.pumpAndSettle();
    expect(totalText(tester), '2 entries · ₹1,480');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong entry is cancelled with a reason, stays struck through, and leaves the total', (tester) async {
    final (container, db, userId) = await setUp(tester);
    await pump(tester, container, userId);

    await tester.tap(find.textContaining('JCB diesel'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-voucher')), findsOneWidget);
    await tester.tap(find.byKey(const Key('expense-cancel')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cancel-reason')), 'entered twice');
    await tester.tap(find.text('Cancel entry'));
    await settle(tester);

    expect(totalText(tester), '1 entry · ₹1,180');
    final fuel = tester.widget<Text>(find.text('Fuel'));
    expect(fuel.style?.decoration, TextDecoration.lineThrough);
    expect(find.textContaining('Cancelled'), findsOneWidget);
    final row = await tester.runAsync(() => db.expenseDao.byId('fuel'));
    expect(row!.voided, isTrue);
    expect(row.voidReason, 'entered twice');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bill typed before GST gets GST added and split as CGST and SGST', (tester) async {
    final (container, db, userId) = await setUp(tester);
    await pump(tester, container, userId);

    await tester.tap(find.text('Add expense'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('expense-amount')), '1000');
    await tester.tap(find.byKey(const Key('gst-18')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amount includes GST'));
    await tester.pumpAndSettle();
    expect(find.text('₹1,180 = ₹1,000 + CGST ₹90 + SGST ₹90'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('expense-paid-to')), 'Sri Ram Steels');
    await tester.ensureVisible(find.byKey(const Key('expense-save')));
    await tester.tap(find.byKey(const Key('expense-save')));
    await settle(tester);

    final saved = (await tester.runAsync(() => db.expenseDao.allForProject('p1')))!
        .firstWhere((e) => e.paidTo == 'Sri Ram Steels');
    expect(saved.amount, 1180);
    expect(saved.gstPct, 18);
    expect(saved.voucherNo, 3);
    expect(saved.mode, 'cash');
    expect(totalText(tester), '3 entries · ₹2,660');
    expect(tester.takeException(), isNull);
  });
}
