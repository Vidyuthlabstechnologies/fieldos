/// Measurement to billing and reconciliation: approved measurements to the
/// next RA bill, payments spread over bills, retention released, and a
/// supplier's invoice checked against its PO and GRNs.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/billing_reconcile.dart';

late AppDatabase db;
late Project site;

Future<ClientBill> _bill(String id, List<BillLine> lines, {DateTime? on, double retention = 5}) {
  final t = billTotals(lines, retentionPct: retention);
  return db.billDao.create(ClientBillsCompanion.insert(
      id: id, projectId: site.id, kind: 'ra', billNumber: id, billDate: on ?? DateTime(2026, 10, 1), clientName: 'Client',
      linesJson: encodeLines(lines), retentionPct: Value(retention), gross: t.gross, netPayable: t.netPayable, recordedBy: 'pm'));
}

Future<PaymentsReceivedData> _payment(String id, double amount, {DateTime? on}) => db.paymentDao.create(PaymentsReceivedCompanion.insert(
    id: id, projectId: site.id, amount: amount, receivedOn: on ?? DateTime(2026, 10, 20), fromParty: 'Client', mode: 'bank',
    recordedBy: 'pm'));

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas'));
  });
  tearDown(() => db.close());

  group('measurement book to RA bill', () {
    test('only approved quantity counts, part approvals and corrections included, less what was billed', () async {
      final dao = db.billingRecordsDao;
      final m1 = await dao.measure(
          projectId: site.id, description: 'Brickwork CM 1:6', unit: 'cum', rate: 5200, qty: 40, on: DateTime(2026, 10, 5), by: 'eng');
      final m2 = await dao.measure(
          projectId: site.id, description: 'Brickwork CM 1:6', unit: 'cum', rate: 5200, qty: 25, on: DateTime(2026, 10, 12), by: 'eng');
      final m3 = await dao.measure(
          projectId: site.id, description: 'Plastering 12mm', unit: 'sqm', qty: 300, on: DateTime(2026, 10, 12), by: 'eng');
      final m4 = await dao.measure(
          projectId: site.id, description: 'brickwork cm 1:6', unit: 'CUM', rate: 5200, qty: -2, on: DateTime(2026, 10, 13), by: 'eng');
      await dao.measure(projectId: site.id, description: 'Waiting work', unit: 'nos', rate: 10, qty: 5, on: DateTime(2026, 10, 13), by: 'eng');
      await dao.decide(m1.id, approve: true, by: 'pm');
      await dao.decide(m2.id, approve: true, approvedQty: 20, by: 'pm', note: '5 cum not to drawing');
      await dao.decide(m3.id, approve: false, by: 'pm');
      await dao.decide(m4.id, approve: true, by: 'pm');
      expect(() => dao.decide(m1.id, approve: true, by: 'pm'), throwsStateError);
      final m5 = await dao.measure(projectId: site.id, description: 'X', unit: 'nos', qty: 3, on: DateTime(2026, 10, 14), by: 'eng');
      expect(() => dao.decide(m5.id, approve: true, approvedQty: 4, by: 'pm'), throwsArgumentError);
      expect(() => dao.decide(m5.id, approve: true, approvedQty: -1, by: 'pm'), throwsArgumentError);

      final approved = approvedToDate(await dao.measurementsFor(site.id), await dao.decisionsFor(site.id));
      expect(approved.values.single.qty, 58, reason: '40 + 20 of 25 - 2');
      expect(approved.values.single.rate, 5200);
      expect(approvedToDate(await dao.measurementsFor(site.id), await dao.decisionsFor(site.id), upTo: DateTime(2026, 10, 10))
          .values.single.qty, 40);

      final ra1 = await _bill('RA-01', [const BillLine(description: 'Brickwork CM 1:6', unit: 'cum', rate: 5200, qty: 40)]);
      final draft = nextRaLines(approved: approved, earlierBills: [decodeLines(ra1.linesJson)], extras: const [
        ApprovedExtra(description: 'Extra parapet (VO-3)', unit: 'rmt', qty: 12, rate: 900),
      ]);
      expect(draft.lines.map((l) => (l.description, l.qty, l.rate)), [
        ('Brickwork CM 1:6', 18.0, 5200.0),
        ('Extra parapet (VO-3)', 12.0, 900.0),
      ]);
      // Once the extra is billed it doesn't come again.
      final again = nextRaLines(approved: approved, earlierBills: [decodeLines(ra1.linesJson), draft.lines], extras: const [
        ApprovedExtra(description: 'Extra parapet (VO-3)', unit: 'rmt', qty: 12, rate: 900),
      ]);
      expect(again.lines, isEmpty);

      final queued = (await db.syncOutboxDao.pending()).map((o) => o.targetTable).toList();
      expect(queued.where((t) => t == 'site_work_measurements'), hasLength(6));
      expect(queued.where((t) => t == 'site_work_measurement_decisions'), hasLength(4));
    });

    test('an item without a rate takes the BOQ rate, or is held back until it has one', () async {
      final dao = db.billingRecordsDao;
      final a = await dao.measure(projectId: site.id, costHeadId: 'ch-1', description: 'PCC', unit: 'cum', qty: 10,
          on: DateTime(2026, 10, 5), by: 'eng');
      final b = await dao.measure(projectId: site.id, description: 'Loose item', unit: 'nos', qty: 2, on: DateTime(2026, 10, 5), by: 'eng');
      await dao.decide(a.id, approve: true, by: 'pm');
      await dao.decide(b.id, approve: true, by: 'pm');
      final approved = approvedToDate(await dao.measurementsFor(site.id), await dao.decisionsFor(site.id), boqRates: {'ch-1': 4100});
      final draft = nextRaLines(approved: approved, earlierBills: const []);
      expect(draft.lines.single.rate, 4100);
      expect(draft.noRate, ['Loose item']);
    });
  });

  group('payments against bills and retention', () {
    test('a part payment spreads over the oldest bills; the bill is marked paid when covered', () async {
      final ra1 = await _bill('RA-01', [const BillLine(description: 'Work', unit: 'cum', rate: 1000, qty: 100)]);
      final ra2 = await _bill('RA-02', [const BillLine(description: 'Work', unit: 'cum', rate: 1000, qty: 50)], on: DateTime(2026, 10, 15));
      // 100,000 + 18% GST - 5% retention = 113,000; RA-02 is 56,500.
      expect(ra1.netPayable, 113000);
      final p = await _payment('pay-1', 150000);
      final dao = db.billingRecordsDao;
      final plan = planAllocation(150000, billBalances([ra2, ra1], await dao.allocationsFor(site.id)));
      expect(plan, [('RA-01', 113000.0), ('RA-02', 37000.0)]);
      for (final (bill, amount) in plan) {
        await dao.allocate(paymentId: p.id, billId: bill, amount: amount, by: 'pm');
      }
      final bills = await db.billDao.forProject(site.id);
      final bal = {for (final b in billBalances(bills, await dao.allocationsFor(site.id))) b.bill.id: b};
      expect(bal['RA-01']!.settled, isTrue);
      expect(bills.firstWhere((b) => b.id == 'RA-01').status, 'paid');
      expect(bal['RA-02']!.outstanding, 19500);
      expect(bills.firstWhere((b) => b.id == 'RA-02').status, 'issued');
      expect(unallocated([p], await dao.allocationsFor(site.id))['pay-1'], 0);

      // Nothing left on the payment, and never more than a bill needs.
      expect(() => dao.allocate(paymentId: p.id, billId: 'RA-02', amount: 1, by: 'pm'), throwsA(isA<AllocationTooBig>()));
      final p2 = await _payment('pay-2', 50000);
      expect(() => dao.allocate(paymentId: p2.id, billId: 'RA-02', amount: 20000, by: 'pm'), throwsA(isA<AllocationTooBig>()));

      // Undoing an allocation makes the bill due again.
      final first = (await dao.allocationsFor(site.id)).firstWhere((a) => a.billId == 'RA-01');
      await dao.removeAllocation(first.id);
      expect((await db.billDao.forProject(site.id)).firstWhere((b) => b.id == 'RA-01').status, 'issued');
    });

    test('retention is released against a payment, no more than was kept', () async {
      final ra1 = await _bill('RA-01', [const BillLine(description: 'Work', unit: 'cum', rate: 1000, qty: 100)]);
      final p = await _payment('pay-r', 8000);
      final dao = db.billingRecordsDao;
      expect(billBalances([ra1], const []).single.retentionKept, 5000);
      expect(() => dao.allocate(paymentId: p.id, billId: ra1.id, kind: 'retention', amount: 6000, by: 'pm'),
          throwsA(isA<AllocationTooBig>()));
      await dao.allocate(paymentId: p.id, billId: ra1.id, kind: 'retention', amount: 5000, by: 'pm');
      final b = billBalances([ra1], await dao.allocationsFor(site.id)).single;
      expect(b.retentionHeld, 0);
      expect(b.outstanding, 113000, reason: 'retention money does not pay the bill');
    });
  });

  group('supplier invoice against PO and GRN', () {
    late PurchaseOrder po;
    setUp(() async {
      final s = await db.supplierDao.create(SuppliersCompanion.insert(id: 'sup', companyId: site.companyId, name: 'Sri Balaji'));
      po = await db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
          id: 'po-1', projectId: site.id, supplierId: s.id, raisedBy: 'pm', totalAmount: const Value(40000), status: const Value('issued')));
      await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
          id: 'grn-1', projectId: site.id, poId: Value(po.id), supplierId: const Value('sup'), materialName: 'Cement', quantity: 95,
          amount: 38000, receivedBy: 'sup', receivedOn: DateTime(2026, 11, 4)));
    });

    Future<SupplierInvoice> invoice(String no, double amount, {String? poId = 'po-1', double? qty, DateTime? on}) =>
        db.billingRecordsDao.recordSupplierInvoice(SupplierInvoicesCompanion.insert(id: 'si-$no-$amount',
            projectId: site.id, supplierId: 'sup', poId: Value(poId), invoiceNumber: no,
            invoiceDate: on ?? DateTime(2026, 11, 5), amount: amount, qty: Value(qty), recordedBy: 'acc'));

    Future<InvoiceCheck> check(SupplierInvoice i) async => checkSupplierInvoice(i,
        order: i.poId == null ? null : po,
        receipts: await db.materialDao.forProject(site.id),
        others: await db.billingRecordsDao.supplierInvoicesFor(site.id));

    test('an invoice for what came matches', () async {
      expect((await check(await invoice('INV-1', 38000, qty: 95))).matched, isTrue);
    });

    test('billing the full 100 bags when 95 came is flagged, with the difference', () async {
      final c = await check(await invoice('INV-1', 40000, qty: 100));
      expect(c.flags, containsAll([InvoiceFlag.overReceived, InvoiceFlag.qtyOverReceived]));
      expect(c.flags, isNot(contains(InvoiceFlag.overOrder)));
      expect(c.overBy, 2000);
    });

    test('a second invoice on the same PO counts the first; duplicates and invoices without a PO are flagged', () async {
      await invoice('INV-1', 30000, on: DateTime(2026, 11, 5));
      final second = await check(await invoice('INV-2', 12000, on: DateTime(2026, 11, 6)));
      expect(second.invoicedBefore, 30000);
      expect(second.flags, containsAll([InvoiceFlag.overReceived, InvoiceFlag.overOrder]));
      final dup = await check(await invoice('inv-1 ', 100, on: DateTime(2026, 11, 7)));
      expect(dup.flags, contains(InvoiceFlag.duplicate));
      final loose = await check(await invoice('INV-9', 500, poId: null));
      expect(loose.flags, containsAll([InvoiceFlag.noPo, InvoiceFlag.nothingReceived]));

      // A cancelled invoice no longer counts, and stays on record.
      final first = (await db.billingRecordsDao.supplierInvoicesFor(site.id)).firstWhere((i) => i.invoiceNumber == 'INV-1');
      await db.billingRecordsDao.voidSupplierInvoice(first.id, 'Wrong supplier');
      final redo = await check((await db.billingRecordsDao.supplierInvoicesFor(site.id)).firstWhere((i) => i.invoiceNumber == 'INV-2'));
      expect(redo.invoicedBefore, 0);
      expect(redo.matched, isTrue);
      expect(() => db.billingRecordsDao.voidSupplierInvoice(first.id, ' '), throwsArgumentError);
    });
  });
}
