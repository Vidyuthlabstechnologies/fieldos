/// Follow-ups from the 2026-11 audit that don't belong to one screen's tests.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('billing a work order twice adds the second bill to the first', () async {
    final c = await db.companyDao.create('Sai Constructions');
    final site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally'));
    final sub = await db.subcontractorDao.create(SubcontractorsCompanion.insert(id: 'sub-1', companyId: c.id, name: 'ACME'));
    final wo = await db.workOrderDao.createWorkOrder(WorkOrdersCompanion.insert(
        id: 'wo-1', projectId: site.id, subcontractorId: sub.id, description: 'Wiring', agreedAmount: const Value(150000.0)));
    await db.workOrderDao.billWorkOrder(wo.id, 25000);
    await db.workOrderDao.billWorkOrder(wo.id, 40000);
    expect((await db.workOrderDao.workOrdersFor(site.id)).single.billedAmount, 65000);
  });
}
