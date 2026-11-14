/// Bills in the non-Indian apps: one tax line named after the market's tax,
/// no GSTIN, IGST switch, TDS or UPI, and the market's bill names. India
/// keeps CGST + SGST / IGST.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/bills_view.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));
  const lines = [BillLine(description: 'Concrete slab', unit: 'CY', rate: 150, qty: 20)];

  test('India still splits GST', () {
    final t = billTotals(lines, gstRate: 18);
    expect((t.cgst, t.sgst, t.igst), (270.0, 270.0, 0.0));
    expect(taxLines(t, rate: 18, interState: false).map((l) => l.$1), ['CGST 9%', 'SGST 9%']);
    expect(taxLines(billTotals(lines, gstRate: 18, interState: true), rate: 18, interState: true).single.$1, 'IGST 18%');
    expect(billKinds['ra'], 'Running bill (RA)');
    expect(gstSplit(118, 18).cgst, 9);
  });

  test('US: one sales tax line, whatever the inter-state flag says', () {
    debugSetMarket(Market.us);
    final t = billTotals(lines, gstRate: 8.25, retentionPct: 5);
    expect((t.cgst, t.sgst), (0.0, 0.0));
    expect(t.igst, 247.5);
    expect(t.invoiceTotal, 3247.5);
    expect(t.retention, 150);
    expect(t.netPayable, 3097.5);
    expect(taxLines(t, rate: 8.25, interState: false), [('Sales tax 8.25%', 247.5)]);
    expect(taxLines(billTotals(lines, gstRate: 0), rate: 0, interState: false), isEmpty);
    expect(billKinds, {'ra': 'Pay application', 'tax_invoice': 'Invoice'});
    expect(gstSplit(108, 8).igst, 8);
    expect(gstSplit(108, 8).cgst, 0);
    final q = quoteTotals(lines, gstRate: 7);
    expect((q.cgst, q.sgst, q.igst), (0.0, 0.0, 210.0));
    expect(gstRates, [6, 7, 8.25]);
  });

  test('UK, UAE and Malaysia name their tax and bills', () {
    debugSetMarket(Market.uk);
    expect(taxLines(billTotals(lines, gstRate: 20), rate: 20, interState: false).single.$1, 'VAT 20%');
    expect(billKinds['ra'], 'Application for payment');
    expect(billKinds['tax_invoice'], 'VAT invoice');
    debugSetMarket(Market.uae);
    expect(taxLines(billTotals(lines, gstRate: 5), rate: 5, interState: false).single.$2, 150);
    expect(market.invoiceTitle, 'TAX INVOICE');
    debugSetMarket(Market.malaysia);
    expect(taxLines(billTotals(lines, gstRate: 8), rate: 8, interState: false).single.$1, 'SST 8%');
    expect(billKinds['ra'], 'Progress claim');
  });

  testWidgets('the US new-bill screen has sales tax and no Indian fields', (tester) async {
    debugSetMarket(Market.us);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late Project project;
    late String userId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'mike', name: 'Mike Torres', password: '123456');
      final companyId = (await session.createCompany('Torres Concrete LLC')).id;
      userId = container.read(sessionProvider).user!.id;
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: companyId, name: 'Elm St'));
      project = (await db.projectDao.byId('p1'))!;
    });
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: NewBillScreen(project: project, userId: userId, initialLines: lines),
      ),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
    expect(find.text('Pay application'), findsOneWidget);
    expect(find.text('Sales tax'), findsOneWidget);
    expect(find.text('Retainage %'), findsOneWidget);
    expect(find.textContaining('GST'), findsNothing);
    expect(find.textContaining('IGST'), findsNothing);
    expect(find.textContaining('TDS'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.textContaining('Lakh'), findsNothing);
    expect(find.text(r'$3,000'), findsWidgets);
    // Default is no sales tax; picking 8.25% adds one line.
    await tester.tap(find.text('8.25%'));
    await tester.pumpAndSettle();
    expect(find.text('Sales tax 8.25%'), findsOneWidget);
    expect(find.textContaining('Dollars'), findsOneWidget);
  });

  test('the bill PDF builds in every market', () async {
    for (final m in Market.values) {
      debugSetMarket(m);
      final bill = ClientBill(
        id: 'b1', projectId: 'p1', kind: 'tax_invoice', billNumber: 'INV-0001', billDate: DateTime(2026, 11, 14),
        clientName: 'Owner', clientGstin: null, sac: defaultSac, linesJson: encodeLines(lines),
        gstRate: market.tax.defaultRate, interState: !market.tax.splitsInsideState, retentionPct: 5, tdsPct: 0,
        gross: 3000, netPayable: 3000, notes: null, recordedBy: 'u', createdAt: DateTime(2026, 11, 14),
        status: 'draft',
      );
      final bytes = await buildBillPdf(
          bill: bill, companyName: 'Acme', project: Project(id: 'p1', companyId: 'c', name: 'Job', status: 'active', createdAt: DateTime(2026)),
          profile: const BillingProfile(gstin: 'X1'));
      expect(bytes.length, greaterThan(1000), reason: '$m');
    }
  });
}
