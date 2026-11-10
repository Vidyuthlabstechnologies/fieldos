/// FOS-201 to FOS-204 as one flow, on one phone's database: a subcontractor
/// claims 120 m² against a 100 m² work order, the engineer certifies the
/// 100 m² in scope and sends 20 m² to the variation register, the variation
/// is approved, the 20 m² becomes certifiable, and the budget line and the
/// exceptions inbox follow each step without counting anything twice.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_data.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';

void main() {
  late AppDatabase db;
  late Project site;
  late CommercialDao dao;
  late Subcontractor painter;
  late CostCode plaster;
  const engineer = 'engineer-1';
  const sub = 'sub-1';
  const pm = 'pm-1';

  setUp(() async {
    db = AppDatabase.memory();
    dao = db.commercialDao;
    final company = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(
        id: const Uuid().v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    painter = await db.subcontractorDao.create(SubcontractorsCompanion.insert(
        id: const Uuid().v4(), companyId: company.id, name: 'Ravi Plastering Works'));
    plaster = await dao.addCostCode(projectId: site.id, code: '04-PL', name: 'Internal plaster', originalBudget: 50000);
  });
  tearDown(() => db.close());

  Future<CommercialData> load() => loadCommercialData(db, site.id);

  test('the 120 m² claim against a 100 m² work order, end to end', () async {
    final wo = await dao.createWorkOrder(
        projectId: site.id,
        subcontractorId: painter.id,
        description: 'Internal plaster, Block A',
        unit: 'm²',
        qty: 100,
        rate: 450,
        costCodeId: plaster.id);

    // The order is committed against the budget line; nothing is spent yet.
    var d = await load();
    var line = d.costReport().lines.single;
    expect(line.workOrderCommitted, 45000);
    expect(line.actual, 0);
    expect(line.projectedFinal, 45000);

    // The subcontractor claims 120 m².
    final claim = await dao.submitClaim(workOrderId: wo.id, qty: 120, by: sub, location: 'Block A, floors 1-3');
    d = await load();
    var ex = commercialExceptions(d, now: DateTime.now());
    expect(ex.map((e) => e.kind), [ExceptionKind.aboveContract]);
    expect(suggestedSplit(d.position(wo), d.claim(claim)), (accept: 100.0, hold: 20.0));

    // The engineer can't accept 120: only 100 is on the order.
    await expectLater(
        dao.certify(claimId: claim.id, accepted: 120, rejected: 0, by: engineer), throwsA(isA<CertificationRefused>()));

    // Certifies 100 and sends the 20 to the variation register.
    final first = await dao.certify(
        claimId: claim.id, accepted: 100, rejected: 0, by: engineer, raiseVariation: true, note: 'Extra on the stair core');
    d = await load();
    final v = d.variations.single;
    expect(first.variationId, v.id);
    expect(v.origin, 'claim_over_order');
    expect(v.qty, 20);
    expect(v.estimatedCost, 9000);
    expect(v.sourceClaimId, claim.id);
    expect(variationState(v, d.decisionByVariation), VariationState.pending);
    var pos = d.position(wo);
    expect(pos.certifiedQty, 100);
    expect(pos.remainingQty, 0);
    expect(d.claim(claim).heldForVariation, isTrue);
    expect(d.claim(claim).open, 20);

    // Commitment became actual: 45,000 counted once.
    line = d.costReport().lines.single;
    expect(line.actual, 45000);
    expect(line.workOrderCommitted, 0);
    expect(line.projectedFinal, 45000);
    expect(line.pendingChanges, 9000);
    expect(line.projectedIfPendingApproved, 54000);

    // The same 100 can't be certified again, nor the held 20 before approval.
    await expectLater(
        dao.certify(claimId: claim.id, accepted: 20, rejected: 0, by: engineer), throwsA(isA<CertificationRefused>()));
    ex = commercialExceptions(d, now: DateTime.now());
    expect(ex.map((e) => e.kind), [ExceptionKind.beyondScope]);
    expect(ex.single.defaultOwnerRole, 'manager');

    // The project director approves the variation.
    await dao.decideVariation(variationId: v.id, approve: true, by: pm, note: 'Client asked for it on 3 Nov');
    await expectLater(dao.decideVariation(variationId: v.id, approve: false, by: pm), throwsA(isA<CertificationRefused>()));
    d = await load();
    pos = d.position(wo);
    expect(pos.baselineQty, 100, reason: 'the baseline stays for comparison');
    expect(pos.currentQty, 120);
    expect(pos.currentValue, 54000);
    expect(pos.remainingQty, 20);
    expect(d.claim(claim).eligibleAfterApproval, isTrue);
    line = d.costReport().lines.single;
    expect(line.originalBudget, 50000);
    expect(line.approvedChanges, 9000);
    expect(line.revisedBudget, 59000);
    expect(line.workOrderCommitted, 9000, reason: 'the approved 20 m² is committed, not yet spent');
    expect(line.projectedFinal, 54000);

    // The held 20 is certified against the approved variation.
    await dao.certify(claimId: claim.id, accepted: 20, rejected: 0, by: engineer, againstVariationId: v.id);
    d = await load();
    expect(d.claim(claim).settled, isTrue);
    expect(d.position(wo).certifiedValue, 54000);
    line = d.costReport().lines.single;
    expect(line.actual, 54000);
    expect(line.openCommitments, 0);
    expect(line.overrun, lessThan(0));
    expect(commercialExceptions(d, now: DateTime.now()), isEmpty);

    // Nothing more can be certified on the claim or the order.
    await expectLater(
        dao.certify(claimId: claim.id, accepted: 1, rejected: 0, by: engineer), throwsA(isA<CertificationRefused>()));
    final again = await dao.submitClaim(workOrderId: wo.id, qty: 5, by: sub);
    await expectLater(
        dao.certify(claimId: again.id, accepted: 5, rejected: 0, by: engineer), throwsA(isA<CertificationRefused>()));
    // But rejecting it is fine.
    await dao.certify(claimId: again.id, accepted: 0, rejected: 5, by: engineer, note: 'Already certified in C-1');

    // Every step is queued for the server, in order.
    final out = (await db.select(db.syncOutbox).get()).map((e) => e.targetTable).toList();
    expect(out, containsAllInOrder(
        ['work_orders', 'work_claims', 'variations', 'work_certifications', 'variation_decisions', 'work_certifications']));
  });

  test('a rejected variation leaves the held quantity to reject', () async {
    final wo = await dao.createWorkOrder(
        projectId: site.id, subcontractorId: painter.id, description: 'Plaster', unit: 'm²', qty: 100, rate: 450);
    final claim = await dao.submitClaim(workOrderId: wo.id, qty: 120, by: sub);
    await dao.certify(claimId: claim.id, accepted: 100, rejected: 0, by: engineer, raiseVariation: true);
    final v = (await dao.variationsFor(site.id)).single;
    await dao.decideVariation(variationId: v.id, approve: false, by: pm, note: 'In the original scope');
    var d = await load();
    expect(d.position(wo).currentQty, 100);
    expect(d.claim(claim).open, 20);
    await expectLater(
        dao.certify(claimId: claim.id, accepted: 20, rejected: 0, by: engineer), throwsA(isA<CertificationRefused>()));
    await dao.certify(claimId: claim.id, accepted: 0, rejected: 20, by: engineer, note: 'Variation V-1 rejected');
    d = await load();
    expect(d.claim(claim).settled, isTrue);
  });

  test('purchase orders turn into actual cost as material arrives', () async {
    final vendor = await db.supplierDao.create(SuppliersCompanion.insert(
        id: const Uuid().v4(), companyId: site.companyId, name: 'Sri Balaji Traders'));
    final po = await db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
        id: const Uuid().v4(), projectId: site.id, supplierId: vendor.id, raisedBy: pm, totalAmount: const Value(40000)));
    await dao.setOrderCostCode(po.id, plaster.id);
    var line = (await load()).costReport().lines.single;
    expect((line.poCommitted, line.actual), (40000.0, 0.0));

    await db.purchaseDao.receiveAgainstOrder(
        po.id,
        closeOrder: false,
        MaterialReceiptsCompanion.insert(
            id: const Uuid().v4(), projectId: site.id, poId: Value(po.id), materialName: 'Cement', quantity: 50,
            amount: 19000, receivedBy: engineer, receivedOn: DateTime.now()));
    line = (await load()).costReport().lines.single;
    expect((line.poCommitted, line.actual, line.projectedFinal), (21000.0, 19000.0, 40000.0));

    // Closed short: nothing more is committed.
    await db.purchaseDao.setOrderStatus(po.id, 'delivered');
    line = (await load()).costReport().lines.single;
    expect((line.poCommitted, line.actual), (0.0, 19000.0));

    // A coded expense is actual cost; still to commit adds to the forecast.
    await dao.updateCostCode(plaster.id, uncommittedEstimate: 40000);
    line = (await load()).costReport().lines.single;
    expect(line.projectedFinal, 59000);
    final ex = commercialExceptions(await load(), now: DateTime.now());
    expect(ex.single.kind, ExceptionKind.forecastOverrun);
    expect(ex.single.amount, 9000);

    // The PM accepts the overrun: resolved while it stays the same size.
    await dao.actOnException(
        projectId: site.id, exceptionKey: ex.single.key, action: 'resolved', by: pm,
        note: 'Covered by contingency', fingerprint: ex.single.fingerprint);
    expect(commercialExceptions(await load(), now: DateTime.now()).single.isResolved, isTrue);
    await dao.updateCostCode(plaster.id, uncommittedEstimate: 60000);
    expect(commercialExceptions(await load(), now: DateTime.now()).single.isResolved, isFalse,
        reason: 'a bigger overrun comes back');
  });

  test('an unanswered claim becomes overdue for certification', () async {
    final wo = await dao.createWorkOrder(
        projectId: site.id, subcontractorId: painter.id, description: 'Plaster', unit: 'm²', qty: 100, rate: 450);
    await dao.submitClaim(
        workOrderId: wo.id, qty: 40, by: sub, now: DateTime.now().subtract(const Duration(days: certificationDays + 1)));
    final ex = commercialExceptions(await load(), now: DateTime.now());
    expect(ex.single.kind, ExceptionKind.overdueCertification);
    expect(ex.single.isOverdue(DateTime.now()), isTrue);
    await dao.actOnException(
        projectId: site.id, exceptionKey: ex.single.key, action: 'assigned', by: pm, ownerId: engineer, dueOn: '2099-01-01');
    final after = commercialExceptions(await load(), now: DateTime.now()).single;
    expect(after.ownerId, engineer);
    expect(after.isOverdue(DateTime.now()), isFalse);
  });

  test('upgrading from v15 adds the commercial tables and columns', () async {
    // Fresh in-memory databases are created at v16; the step itself runs
    // in schema_v16_upgrade_test.dart.
    final cols = await db.customSelect('PRAGMA table_info(work_orders)').get();
    expect(cols.map((r) => r.read<String>('name')), containsAll(['unit', 'contract_qty', 'rate', 'cost_code_id']));
  });
}
