/// Audit follow-ups that need the local Supabase stack (skip without it).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('signing out sends what is still queued under the account that wrote it', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final phone = await CloudPhone.signUp('signout');
    final company = await phone.db.companyDao.create('Sai Constructions');
    await phone.service.registerCompany(companyId: company.id, name: company.name);
    final site = await phone.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    expect(await phone.db.syncOutboxDao.pendingCount(), greaterThan(0));
    await phone.service.disableSync();
    expect(await phone.db.syncOutboxDao.pendingCount(), 0);
    final rows = await adminClient().from('projects').select('id').eq('id', site.id);
    expect(rows, hasLength(1));
    await phone.close();
  });
}
