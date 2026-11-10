/// The sales demo, end to end on two phones against the local Supabase stack
/// (skips itself when the stack is not running):
///
/// A supervisor receives cement with no signal, records the quantity and
/// photographs the delivery slip. When the phone reconnects, the project
/// manager sees the receipt against the PO, with the shortage flagged and
/// the slip on their own phone, approves the accepted quantity and closes
/// the week. Accounts gets a pack it can use. The supervisor cannot approve
/// it themselves, and nobody can rewrite the approval afterwards.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/close/week_close_pack.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('cement arrives offline, the manager approves the accepted quantity, accounts gets the pack', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final pm = await CloudPhone.signUp('pm');
    final supervisor = await CloudPhone.signUp('supervisor');
    final company = await pm.db.companyDao.create('Sai Constructions');
    final cloud = await pm.service.registerCompany(companyId: company.id, name: company.name);
    final site = await pm.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));

    // The office orders 100 bags of cement.
    final vendor = await pm.db.supplierDao.create(SuppliersCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Sri Balaji Traders'));
    final request = await pm.db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
        id: uuid.v4(), projectId: site.id, raisedBy: pm.localUserId, materialName: 'Cement (OPC 53)',
        quantity: const Value(100), unit: const Value('bags'), status: const Value('approved')));
    final po = await pm.db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
        id: uuid.v4(), projectId: site.id, supplierId: vendor.id, requestId: Value(request.id), raisedBy: pm.localUserId,
        poNumber: const Value('PO-0042'), totalAmount: const Value(40000), status: const Value('issued')));
    expect((await pm.engine.pushPending()).failed, 0);

    await supervisor.service.joinCompany(cloud.joinCode!);
    await supervisor.engine.pullAll();
    expect(await supervisor.db.purchaseDao.ordersFor(site.id), hasLength(1));

    // On site, no signal: the truck brings 95 bags. The supervisor records
    // them against the PO, photographs the slip and says nothing more is
    // coming. Nothing is pushed yet.
    final slipBytes = img.encodeJpg(img.Image(width: 240, height: 320)..clear(img.ColorRgb8(230, 225, 210)));
    final slip = File('${supervisor.filesDir.path}/slip.jpg')..writeAsBytesSync(slipBytes);
    final s = supervisor.db;
    final receipt = await s.purchaseDao.receiveAgainstOrder(
      po.id,
      closeOrder: true,
      slipPath: slip.path,
      MaterialReceiptsCompanion.insert(
        id: uuid.v4(),
        projectId: site.id,
        poId: Value(po.id),
        supplierId: Value(vendor.id),
        materialName: 'Cement (OPC 53)',
        quantity: 95,
        unit: const Value('bags'),
        amount: 38000,
        receivedBy: supervisor.localUserId,
        receivedOn: DateTime.now(),
      ),
    );
    final waiting = await s.select(s.syncOutbox).get();
    expect(waiting.map((e) => e.targetTable),
        containsAll(['site_material_receipts', 'site_receipt_attachments', 'purchase_orders']));

    // Signal is back.
    final push = await supervisor.engine.pushPending();
    expect(push.failed, 0, reason: 'receipt, slip and the order marked delivered all reach the server');
    expect(await s.select(s.syncOutbox).get(), isEmpty);

    // The project manager's phone pulls: the receipt is against the PO, the
    // 5 missing bags are flagged, and the slip opens on this phone.
    await pm.engine.pullAll();
    var week = await loadWeekClose(pm.db, site, DateTime.now());
    var item = week.items.singleWhere((i) => i.kind == CloseKind.receipt);
    expect(item.id, receipt.id);
    expect(item.orderedQty, 100);
    expect(item.evidence, 1);
    final short = item.flags.singleWhere((f) => f.flag == CloseFlag.shortDelivery);
    expect(short.qty, 5);
    expect(short.english, 'Short by 5 bags against the PO');
    expect(item.flags.map((f) => f.flag), isNot(contains(CloseFlag.noSlip)));
    final slips = await pm.db.materialDao.slipsFor(receipt.id);
    expect(File(slips.single.filePath).readAsBytesSync(), slipBytes);
    expect(slips.single.filePath, startsWith(pm.filesDir.path));

    // The supervisor can't approve their own delivery, on the phone or by
    // going to the server directly.
    final supervisorActions = CloseActions(s, userId: supervisor.localUserId, role: Roles.member);
    final theirWeek = await loadWeekClose(s, site, DateTime.now());
    expect(() => supervisorActions.approve(theirWeek, theirWeek.items.single), throwsA(isA<CloseNotAllowed>()));
    await expectLater(
      supervisor.client.from('site_close_reviews').insert({
        'id': uuid.v4(),
        'project_id': site.id,
        'week_start': week.weekKey,
        'item_kind': 'receipt',
        'item_id': receipt.id,
        'decision': 'approved',
        'decided_by': supervisor.remoteUserId,
      }),
      throwsA(isA<PostgrestException>()),
    );

    // The manager approves the 95 that came (2 were split, so 93 accepted)
    // and closes the week.
    final pmActions = CloseActions(pm.db, userId: pm.localUserId, role: Roles.owner);
    await pmActions.approve(week, item, acceptedQty: 93, note: '2 bags split, 5 never came');
    week = await loadWeekClose(pm.db, site, DateTime.now());
    expect(week.canClose, isTrue);
    await pmActions.closeWeek(week);
    final pmPush = await pm.engine.pushPending();
    final errors = [for (final e in await pm.db.select(pm.db.syncOutbox).get()) e.lastError];
    expect(pmPush.failed, 0, reason: '$errors');

    // The server holds the decisions, with when each reached it, and won't let
    // anyone rewrite or remove them.
    final rows = await pm.client
        .from('site_close_reviews')
        .select()
        .eq('project_id', site.id)
        .order('created_at', ascending: true)
        .order('synced_at', ascending: true);
    expect(rows.map((r) => r['decision']), ['approved', 'closed']);
    expect(rows.first['accepted_qty'], 93);
    expect(rows.first['decided_by'], pm.remoteUserId);
    await expectLater(
        pm.client.from('site_close_reviews').update({'accepted_qty': 95}).eq('id', rows.first['id']).select(),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')));
    await expectLater(pm.client.from('site_close_reviews').delete().eq('id', rows.first['id']).select(),
        throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')));

    // The supervisor sees it approved, with what was accepted.
    await supervisor.engine.pullAll();
    final seen = await loadWeekClose(s, site, DateTime.now());
    expect(seen.isClosed, isTrue);
    item = seen.items.single;
    expect(item.state, ItemState.approved);
    expect(item.acceptedQty, 93);

    // Accounts gets one PDF with the slip in it, and a CSV.
    week = await loadWeekClose(pm.db, site, DateTime.now());
    final pdf = await buildWeekClosePack(
      week: week,
      companyName: company.name,
      names: {pm.localUserId: 'Anil (PM)'},
      photos: await packPhotos(pm.db, week),
    );
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    expect(pdf.length, greaterThan(slipBytes.length), reason: 'the slip photo is inside');
    final csv = weekCloseCsv(week);
    expect(csv, contains('Short by 5 bags against the PO'));
    expect(csv, contains(',93,'));

    await pm.close();
    await supervisor.close();
  });
}
