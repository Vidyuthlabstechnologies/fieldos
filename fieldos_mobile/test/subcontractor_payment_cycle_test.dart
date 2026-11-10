/// The release's acceptance test, on three phones against the local
/// Supabase stack (skips itself when the stack is not running): one
/// subcontractor payment cycle with a disputed quantity.
///
/// The builder gives Ravi Plastering a 100 m² work order at ₹450/m². Ravi,
/// on his own phone with restricted access, claims 120 m² with a photo.
/// The site engineer certifies the 100 m² in scope and sends 20 m² to the
/// variation register. The project manager approves it, which raises the
/// order to 120 m² and the budget line with it, and the engineer certifies
/// the 20 m². Ravi sees the outcome of his claim and nothing else of the
/// site. At every step the server refuses what the phone would refuse:
/// certifying the same quantity twice, going past the order, an engineer
/// deciding a variation, a subcontractor certifying their own work, or
/// rewriting a decision.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_data.dart';
import 'package:fieldos_mobile/features/commercial/commercial_pack.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  test('120 m² claimed on a 100 m² order: certified, varied, approved, certified, traced', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final pm = await CloudPhone.signUp('pm');
    final engineer = await CloudPhone.signUp('engineer');
    final ravi = await CloudPhone.signUp('subcontractor');

    // --- The office sets up the order --------------------------------------
    final company = await pm.db.companyDao.create('Sai Constructions');
    final cloud = await pm.service.registerCompany(companyId: company.id, name: company.name);
    final site = await pm.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', clientName: const Value('Mr. Rao'),
        status: const Value('active')));
    final firm = await pm.db.subcontractorDao.create(SubcontractorsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Ravi Plastering Works'));
    final other = await pm.db.subcontractorDao.create(SubcontractorsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Another Painter'));
    final code = await pm.db.commercialDao
        .addCostCode(projectId: site.id, code: '04-PL', name: 'Internal plaster', originalBudget: 50000);
    final wo = await pm.db.commercialDao.createWorkOrder(
        projectId: site.id, subcontractorId: firm.id, description: 'Internal plaster, Block A', unit: 'm²',
        qty: 100, rate: 450, costCodeId: code.id);
    final otherWo = await pm.db.commercialDao.createWorkOrder(
        projectId: site.id, subcontractorId: other.id, description: 'Exterior paint', unit: 'm²', qty: 300, rate: 120);
    await pm.db.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: site.id, category: 'misc', amount: 1200, incurredOn: '2026-11-09',
        recordedBy: pm.localUserId));
    await pushAll(pm);

    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();

    // --- Ravi joins with restricted access ----------------------------------
    final access = await pm.service.subcontractorAccessCode(firm.id);
    await expectLater(engineer.service.subcontractorAccessCode(firm.id), throwsA(isA<PostgrestException>()),
        reason: 'only the owner or a PM hands out subcontractor codes');
    final link = await ravi.service.joinAsSubcontractor(access);
    expect((link.subcontractorId, link.companyName), (firm.id, 'Sai Constructions'));
    await ravi.engine.pullAll();
    final r = ravi.db;
    expect((await r.projectDao.byId(site.id))?.name, 'Kompally Villas');
    expect((await r.projectDao.byId(site.id))?.clientName, isNull, reason: 'site name only, no client details');
    expect((await r.commercialDao.workOrdersFor(site.id)).map((w) => w.id), [wo.id],
        reason: 'his own order only, not the other painter\'s');
    expect(await r.commercialDao.costCodesFor(site.id), isEmpty);
    expect(await r.select(r.siteExpenses).get(), isEmpty);
    expect(await ravi.client.from('projects').select('id'), isEmpty);
    expect(await ravi.client.from('work_orders').select('id').eq('id', otherWo.id), isEmpty);

    // --- Ravi claims 120 m² with a photo, on his phone -----------------------
    final photo = File('${ravi.filesDir.path}/plaster.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 160, height: 120)..clear(img.ColorRgb8(200, 190, 180))));
    final claim = await r.commercialDao.submitClaim(
        workOrderId: wo.id, qty: 120, by: ravi.localUserId, location: 'Block A, floors 1-3', photos: [photo.path]);
    await pushAll(ravi);
    // He can't certify his own work, or claim against someone else's order.
    await expectLater(
        ravi.client.from('work_certifications').insert({
          'id': uuid.v4(), 'project_id': site.id, 'work_order_id': wo.id, 'claim_id': claim.id,
          'accepted_qty': 120, 'certified_by': ravi.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        ravi.client.from('work_claims').insert({
          'id': uuid.v4(), 'project_id': site.id, 'work_order_id': otherWo.id, 'qty': 10,
          'submitted_by': ravi.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));

    // --- The engineer certifies the 100 m² in scope --------------------------
    await engineer.engine.pullAll();
    final e = engineer.db;
    var d = await loadCommercialData(e, site.id);
    expect(commercialExceptions(d, now: DateTime.now()).map((x) => x.kind), [ExceptionKind.aboveContract]);
    expect(d.photosOf(claim.id), hasLength(1), reason: 'Ravi\'s photo is on the engineer\'s phone');
    final split = suggestedSplit(d.position(d.orderById(wo.id)!), d.claim(d.claimById(claim.id)!));
    expect(split, (accept: 100.0, hold: 20.0));
    final first = await e.commercialDao.certify(
        claimId: claim.id, accepted: split.accept, rejected: 0, by: engineer.localUserId, raiseVariation: true,
        note: 'Stair core walls are not in the order');
    await pushAll(engineer);
    final variationId = first.variationId!;

    // A second, stale phone can't take the same 100 m² again: the server
    // checks the claim and the order, whatever the phone thought.
    await expectLater(
        engineer.client.from('work_certifications').insert({
          'id': uuid.v4(), 'project_id': site.id, 'work_order_id': wo.id, 'claim_id': claim.id,
          'accepted_qty': 20, 'certified_by': engineer.remoteUserId,
        }),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('beyond its agreed quantity'))));
    final second = await engineer.client.from('work_claims').insert({
      'id': uuid.v4(), 'project_id': site.id, 'work_order_id': wo.id, 'qty': 50, 'submitted_by': engineer.remoteUserId,
    }).select().single();
    await expectLater(
        engineer.client.from('work_certifications').insert({
          'id': uuid.v4(), 'project_id': site.id, 'work_order_id': wo.id, 'claim_id': second['id'],
          'accepted_qty': 50, 'certified_by': engineer.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));
    // And the engineer can't decide the variation.
    await expectLater(
        engineer.client.from('variation_decisions').insert({
          'id': uuid.v4(), 'variation_id': variationId, 'project_id': site.id, 'decision': 'approved',
          'approved_qty': 20, 'approved_cost': 9000, 'decided_by': engineer.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));

    // --- The project manager sees the impact and approves --------------------
    await pm.engine.pullAll();
    d = await loadCommercialData(pm.db, site.id);
    var line = d.costReport().lines.firstWhere((l) => l.costCode?.id == code.id);
    expect((line.actual, line.workOrderCommitted, line.pendingChanges), (45000.0, 0.0, 9000.0));
    final queue = commercialExceptions(d, now: DateTime.now());
    // The variation waits for a decision, and the stray 50 m² claim is
    // flagged as above the order.
    expect({for (final x in queue) x.kind: x.sourceId},
        {ExceptionKind.beyondScope: variationId, ExceptionKind.aboveContract: second['id']});
    // Changing the agreed baseline after certification is refused.
    await expectLater(
        pm.client.from('work_orders').update({'contract_qty': 120}).eq('id', wo.id).select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('record a variation'))));
    await pm.db.commercialDao.decideVariation(
        variationId: variationId, approve: true, by: pm.localUserId, note: 'Client asked for the stair core');
    await pushAll(pm);
    final decision = await pm.client.from('variation_decisions').select().eq('variation_id', variationId).single();
    await expectLater(
        pm.client.from('variation_decisions').update({'decision': 'rejected'}).eq('id', decision['id']).select(),
        throwsA(isA<PostgrestException>()));

    // --- The 20 m² is now certifiable ----------------------------------------
    await engineer.engine.pullAll();
    d = await loadCommercialData(e, site.id);
    expect(d.claim(d.claimById(claim.id)!).eligibleAfterApproval, isTrue);
    expect(d.position(d.orderById(wo.id)!).remainingQty, 20);
    await e.commercialDao.certify(
        claimId: claim.id, accepted: 20, rejected: 0, by: engineer.localUserId, againstVariationId: variationId);
    await pushAll(engineer);

    // --- Everyone sees the same decision -------------------------------------
    await pm.engine.pullAll();
    await ravi.engine.pullAll();
    for (final phone in [pm, engineer]) {
      final x = await loadCommercialData(phone.db, site.id);
      final pos = x.position(x.orderById(wo.id)!);
      expect((pos.baselineQty, pos.currentQty, pos.certifiedQty, pos.certifiedValue), (100.0, 120.0, 120.0, 54000.0));
      line = x.costReport().lines.firstWhere((l) => l.costCode?.id == code.id);
      expect((line.revisedBudget, line.actual, line.openCommitments), (59000.0, 54000.0, 0.0));
    }
    final rd = await loadCommercialData(r, site.id);
    final mine = rd.claim(rd.claimById(claim.id)!);
    expect((mine.accepted, mine.rejected, mine.settled), (120.0, 0.0, true));
    expect(rd.variations, isEmpty, reason: 'the variation register stays with the builder');

    // --- Accounts traces the payment back to the agreement and the photo ----
    d = await loadCommercialData(pm.db, site.id);
    final trace = traceClaim(d, d.claimById(claim.id)!);
    expect(trace.map((s) => s.kind), [
      TraceKind.agreed,
      TraceKind.claimed,
      TraceKind.certified,
      TraceKind.variationRaised,
      TraceKind.variationDecided,
      TraceKind.certified,
    ]);
    expect(trace[1].photos, 1);
    final csv = workOrderStatementCsv(d, d.orderById(wo.id)!);
    expect(csv, contains('C-1'));
    expect(csv, contains('C-2'));
    expect(csv, contains('54000.00'));
    final pdf = await buildWorkOrderStatement(
        data: d, order: d.orderById(wo.id)!, companyName: company.name, siteName: site.name, names: const {});
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');

    await pm.close();
    await engineer.close();
    await ravi.close();
  });
}
