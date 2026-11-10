/// Upgrading to schema v21 (CRM) adds the lead, history and quote tables
/// and keeps the sites a phone already had.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v16 -> v21 upgrade adds the CRM tables and keeps old sites', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v21');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    final company = await db.companyDao.create('Sai Constructions');
    await db.projectDao.create(
        ProjectsCompanion.insert(id: 'p-old', companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    for (final t in ['crm_leads', 'crm_activities', 'crm_quotes']) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement('PRAGMA user_version = 16');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.projectDao.byId('p-old'))!.name, 'Kompally Villas');
    expect(await db.crmDao.leadsFor(company.id), isEmpty);
    final lead = await db.crmDao.addLead(companyId: company.id, name: 'Ramesh Reddy', by: 'u', source: 'nonsense');
    expect(lead.source, 'other');
    expect(lead.stage, 'new');
  });
}
