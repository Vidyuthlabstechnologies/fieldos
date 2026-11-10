/// Measurement to billing on two phones against the local Supabase stack
/// (skips itself when the stack is not running): the engineer measures,
/// the manager approves and bills, a part payment is put against the bill,
/// and a supplier invoice syncs. The server refuses an engineer's approval,
/// an allocation beyond the payment, and an edit to an invoice.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/billing_reconcile.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('measure, approve, bill, part-pay and match a supplier invoice across phones', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final pm = await CloudPhone.signUp('pm');
    final eng = await CloudPhone.signUp('eng');
    final company = await pm.db.companyDao.create('Sai Constructions');
    final cloud = await pm.service.registerCompany(companyId: company.id, name: company.name);
    final site = await pm.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final vendor = await pm.db.supplierDao.create(SuppliersCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Sri Balaji'));
    final po = await pm.db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
        id: uuid.v4(), projectId: site.id, supplierId: vendor.id, raisedBy: pm.localUserId, totalAmount: const Value(40000),
        status: const Value('issued')));
    expect((await pm.engine.pushPending()).failed, 0);
    await eng.service.joinCompany(cloud.joinCode!);
    await eng.engine.pullAll();

    // The engineer measures 40 cum of brickwork and records the cement
    // supplier's invoice; neither can be approved by them.
    final m = await eng.db.billingRecordsDao.measure(
        projectId: site.id, description: 'Brickwork CM 1:6', unit: 'cum', rate: 5200, qty: 40, on: DateTime.now(),
        by: eng.localUserId, location: 'Block A');
    await eng.db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
        id: uuid.v4(), projectId: site.id, poId: Value(po.id), supplierId: Value(vendor.id), materialName: 'Cement',
        quantity: 95, amount: 38000, receivedBy: eng.localUserId, receivedOn: DateTime.now()));
    final inv = await eng.db.billingRecordsDao.recordSupplierInvoice(SupplierInvoicesCompanion.insert(
        id: uuid.v4(), projectId: site.id, supplierId: vendor.id, poId: Value(po.id), invoiceNumber: 'SB/1182',
        invoiceDate: DateTime.now(), amount: 40000, qty: const Value(100), recordedBy: eng.localUserId));
    var push = await eng.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await eng.db.select(eng.db.syncOutbox).get()) e.lastError]}');
    await expectLater(
        eng.client.from('site_work_measurement_decisions').insert({
          'id': uuid.v4(), 'project_id': site.id, 'measurement_id': m.id, 'decision': 'approved', 'approved_qty': 40,
          'decided_by': eng.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        eng.client.from('site_supplier_invoices').update({'voided': true, 'void_reason': 'x'}).eq('id', inv.id).select(),
        completion(isEmpty), reason: 'only owners and PMs cancel invoices');

    // The manager's phone pulls, approves 38 of the 40, and bills it.
    await pm.engine.pullAll();
    final pmDao = pm.db.billingRecordsDao;
    expect((await pmDao.measurementsFor(site.id)).single.location, 'Block A');
    await pmDao.decide(m.id, approve: true, approvedQty: 38, by: pm.localUserId, note: '2 cum not to drawing');
    final draft = nextRaLines(
        approved: approvedToDate(await pmDao.measurementsFor(site.id), await pmDao.decisionsFor(site.id)), earlierBills: const []);
    expect(draft.lines.single.qty, 38);
    final totals = billTotals(draft.lines, retentionPct: 5);
    final bill = await pm.db.billDao.create(ClientBillsCompanion.insert(
        id: uuid.v4(), projectId: site.id, kind: 'ra', billNumber: 'RA-01', billDate: DateTime.now(), clientName: 'Client',
        linesJson: encodeLines(draft.lines), retentionPct: const Value(5), gross: totals.gross, netPayable: totals.netPayable,
        recordedBy: pm.localUserId));
    final pay = await pm.db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: uuid.v4(), projectId: site.id, amount: 150000, receivedOn: DateTime.now(), fromParty: 'Client', mode: 'bank',
        recordedBy: pm.localUserId));
    await pmDao.allocate(paymentId: pay.id, billId: bill.id, amount: 150000, by: pm.localUserId);
    push = await pm.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await pm.db.select(pm.db.syncOutbox).get()) e.lastError]}');

    // The server keeps the approved quantity in bounds and allocations
    // within the payment.
    final m2 = await eng.db.billingRecordsDao.measure(
        projectId: site.id, description: 'Plaster', unit: 'sqm', qty: 10, on: DateTime.now(), by: eng.localUserId);
    expect((await eng.engine.pushPending()).failed, 0);
    await expectLater(
        pm.client.from('site_work_measurement_decisions').insert({
          'id': uuid.v4(), 'project_id': site.id, 'measurement_id': m2.id, 'decision': 'approved', 'approved_qty': 11,
          'decided_by': pm.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        pm.client.from('site_bill_allocations').insert({
          'id': uuid.v4(), 'project_id': site.id, 'payment_id': pay.id, 'bill_id': bill.id, 'amount': 1,
          'created_by': pm.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()), reason: 'the payment is used up');
    await expectLater(
        pm.client.from('site_supplier_invoices').update({'amount': 38000, 'voided': false}).eq('id', inv.id).select(),
        throwsA(isA<PostgrestException>()), reason: 'an invoice is only ever cancelled');

    // Accounts' view on the manager's phone: the invoice asks for 2,000
    // more than what came.
    final check = checkSupplierInvoice((await pmDao.supplierInvoicesFor(site.id)).single,
        order: (await pm.db.purchaseDao.ordersFor(site.id)).single,
        receipts: await pm.db.materialDao.forProject(site.id),
        others: await pmDao.supplierInvoicesFor(site.id));
    expect(check.flags, containsAll([InvoiceFlag.overReceived, InvoiceFlag.qtyOverReceived]));
    expect(check.overBy, 2000);

    // A fresh manager phone gets the allocation and sees the bill part paid.
    final pm2 = await CloudPhone.signUp('pm2');
    await pm2.service.joinCompany(cloud.joinCode!);
    await adminClient().from('company_members').update({'role': 'project_manager'}).eq('user_id', pm2.remoteUserId);
    await pm2.engine.pullAll();
    final bal = billBalances(await pm2.db.billDao.forProject(site.id), await pm2.db.billingRecordsDao.allocationsFor(site.id)).single;
    expect(bal.paid, 150000);
    expect(bal.outstanding, closeTo(totals.netPayable - 150000, 0.01));
    expect((await pm2.db.billingRecordsDao.decisionsFor(site.id))[m.id]!.approvedQty, 38);

    await pm.close();
    await eng.close();
    await pm2.close();
  });
}
