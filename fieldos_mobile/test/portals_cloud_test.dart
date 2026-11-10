/// The free supplier and client portals against the local Supabase stack
/// (skips itself when it is not running). The owner shares a code with a
/// supplier and with a site's client; the supplier answers a price request
/// and says the order is on its way, the client sees the site's updates,
/// bills and photos, and nobody sees what was not shared with them.
library;

import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  test('a supplier prices a request and sends the order; a client follows the site', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('portal-owner');
    final supplier = await CloudPhone.signUp('portal-supplier');
    final client = await CloudPhone.signUp('portal-client');
    final outsider = await CloudPhone.signUp('portal-outsider');
    addTearDown(() async {
      for (final p in [owner, supplier, client, outsider]) {
        await p.close();
      }
    });

    final company = await owner.db.companyDao.create('Sai Constructions');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final siteId = uuid.v4();
    final otherSiteId = uuid.v4();
    await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: siteId, companyId: company.id, name: 'Narapally', status: const Value('active')));
    await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: otherSiteId, companyId: company.id, name: 'Kompally', status: const Value('active')));
    final balaji = await owner.db.supplierDao.create(
        SuppliersCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Balaji Cements'));
    final lakshmi =
        await owner.db.supplierDao.create(SuppliersCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Lakshmi Traders'));
    final request = await owner.db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
        id: uuid.v4(), projectId: siteId, raisedBy: owner.localUserId, materialName: 'Cement OPC 53',
        unit: const Value('bag'), quantity: const Value(100)));
    await pushAll(owner);

    final ownerPortal = PortalService(owner.client);
    final supplierPortal = PortalService(supplier.client);
    final clientPortal = PortalService(client.client);
    final outsiderPortal = PortalService(outsider.client);

    // --- Codes: the owner's to give, the same code each time ----------------
    final code = await ownerPortal.supplierCode(balaji.id);
    expect(await ownerPortal.supplierCode(balaji.id), code);
    await expectLater(outsiderPortal.supplierCode(balaji.id), throwsA(isA<PostgrestException>()),
        reason: 'only the company\'s owner or PM can make a code');
    await expectLater(outsiderPortal.join('NOTACODE1'), throwsA(isA<PortalJoinError>()));

    // Asked before joining: counted as not in the app yet.
    expect(await ownerPortal.inviteSuppliers(request.id, [balaji.id, lakshmi.id]), 0);

    final link = await supplierPortal.join(code);
    expect(link.kind, PortalKind.supplier);
    expect(link.id, balaji.id);
    expect(link.companyName, 'Sai Constructions');
    expect(await ownerPortal.inviteSuppliers(request.id, [balaji.id, lakshmi.id]), 1);

    // --- The supplier sees the request and sends a price --------------------
    var mine = await supplierPortal.supplierPortal();
    expect(mine.companies, ['Sai Constructions']);
    expect(mine.requests, hasLength(1));
    final r = mine.requests.single;
    expect(r.item, 'Cement OPC 53');
    expect(r.site, 'Narapally');
    expect(r.open, isTrue);
    expect(r.quote, isNull);
    await supplierPortal.sendQuote(r, rate: 360, gstPct: 28, transport: 2500, deliveryDays: 2);
    await supplierPortal.sendQuote(r, rate: 355, gstPct: 28, transport: 2500, deliveryDays: 2); // a better rate
    mine = await supplierPortal.supplierPortal();
    expect(mine.requests.single.quote!.rate, 355);
    expect(mine.requests.single.quote!.status, 'received');

    // Nothing else of the company: not its tables, not another supplier's price request.
    expect(await supplier.client.from('projects').select('id'), isEmpty);
    expect(await supplier.client.from('purchase_orders').select('id'), isEmpty);
    expect(await supplier.client.from('site_supplier_quotes').select('id'), isEmpty);
    await expectLater(
        supplier.client.rpc('supplier_send_quote', params: {
          'p_request_id': request.id, 'p_vendor_id': lakshmi.id, 'p_rate': 1, 'p_gst_pct': 18,
          'p_transport': 0, 'p_delivery_days': null, 'p_payment_terms': null,
        }),
        throwsA(isA<PostgrestException>()),
        reason: 'a supplier prices only as themselves');

    // --- The owner's phone gets the price and gives the order ---------------
    await owner.engine.pullAll();
    final quotes = await owner.db.supplierQuoteDao.forRequest(request.id);
    expect(quotes, hasLength(1));
    expect(quotes.single.supplierId, balaji.id);
    expect(quotes.single.rate, 355);
    final po = await owner.db.supplierQuoteDao.award(quotes.single.id, by: owner.localUserId);
    await pushAll(owner);

    mine = await supplierPortal.supplierPortal();
    expect(mine.requests.single.quote!.status, 'accepted');
    expect(mine.requests.single.open, isFalse);
    final order = mine.orders.single;
    expect(order.id, po.id);
    expect(order.open, isTrue);
    await expectLater(supplierPortal.sendQuote(mine.requests.single, rate: 1, gstPct: 18), throwsA(isA<PostgrestException>()),
        reason: 'no new price once the order is given');

    await supplierPortal.dispatch(po.id, vehicle: 'TS09 AB 1234', note: 'Driver Ravi, after 3 pm');
    mine = await supplierPortal.supplierPortal();
    expect(mine.orders.single.status, 'acknowledged');
    expect(mine.orders.single.vehicle, 'TS09 AB 1234');
    await expectLater(outsiderPortal.dispatch(po.id, vehicle: 'X'), throwsA(isA<PostgrestException>()));

    await owner.engine.pullAll();
    final pulled = await (owner.db.select(owner.db.purchaseOrders)..where((o) => o.id.equals(po.id))).getSingle();
    expect(pulled.status, 'acknowledged');
    expect(pulled.dispatchVehicle, 'TS09 AB 1234');
    expect(pulled.supplierNote, 'Driver Ravi, after 3 pm');
    expect(pulled.dispatchedOn, isNotNull);

    // --- The client follows one site ----------------------------------------
    final admin = adminClient();
    final ownerId = owner.remoteUserId;
    final dpr = uuid.v4();
    await admin.from('dpr_entries').insert({
      'id': dpr, 'project_id': siteId, 'created_by': ownerId, 'entry_date': '2026-11-09',
      'work_summary': 'Slab shuttering on the first floor', 'manpower_count': 14, 'status': 'confirmed',
    });
    await admin.from('dpr_entries').insert({
      'project_id': siteId, 'created_by': ownerId, 'entry_date': '2026-11-10',
      'work_summary': 'Draft, not yet confirmed', 'status': 'draft',
    });
    final photoPath = '$siteId/dpr-photos/${uuid.v4()}.jpg';
    await admin.storage.from('documents').uploadBinary(photoPath, Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]));
    await admin.from('dpr_photos').insert({'dpr_entry_id': dpr, 'photo_path': photoPath});
    await admin.from('tasks').insert([
      {'project_id': siteId, 'title': 'Footings', 'status': 'done'},
      {'project_id': siteId, 'title': 'Slab', 'status': 'todo'},
    ]);
    await admin.from('site_client_bills').insert({
      'id': uuid.v4(), 'project_id': siteId, 'kind': 'ra', 'bill_number': 'RA-1', 'bill_date': '2026-11-01',
      'client_name': 'Mr Rao', 'lines': '[]', 'gross': 100000, 'net_payable': 118000, 'recorded_by': ownerId,
    });
    await admin.from('site_payments_received').insert({
      'id': uuid.v4(), 'project_id': siteId, 'amount': 50000, 'received_on': '2026-11-05T10:00:00Z',
      'from_party': 'Mr Rao', 'mode': 'upi', 'recorded_by': ownerId,
    });

    final clientCode = await ownerPortal.clientCode(siteId);
    final clientLink = await clientPortal.join(clientCode);
    expect(clientLink.kind, PortalKind.client);
    expect(clientLink.id, siteId);

    final sites = await clientPortal.clientPortal();
    expect(sites, hasLength(1), reason: 'only the shared site, not Kompally');
    final s = sites.single;
    expect(s.name, 'Narapally');
    expect(s.tasksTotal, 2);
    expect(s.tasksDone, 1);
    expect(s.updates, hasLength(1), reason: 'drafts stay with the builder');
    expect(s.updates.single.summary, 'Slab shuttering on the first floor');
    expect(s.updates.single.photos, [photoPath]);
    expect(s.billed, 118000);
    expect(s.paid, 50000);
    expect(s.balance, 68000);
    expect(await clientPortal.photoUrl(photoPath), contains('token='));

    // The client is not a company member and sees no company tables.
    expect(await client.client.from('projects').select('id'), isEmpty);
    expect(await client.client.from('site_expenses').select('id'), isEmpty);
    expect(await client.client.from('vendors').select('id'), isEmpty);
    expect((await clientPortal.supplierPortal()).requests, isEmpty);

    // Outsiders get nothing.
    expect(await outsiderPortal.clientPortal(), isEmpty);
    await expectLater(outsiderPortal.photoUrl(photoPath), throwsA(anything));
    await expectLater(supplierPortal.photoUrl(photoPath), throwsA(anything),
        reason: 'a supplier is not the site\'s client');
  });
}
