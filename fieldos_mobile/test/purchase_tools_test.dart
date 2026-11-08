import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/procurement_screen.dart';
import 'package:fieldos_mobile/features/procurement/purchase_screens.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:supabase/supabase.dart' show SupabaseClient, AuthClientOptions, AuthFlowType;

/// Receiving a PO always closed it and saved the goods as "Goods from PO",
/// so part deliveries, site stock and supplier dues were all wrong.
void main() {
  final now = DateTime(2026, 11, 12);

  PurchaseOrder po(String id, {String supplier = 's1', double? total, DateTime? due, String status = 'issued', String? req}) =>
      PurchaseOrder(
        id: id,
        projectId: 'p',
        supplierId: supplier,
        requestId: req,
        quoteId: null,
        raisedBy: 'u',
        poNumber: null,
        totalAmount: total,
        deliveryDate: due,
        status: status,
        notes: null,
        createdAt: DateTime(2026, 11, 1),
      );

  MaterialReceipt rc(String id, String name, double qty, double amount, DateTime on,
          {String? poId, String? supplier, String? unit = 'bags'}) =>
      MaterialReceipt(
        id: id,
        projectId: 'p',
        poId: poId,
        supplierId: supplier,
        costHeadId: null,
        materialName: name,
        quantity: qty,
        unit: unit,
        amount: amount,
        receivedBy: 'u',
        receivedOn: on,
        createdAt: on,
        notes: null,
      );

  final request = PurchaseRequest(
    id: 'r1',
    projectId: 'p',
    raisedBy: 'u',
    materialName: 'Cement',
    quantity: 100,
    unit: 'bags',
    estimatedAmount: null,
    urgency: 'normal',
    status: 'ordered',
    approvedBy: null,
    approvedAt: null,
    notes: null,
    createdAt: DateTime(2026, 11, 1),
  );

  test('part deliveries leave the rest to come', () {
    final o = po('o1', total: 40000, req: 'r1');
    final p = poProgress(o, request, [
      rc('a', 'Cement', 60, 24000, DateTime(2026, 11, 5), poId: 'o1'),
      rc('b', 'Cement', 10, 4000, DateTime(2026, 11, 6), poId: 'other'),
    ]);
    expect(p.received, 60);
    expect(p.pending, 40);
    expect(p.partlyReceived, isTrue);
    expect(p.amountReceived, 24000);
    expect(poProgress(o, null, const []).pending, isNull);
  });

  test('an open order past its date is late', () {
    expect(poIsLate(po('x', due: DateTime(2026, 11, 11)), now), isTrue);
    expect(poIsLate(po('x', due: DateTime(2026, 11, 12, 9)), now), isFalse, reason: 'due today');
    expect(poIsLate(po('x', due: DateTime(2026, 11, 1), status: 'delivered'), now), isFalse);
    expect(poIsLate(po('x'), now), isFalse);
  });

  test('supplier ledger', () {
    final l = supplierLedgers([
      po('o1', total: 40000, due: DateTime(2026, 11, 10)),
      po('o2', total: 10000, status: 'delivered'),
      po('o3', total: 99999, status: 'cancelled'),
      po('o4', supplier: 's2', total: 5000),
    ], [
      rc('a', 'Cement', 60, 24000, DateTime(2026, 11, 5), poId: 'o1'),
      rc('b', 'Sand', 1, 10000, DateTime(2026, 11, 7), supplier: 's1'),
    ], now);
    expect(l['s1']!.ordered, 50000);
    expect(l['s1']!.received, 34000);
    expect(l['s1']!.toCome, 16000);
    expect(l['s1']!.openOrders, 1);
    expect(l['s1']!.lateOrders, 1);
    expect(l['s1']!.lastDelivery, DateTime(2026, 11, 7));
    expect(l['s2']!.received, 0);
  });

  test('rates per material and unit, oldest first', () {
    final r = materialRates([
      rc('a', 'Cement', 50, 20000, DateTime(2026, 11, 1)),
      rc('b', 'cement ', 50, 21000, DateTime(2026, 11, 8)),
      rc('c', 'Cement', 2, 13000, DateTime(2026, 11, 3), unit: 't'),
      rc('d', 'Steel', 0, 5000, DateTime(2026, 11, 3)),
    ]);
    expect(r.map((x) => '${x.name}/${x.unit}'), ['Cement/bags', 'Cement/t']);
    expect(r.first.latest, 420);
    expect(r.first.previous, 400);
    expect(r.first.changePct, closeTo(5, 0.001));
    expect(r.first.lowest, 400);
    expect(r[1].changePct, isNull);
  });

  test('site units', () {
    SiteUnit u(String k) => unitGroups.expand((g) => g.units).firstWhere((x) => x.key == k);
    expect(convertUnits(1, u('brass'), u('cft')), closeTo(100, 1e-9));
    expect(convertUnits(1, u('t'), u('bag')), 20);
    expect(convertUnits(1, u('guntha'), u('sqft')), closeTo(1089, 0.01));
    expect(convertUnits(10, u('rft'), u('m')), closeTo(3.048, 1e-9));
    expect(steelKgPerMetre(12), closeTo(0.888, 0.001));
  });

  testWidgets('a part delivery keeps the PO open, with the right material', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // Not signed in to the cloud, and no token-refresh timer.
      cloudSyncClientProvider.overrideWith((ref) {
        final c = SupabaseClient('http://localhost:1', 'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
        ref.onDispose(c.dispose);
        return c;
      }),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p', companyId: 'c', name: 'Site'));
      await db.supplierDao.create(SuppliersCompanion.insert(id: 's1', companyId: 'c', name: 'Sri Balaji Traders'));
      await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
          id: 'r1', projectId: 'p', raisedBy: 'u', materialName: 'Cement', quantity: const Value(100), unit: const Value('bags')));
      await db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
          id: 'o1', projectId: 'p', supplierId: 's1', raisedBy: 'u', requestId: const Value('r1'), totalAmount: const Value(40000)));
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: const Scaffold(body: ProcurementView(projectId: 'p', companyId: 'c', userId: 'u')),
      ),
    ));
    await tester.tap(find.text('PO'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Cement 100 bags · ₹40,000'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Receive'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Cement'), findsOneWidget, reason: 'material comes from the request');
    await tester.enterText(find.widgetWithText(TextField, '100'), '60');
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Receive').last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();

    final orders = await tester.runAsync(() => db.purchaseDao.ordersFor('p'));
    expect(orders!.single.status, 'issued');
    final got = await tester.runAsync(() => db.materialDao.forProject('p'));
    expect(got!.single.materialName, 'Cement');
    expect(got.single.quantity, 60);
    expect(got.single.amount, 40000, reason: 'the bill amount was left as the PO total');
    expect(find.textContaining('60 of 100 received, 40 to come'), findsOneWidget);
  });

  testWidgets('unit converter', (tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const UnitConverterScreen()));
    expect(find.text('1 Running feet = 0.3048 Metre'), findsOneWidget);
    await tester.tap(find.text('Volume'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Value'), '2');
    await tester.pumpAndSettle();
    expect(find.text('2 Cubic feet = 0.05663 Cubic metre'), findsOneWidget);
    await tester.tap(find.byTooltip('Swap'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 Cubic metre = 70.629'), findsOneWidget);
    expect(find.text('0.88889 kg per metre'), findsOneWidget);
    expect(find.text('10.667 kg for 12 m'), findsOneWidget);
  });
}
