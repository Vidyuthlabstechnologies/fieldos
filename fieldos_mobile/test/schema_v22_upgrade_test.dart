/// Upgrading to schema v22 adds stores, stock moves, tools and staff
/// salary tables and keeps what a phone already had.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v21 -> v22 upgrade adds the store, tool and salary tables and keeps old sites and leads', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v22');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    final company = await db.companyDao.create('Sai Constructions');
    await db.projectDao.create(
        ProjectsCompanion.insert(id: 'p-old', companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    await db.crmDao.addLead(companyId: company.id, name: 'Ramesh Reddy', by: 'u');
    for (final t in ['stores', 'stock_moves', 'tools', 'tool_issues', 'staff_members', 'staff_advances', 'payroll_lines']) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement('PRAGMA user_version = 21');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.projectDao.byId('p-old'))!.name, 'Kompally Villas');
    expect(await db.crmDao.leadsFor(company.id), hasLength(1));
    final store = await db.warehouseDao.addStore(companyId: company.id, name: 'Main yard', by: 'u');
    expect((await db.warehouseDao.storesFor(company.id)).single.id, store.id);
    expect(await db.payrollDao.staffFor(company.id), isEmpty);
    expect(await db.warehouseDao.toolsFor(company.id), isEmpty);
  });
}
