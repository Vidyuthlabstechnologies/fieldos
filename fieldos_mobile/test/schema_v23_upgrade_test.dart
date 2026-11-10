/// Upgrading to schema v23 adds supplier quotes and keeps a phone's
/// purchase requests and orders.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v22 -> v23 upgrade adds supplier quotes and keeps old requests', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v23');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
        id: 'r-old', projectId: 'p', raisedBy: 'u', materialName: 'River sand', quantity: const Value(3)));
    await db.customStatement('DROP TABLE supplier_quotes');
    await db.customStatement('PRAGMA user_version = 22');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.purchaseDao.requestsFor('p')).single.materialName, 'River sand');
    final q = await db.supplierQuoteDao.addQuote(requestId: 'r-old', supplierId: 's', rate: 4200, by: 'u');
    expect((await db.supplierQuoteDao.forRequest('r-old')).single.id, q.id);
    expect(q.gstPct, 18);
    expect(q.status, 'received');
  });
}
