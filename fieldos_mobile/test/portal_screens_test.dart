/// The free supplier and client apps on a phone, with the server faked: a
/// supplier sends a price and says an order is on its way; a client sees
/// the site's progress, balance and updates; the builder asks suppliers
/// for a price from Compare quotes; Telugu on a 320 px phone fits.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/portals/portal_screens.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

SupabaseClient _offline() => SupabaseClient('http://localhost:1', 'anon',
    authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));

/// A cloud client that never starts its refresh timer.
final _offlineCloud = cloudSyncClientProvider.overrideWith((ref) {
  final c = _offline();
  ref.onDispose(c.dispose);
  return c;
});

class _FakePortal extends PortalService {
  _FakePortal() : super(_offline());
  final quotes = <(String, double, double, double, int?)>[];
  final dispatched = <(String, String?, String?)>[];

  @override
  Future<void> sendQuote(PriceRequest r,
      {required double rate, required double gstPct, double transport = 0, int? deliveryDays, String? paymentTerms}) async {
    quotes.add((r.id, rate, gstPct, transport, deliveryDays));
  }

  @override
  Future<void> dispatch(String orderId, {String? vehicle, String? note}) async => dispatched.add((orderId, vehicle, note));
}

final _supplierData = SupplierPortalData(companies: const ['Sai Constructions'], requests: [
  PriceRequest(
      id: 'r-1', vendorId: 'v-1', site: 'Narapally', companyName: 'Sai Constructions', item: 'Cement OPC 53',
      quantity: 100, unit: 'bag', open: true, askedOn: DateTime(2026, 11, 9)),
  const PriceRequest(
      id: 'r-2', vendorId: 'v-1', site: 'Narapally', companyName: 'Sai Constructions', item: 'River sand',
      quantity: 4, unit: 'load', open: false,
      quote: SupplierQuoteSent(rate: 9000, gstPct: 5, transport: 0, status: 'accepted')),
], orders: [
  SupplierOrder(
      id: 'po-1', site: 'Narapally', companyName: 'Sai Constructions', status: 'issued', poNumber: 'PO-0007',
      item: 'River sand', total: 37800, deliveryDate: DateTime(2026, 11, 12)),
]);

final _clientData = [
  ClientSite(
    id: 'p-1',
    name: 'Narapally villa',
    companyName: 'Sai Constructions',
    tasksTotal: 10,
    tasksDone: 4,
    updates: [
      SiteUpdate(id: 'd-1', date: DateTime(2026, 11, 9), summary: 'Slab shuttering on the first floor', manpower: 14),
    ],
    bills: [SiteBill(number: 'RA-1', date: DateTime(2026, 11, 1), amount: 118000, status: 'issued', kind: 'ra')],
    payments: [ClientPayment(date: DateTime(2026, 11, 5), amount: 50000, mode: 'upi')],
  ),
];

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<(ProviderContainer, _FakePortal)> pump(WidgetTester tester, Widget home,
      {Size size = const Size(412, 915), AppDatabase? db}) async {
    final fake = _FakePortal();
    final database = db ?? AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      _offlineCloud,
      portalServiceProvider.overrideWithValue(fake),
      supplierPortalProvider.overrideWith((ref) async => _supplierData),
      clientPortalProvider.overrideWith((ref) async => _clientData),
    ]);
    addTearDown(() async {
      container.dispose();
      fake.client.dispose();
      if (db == null) await database.close();
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await settle(tester);
    return (container, fake);
  }

  testWidgets('a supplier sends a price and says the order is on its way', (tester) async {
    final (_, fake) = await pump(tester, const SupplierHomeScreen());
    expect(find.text('Cement OPC 53'), findsOneWidget);
    expect(find.textContaining('You got the order'), findsOneWidget);
    expect(find.byKey(const Key('price-r-2')), findsNothing, reason: 'a decided request takes no new price');

    await tester.tap(find.byKey(const Key('price-r-1')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('quote-rate')), '355');
    await tester.enterText(find.byKey(const Key('quote-gst')), '28');
    await tester.enterText(find.byKey(const Key('quote-transport')), '2500');
    await tester.enterText(find.byKey(const Key('quote-days')), '2');
    await tester.tap(find.byKey(const Key('quote-send')));
    await settle(tester);
    expect(fake.quotes, [('r-1', 355.0, 28.0, 2500.0, 2)]);
    expect(find.text('Price sent. The site compares it with the others.'), findsOneWidget);

    await tester.tap(find.text('Orders'));
    await settle(tester);
    expect(find.text('PO-0007'), findsOneWidget);
    expect(find.text('New order'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dispatch-po-1')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('dispatch-vehicle')), 'TS09 AB 1234');
    await tester.enterText(find.byKey(const Key('dispatch-note')), 'Driver Ravi');
    await tester.tap(find.byKey(const Key('dispatch-save')));
    await settle(tester);
    expect(fake.dispatched, [('po-1', 'TS09 AB 1234', 'Driver Ravi')]);
  });

  testWidgets('a supplier cannot send a price without a rate', (tester) async {
    final (_, fake) = await pump(tester, const SupplierHomeScreen());
    await tester.tap(find.byKey(const Key('price-r-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('quote-send')));
    await settle(tester);
    expect(fake.quotes, isEmpty);
    expect(find.text('Enter the rate a unit.'), findsOneWidget);
  });

  testWidgets('a client sees the progress, the balance and the daily updates', (tester) async {
    await pump(tester, const ClientHomeScreen());
    expect(find.text('Narapally villa'), findsOneWidget);
    expect(find.text('4 of 10 jobs done'), findsOneWidget);
    expect(
        find.descendant(of: find.byKey(const Key('client-balance')), matching: find.textContaining('68,000')), findsOneWidget);
    expect(find.text('Slab shuttering on the first floor'), findsOneWidget);
    expect(find.text('14 people on site'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('RA-1 · 1 Nov'), 200);
    expect(find.text('To pay'), findsOneWidget);
  });

  testWidgets('the builder asks suppliers for a price in the app from Compare quotes', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    // Not signed in to Team & sync: the builder is told to turn it on first.
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db), _offlineCloud]);
    addTearDown(container.dispose);
    late String companyId, userId, requestId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      userId = container.read(sessionProvider).user!.id;
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p-1', companyId: companyId, name: 'Narapally', status: const Value('active')));
      await db.supplierDao.create(SuppliersCompanion.insert(id: 's-1', companyId: companyId, name: 'Balaji Cements'));
      requestId = (await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
              id: 'pr-1', projectId: 'p-1', raisedBy: userId, materialName: 'Cement OPC 53', unit: const Value('bag'))))
          .id;
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildFieldOsTheme(Brightness.light),
          home: QuoteCompareScreen(requestId: requestId, companyId: companyId, userId: userId)),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const Key('ask-in-app')));
    await settle(tester);
    expect(find.text('Balaji Cements'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ask-s-1')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ask-send')));
    await settle(tester);
    expect(find.text('Turn on Team & sync first.'), findsOneWidget);
  });

  testWidgets('Telugu on a 320 px phone fits the supplier screen', (tester) async {
    setCurrentLanguage(AppLanguage.te);
    await pump(tester, const SupplierHomeScreen(), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(Tab).last);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Telugu on a 320 px phone fits the client screen', (tester) async {
    setCurrentLanguage(AppLanguage.te);
    await pump(tester, const ClientHomeScreen(), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.text('Narapally villa'), findsOneWidget);
  });
}
