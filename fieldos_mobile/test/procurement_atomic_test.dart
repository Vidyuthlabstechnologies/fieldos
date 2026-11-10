/// Procurement steps that change two records do it as one (audit P1,
/// 2026-11-10): an order and its request's status, a delivery and its
/// order's closure. Interrupted or repeated, they never leave half a step.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<PurchaseRequest> request() => db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
      id: _uuid.v4(), projectId: 'p', raisedBy: 'u', materialName: 'TMT 12mm', quantity: const Value(2)));

  PurchaseOrdersCompanion order() => PurchaseOrdersCompanion.insert(
      id: _uuid.v4(), projectId: 'p', supplierId: 's', raisedBy: 'u', totalAmount: const Value(130000));

  Future<List<(String, String)>> queued() async =>
      [for (final o in await db.syncOutboxDao.pending()) (o.targetTable, o.operation)];

  test('a PO and its request turning "ordered" happen together, and only once', () async {
    final r = await request();
    final po = await db.purchaseDao.orderFromRequest(r.id, order());
    expect(po.requestId, r.id);
    expect((await db.purchaseDao.requestsFor('p')).single.status, 'ordered');
    expect(await queued(), [
      ('purchase_requisitions', 'insert'),
      ('purchase_orders', 'insert'),
      ('purchase_requisitions', 'update'),
    ]);

    // A second tap, or a retry after the app was killed: same order back.
    final again = await db.purchaseDao.orderFromRequest(r.id, order());
    expect(again.id, po.id);
    expect(await db.purchaseDao.ordersFor('p'), hasLength(1));
    expect(await queued(), hasLength(3));
  });

  test('if the second write fails, the first is undone too', () async {
    // No such request: marking it ordered fails after the order was written.
    await expectLater(db.purchaseDao.orderFromRequest('missing', order()), throwsA(anything));
    expect(await db.purchaseDao.ordersFor('p'), isEmpty, reason: 'no orphan order');
    expect(await db.syncOutboxDao.pending(), isEmpty, reason: 'nothing half-queued for the cloud');
  });

  test('a full delivery is recorded and closes its order together; a repeat counts once', () async {
    final r = await request();
    final po = await db.purchaseDao.orderFromRequest(r.id, order());
    final receiptId = _uuid.v4();
    MaterialReceiptsCompanion receipt() => MaterialReceiptsCompanion.insert(
        id: receiptId, projectId: 'p', materialName: 'TMT 12mm', quantity: 2, amount: 130000, receivedBy: 'u',
        receivedOn: DateTime.utc(2026, 11, 10));

    await db.purchaseDao.receiveAgainstOrder(po.id, receipt(), closeOrder: true);
    await db.purchaseDao.receiveAgainstOrder(po.id, receipt(), closeOrder: true);
    final receipts = await db.materialDao.forProject('p');
    expect(receipts, hasLength(1));
    expect(receipts.single.poId, po.id);
    expect((await db.purchaseDao.ordersFor('p')).single.status, 'delivered');
    expect((await queued()).skip(3), [('site_material_receipts', 'insert'), ('purchase_orders', 'update')]);
  });

  test('a part delivery keeps the order open', () async {
    final r = await request();
    final po = await db.purchaseDao.orderFromRequest(r.id, order());
    await db.purchaseDao.receiveAgainstOrder(
        po.id,
        MaterialReceiptsCompanion.insert(
            id: _uuid.v4(), projectId: 'p', materialName: 'TMT 12mm', quantity: 1, amount: 65000, receivedBy: 'u',
            receivedOn: DateTime.utc(2026, 11, 10)),
        closeOrder: false);
    expect((await db.purchaseDao.ordersFor('p')).single.status, isNot('delivered'));
  });

  test('a receipt interrupted inside a larger step leaves nothing behind', () async {
    final r = await request();
    final po = await db.purchaseDao.orderFromRequest(r.id, order());
    final before = await db.syncOutboxDao.pendingCount();
    await expectLater(
        db.transaction(() async {
          await db.purchaseDao.receiveAgainstOrder(
              po.id,
              MaterialReceiptsCompanion.insert(
                  id: _uuid.v4(), projectId: 'p', materialName: 'TMT 12mm', quantity: 2, amount: 130000,
                  receivedBy: 'u', receivedOn: DateTime.utc(2026, 11, 10)),
              closeOrder: true);
          throw StateError('app killed');
        }),
        throwsStateError);
    expect(await db.materialDao.forProject('p'), isEmpty);
    expect((await db.purchaseDao.ordersFor('p')).single.status, po.status);
    expect(await db.syncOutboxDao.pendingCount(), before);
  });
}
