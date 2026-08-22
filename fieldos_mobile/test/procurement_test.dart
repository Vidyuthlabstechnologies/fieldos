import 'package:fieldos_mobile/data/app_database.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('RFQ -> PO -> GRN procurement chain', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));
    final supplier = await db.supplierDao.create(SuppliersCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'Acme',
    ));

    // 1. RFQ
    final req = await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      raisedBy: 'u1',
      materialName: 'Cement',
      quantity: const Value(10),
      unit: const Value('bags'),
      estimatedAmount: const Value(5000),
      status: const Value('draft'),
    ));
    expect((await db.purchaseDao.requestsFor(project.id)).length, 1);

    // 2. PO from RFQ
    final po = await db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      supplierId: supplier.id,
      requestId: Value(req.id),
      raisedBy: 'u1',
      totalAmount: const Value(5000),
      status: const Value('open'),
    ));
    await db.purchaseDao.setRequestStatus(req.id, 'ordered');
    expect((await db.purchaseDao.requestsFor(project.id)).first.status, 'ordered');
    expect((await db.purchaseDao.ordersFor(project.id)).length, 1);

    // 3. GRN -> material actuals + close PO
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      poId: Value(po.id),
      supplierId: Value(supplier.id),
      costHeadId: const Value(null),
      materialName: 'Cement',
      quantity: 10,
      unit: const Value('bags'),
      amount: 5000,
      receivedBy: 'u1',
      receivedOn: DateTime.now(),
    ));
    await db.purchaseDao.setOrderStatus(po.id, 'received');

    expect((await db.materialDao.forProject(project.id)).length, 1);
    expect((await db.purchaseDao.ordersFor(project.id)).first.status, 'received');
  });
}
