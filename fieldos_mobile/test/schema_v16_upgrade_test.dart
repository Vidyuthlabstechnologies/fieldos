/// Upgrading to schema v16 (commercial controls) adds the budget line,
/// claim, certificate, variation and exception tables and the new work
/// order columns, and keeps the work orders a site already had.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v15 -> v16 upgrade adds commercial tables and keeps old work orders', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v16');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.workOrders).insert(WorkOrdersCompanion.insert(
        id: 'wo-old', projectId: 'p', subcontractorId: 's', description: 'Plaster, Block A', agreedAmount: const Value(50000)));
    for (final t in [
      'cost_codes',
      'work_claims',
      'work_certifications',
      'variations',
      'variation_decisions',
      'commercial_attachments',
      'exception_actions',
    ]) {
      await db.customStatement('DROP TABLE $t');
    }
    for (final c in ['unit', 'contract_qty', 'rate', 'cost_code_id']) {
      await db.customStatement('ALTER TABLE work_orders DROP COLUMN $c');
    }
    await db.customStatement('ALTER TABLE purchase_orders DROP COLUMN cost_code_id');
    await db.customStatement('ALTER TABLE site_expenses DROP COLUMN cost_code_id');
    await db.customStatement('PRAGMA user_version = 15');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final old = await db.commercialDao.workOrderById('wo-old');
    expect(old!.description, 'Plaster, Block A');
    expect(old.agreedAmount, 50000);
    expect(old.contractQty, isNull);
    expect(await db.commercialDao.claimsFor('wo-old'), isEmpty);
    expect(await db.commercialDao.costCodesFor('p'), isEmpty);

    // The new tables work straight after the upgrade.
    final order = await db.commercialDao.createWorkOrder(
        projectId: 'p', subcontractorId: 's', description: 'Internal plaster', unit: 'm²', qty: 100, rate: 250);
    final claim = await db.commercialDao.submitClaim(workOrderId: order.id, qty: 40, by: 'u');
    expect((await db.commercialDao.claimsFor(order.id)).single.id, claim.id);
  });
}
