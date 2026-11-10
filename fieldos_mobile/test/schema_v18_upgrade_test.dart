/// Upgrading to schema v18 adds the measurement book, bill allocations and
/// supplier invoices.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v17 -> v18 upgrade creates the billing tables', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v18');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    for (final t in ['work_measurements', 'work_measurement_decisions', 'bill_allocations', 'supplier_invoices']) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement('PRAGMA user_version = 17');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final m = await db.billingRecordsDao
        .measure(projectId: 'p', description: 'PCC', unit: 'cum', qty: 3, on: DateTime(2026, 11, 2), by: 'u');
    await db.billingRecordsDao.decide(m.id, approve: true, by: 'pm');
    expect((await db.billingRecordsDao.decisionsFor('p'))[m.id]!.approvedQty, 3);
    expect(await db.billingRecordsDao.allocationsFor('p'), isEmpty);
    expect(await db.billingRecordsDao.supplierInvoicesFor('p'), isEmpty);
    await db.close();
  });
}
