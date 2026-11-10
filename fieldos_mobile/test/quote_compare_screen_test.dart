/// Comparing supplier quotes on a phone: two quotes entered, the cheapest
/// landed one marked, the order given as a PO. Also Telugu on a 320 px
/// phone without overflow.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase, String, String, String)> setUpRequest(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String companyId, me, requestId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      me = container.read(sessionProvider).user!.id;
      await db.projectDao.create(ProjectsCompanion.insert(
          id: 'p-1', companyId: companyId, name: 'Narapally', status: const Value('active')));
      for (final (id, name) in [('s-a', 'Balaji Cements'), ('s-b', 'Lakshmi Traders')]) {
        await db.supplierDao.create(SuppliersCompanion.insert(
            id: id, companyId: companyId, name: name, contactPhone: const Value('9876543210')));
      }
      requestId = (await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
              id: 'r-1',
              projectId: 'p-1',
              raisedBy: me,
              materialName: 'Cement OPC 53',
              unit: const Value('bag'),
              quantity: const Value(100))))
          .id;
    });
    return (container, db, companyId, me, requestId);
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

  Future<void> addQuote(WidgetTester tester, String supplier, String rate, {String transport = ''}) async {
    await tester.tap(find.byKey(const Key('add-quote')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('quote-supplier')));
    await settle(tester);
    await tester.tap(find.text(supplier).last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('quote-rate')), rate);
    if (transport.isNotEmpty) await tester.enterText(find.byKey(const Key('quote-transport')), transport);
    await tester.pump();
    expect(find.textContaining('Landed at site'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quote-save')));
    await settle(tester);
  }

  testWidgets('two quotes, the cheapest landed one marked, the order given', (tester) async {
    final (container, db, companyId, me, requestId) = await setUpRequest(tester);
    await pumpApp(tester, container, QuoteCompareScreen(requestId: requestId, companyId: companyId, userId: me));
    expect(find.textContaining('No quotes yet'), findsOneWidget);
    expect(find.byKey(const Key('ask-suppliers')), findsOneWidget);

    // Lower rate, but transport makes it dearer at site.
    await addQuote(tester, 'Balaji Cements', '360', transport: '3000');
    await addQuote(tester, 'Lakshmi Traders', '370');

    expect(find.text('Cheapest'), findsOneWidget);
    expect(find.textContaining('Lakshmi Traders is cheapest'), findsOneWidget);
    final quotes = await tester.runAsync(() => db.supplierQuoteDao.forRequest(requestId));
    final lakshmi = quotes!.firstWhere((q) => q.supplierId == 's-b');

    await tester.ensureVisible(find.byKey(Key('award-${lakshmi.id}')));
    await tester.tap(find.byKey(Key('award-${lakshmi.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('award-confirm')));
    await settle(tester);

    expect(find.text('Ordered'), findsOneWidget);
    expect(find.text('Turned down'), findsOneWidget);
    expect(find.byKey(const Key('add-quote')), findsNothing);
    final orders = await tester.runAsync(() => db.purchaseDao.ordersFor('p-1'));
    expect(orders!.single.supplierId, 's-b');
    expect(orders.single.totalAmount, closeTo(43660, 0.001));
  });

  testWidgets('Telugu on a 320 px phone fits', (tester) async {
    final (container, db, companyId, me, requestId) = await setUpRequest(tester);
    await tester.runAsync(() async {
      await db.supplierQuoteDao.addQuote(
          requestId: requestId, supplierId: 's-a', rate: 360, transport: 3000, deliveryDays: 2, paymentTerms: '30 days credit', by: me);
      await db.supplierQuoteDao.addQuote(requestId: requestId, supplierId: 's-b', rate: 370, deliveryDays: 5, by: me);
    });
    setCurrentLanguage(AppLanguage.te);
    await pumpApp(tester, container, QuoteCompareScreen(requestId: requestId, companyId: companyId, userId: me),
        size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('add-quote')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('quote-rate')), '355');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
