/// Upgrading to schema v15 (weekly close) adds the slip and decision tables
/// and turns the old `Photo: <path>` receipt notes into delivery slips that
/// sync, leaving receipts with other notes alone.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v14 -> v15 upgrade moves delivery photos out of receipt notes', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v15');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    final photo = File('${dir.path}/grn_1.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

    var db = AppDatabase(NativeDatabase(file));
    Future<void> receipt(String id, String? notes) => db.into(db.materialReceipts).insert(MaterialReceiptsCompanion.insert(
        id: id, projectId: 'p', materialName: 'Cement', quantity: 10, amount: 3800, receivedBy: 'u',
        receivedOn: DateTime(2026, 11, 1), notes: Value(notes)));
    await receipt('r-photo', 'Photo: ${photo.path}');
    await receipt('r-gone', 'Photo: ${dir.path}/deleted.jpg');
    await receipt('r-note', 'Driver left 2 bags at gate');
    await db.customStatement('DROP TABLE receipt_attachments');
    await db.customStatement('DROP TABLE close_reviews');
    await db.customStatement('PRAGMA user_version = 14');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final slips = await db.materialDao.slipsFor('r-photo');
    expect(slips.single.filePath, photo.path);
    expect((await db.materialDao.receiptById('r-photo'))!.notes, isNull);
    expect((await db.materialDao.receiptById('r-gone'))!.notes, contains('deleted.jpg'), reason: 'no file, nothing to move');
    expect((await db.materialDao.receiptById('r-note'))!.notes, 'Driver left 2 bags at gate');
    final queued = await db.syncOutboxDao.pending();
    expect(queued.map((o) => o.targetTable), ['site_receipt_attachments']);
    expect(await db.closeDao.forProject('p'), isEmpty);
    await db.close();
  });
}
