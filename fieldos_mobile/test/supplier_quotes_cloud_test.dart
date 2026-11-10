/// Supplier quotes against the local Supabase stack (skips itself when it is
/// not running). The site engineer enters two suppliers' prices for a
/// request; the owner's phone sees them, gives the order, and the server
/// keeps the decision: the engineer cannot accept a quote, change a decided
/// one or accept a second.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  test('an engineer enters quotes, the owner gives the order, the server keeps it', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('rfq-owner');
    final engineer = await CloudPhone.signUp('rfq-engineer');
    addTearDown(() async {
      for (final p in [owner, engineer]) {
        await p.close();
      }
    });

    final company = await owner.db.companyDao.create('Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    await engineer.service.joinCompany(cloud.joinCode!);

    final siteId = uuid.v4();
    await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: siteId, companyId: company.id, name: 'Narapally', status: const Value('active')));
    final balaji = await owner.db.supplierDao.create(
        SuppliersCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Balaji Cements', contactPhone: const Value('9876543210')));
    final lakshmi =
        await owner.db.supplierDao.create(SuppliersCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Lakshmi Traders'));
    final request = await owner.db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
        id: uuid.v4(), projectId: siteId, raisedBy: owner.localUserId, materialName: 'Cement OPC 53',
        unit: const Value('bag'), quantity: const Value(100)));
    await pushAll(owner);

    // --- The engineer's phone takes the prices ------------------------------
    await engineer.engine.pullAll();
    final eq = engineer.db.supplierQuoteDao;
    final a = await eq.addQuote(
        requestId: request.id, supplierId: balaji.id, rate: 360, transport: 3000, deliveryDays: 2, by: engineer.localUserId);
    final b = await eq.addQuote(requestId: request.id, supplierId: lakshmi.id, rate: 370, deliveryDays: 5, by: engineer.localUserId);
    // Balaji calls back with a better rate before anything is decided.
    await eq.addQuote(
        requestId: request.id, supplierId: balaji.id, rate: 355, transport: 3000, deliveryDays: 2, by: engineer.localUserId);
    await pushAll(engineer);
    final rowA = await adminClient().from('site_supplier_quotes').select('created_by, rate, status').eq('id', a.id).single();
    expect(rowA['created_by'], engineer.remoteUserId);
    expect((rowA['rate'] as num).toDouble(), 355);

    // Not theirs to decide.
    await expectLater(
        engineer.client.from('site_supplier_quotes').update({'status': 'accepted'}).eq('id', b.id).select(),
        throwsA(isA<PostgrestException>()),
        reason: 'an engineer cannot accept a quote, even their own');
    await expectLater(
        engineer.client.from('site_supplier_quotes').insert({
          'id': uuid.v4(), 'project_id': siteId, 'request_id': request.id, 'vendor_id': lakshmi.id,
          'rate': 1, 'status': 'accepted',
        }).select('status').single().then((r) => r['status']),
        completion('received'),
        reason: 'an engineer\'s new quote is always just received');

    // --- The owner's phone gives the order ----------------------------------
    await owner.engine.pullAll();
    final oq = owner.db.supplierQuoteDao;
    expect(await oq.forRequest(request.id), hasLength(3));
    final po = await oq.award(b.id, by: owner.localUserId);
    await pushAll(owner);

    final rows = {
      for (final r in await adminClient().from('site_supplier_quotes').select('id, status, po_id').eq('request_id', request.id))
        r['id']: r
    };
    expect(rows[b.id]!['status'], 'accepted');
    expect(rows[b.id]!['po_id'], po.id);
    expect(rows[a.id]!['status'], 'rejected');
    final poRow = await adminClient().from('purchase_orders').select('total_amount, vendor_id').eq('id', po.id).single();
    expect((poRow['total_amount'] as num).toDouble(), closeTo(43660, 0.01));
    expect(poRow['vendor_id'], lakshmi.id);

    // A decided quote stays decided, and a request has one accepted quote.
    final changed =
        await engineer.client.from('site_supplier_quotes').update({'rate': 1}).eq('id', b.id).select();
    expect(changed, isEmpty);
    await expectLater(
        owner.client.from('site_supplier_quotes').update({'status': 'accepted'}).eq('id', a.id).select(),
        throwsA(isA<PostgrestException>()));

    // The engineer's phone gets the decision.
    await engineer.engine.pullAll();
    final seen = {for (final q in await eq.forRequest(request.id)) q.id: q.status};
    expect(seen[b.id], 'accepted');
    expect(seen[a.id], 'rejected');
  });
}
