/// Upgrading a phone from schema v6 (FieldOS 1.3.0) to v7 must keep its
/// data, add the new tables and column, and queue the site's existing
/// punches, expenses and receipts for the cloud exactly once.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v6 -> v7 upgrade', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v7');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    // A v6 phone with some site records (written straight to the tables,
    // as 1.3.0 did: no outbox entries for them).
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.labourAttendance).insert(LabourAttendanceCompanion.insert(
        id: 'a1', projectId: 'p', workerName: 'Ramesh', recordedBy: 'u', punchIn: DateTime(2026, 11, 1, 9)));
    await db.into(db.siteExpenses).insert(SiteExpensesCompanion.insert(
        id: 'e1', projectId: 'p', category: 'Fuel', amount: 300, incurredOn: '2026-11-01', recordedBy: 'u'));
    await db.into(db.materialReceipts).insert(MaterialReceiptsCompanion.insert(
        id: 'r1', projectId: 'p', materialName: 'Cement', quantity: 10, amount: 3800, receivedBy: 'u',
        receivedOn: DateTime(2026, 11, 1)));
    await db.customStatement('DROP TABLE material_usage');
    await db.customStatement('DROP TABLE payments_received');
    await db.customStatement('ALTER TABLE site_expenses DROP COLUMN worker_id');
    await db.customStatement('PRAGMA user_version = 6');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final queued = await db.syncOutboxDao.pending();
    expect({for (final o in queued) o.targetTable},
        {'site_attendance', 'site_expenses', 'site_material_receipts'});
    expect(queued, hasLength(3));
    expect((await db.expenseDao.forProject('p')).single.workerId, isNull);
    expect(await db.materialDao.usageForProject('p'), isEmpty);
    expect(await db.paymentDao.forProject('p'), isEmpty);
    await db.close();

    // Opening again doesn't queue them twice.
    db = AppDatabase(NativeDatabase(file));
    expect(await db.syncOutboxDao.pending(), hasLength(3));
    await db.close();
  });
}
