/// The company plan's site limit, enforced by the server
/// (supabase/migrations/20261114130000_site_limit_enforced.sql), end to end
/// against the local Supabase stack (skips itself if it is not running): a
/// site the server refuses is parked at once with the site-limit message,
/// and a read-only phone (lib/data/write_guard.dart) still pulls.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

import 'support/cloud_phone.dart';

void main() {
  test('against the local stack: parked at once with the message; pulls work while read-only', () async {
    if (!await localStackReachable()) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('limit-owner');
    final company = await owner.db.companyDao.create('Limit Co');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final admin = adminClient();
    await admin.rpc(
      'grant_company_plan',
      params: {'p_plan': 'pilot', 'p_ends_on': '2099-01-01', 'p_company_id': company.id, 'p_invoice_ref': 'TEST-LIMIT'},
    );
    try {
      await owner.db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Tower A', status: const Value('active')),
      );
      expect((await owner.engine.pushPending()).failed, 0);

      // A second phone's site (or one this phone never pulled): the
      // phone's own check can't see it, the server can.
      final second = await owner.db.projectDao.create(
        ProjectsCompanion.insert(
          id: uuid.v4(),
          companyId: company.id,
          name: 'Tower B',
          status: const Value('planning'),
        ),
      );
      final push = await owner.engine.pushPending();
      expect(push.failed, 1);
      expect(await owner.db.syncOutboxDao.pendingCount(), 0, reason: 'parked at once, not retried 5 times');
      final parked = (await owner.db.syncOutboxDao.parked()).single;
      expect(parked.recordId, second.id);
      expect(siteLimitReasonOf(parked.lastError), contains('covers 1 active site, and 1 are open'));
      expect(await admin.from('projects').select('id').eq('id', second.id), isEmpty);

      // Read-only: the phone still pulls the server's rows and sends
      // nothing new of its own.
      owner.db.writeGuard.reason = ReadOnlyReason.offlineTooLong;
      final serverSite = uuid.v4();
      await admin.from('projects').update({'status': 'completed'}).eq('company_id', company.id);
      await admin.from('projects').insert({'id': serverSite, 'company_id': company.id, 'name': 'From the office'});
      await owner.engine.pullAll();
      expect((await owner.db.projectDao.forCompany(company.id)).map((p) => p.id), contains(serverSite));
      await expectLater(owner.db.projectDao.setStatus(serverSite, 'active'), throwsA(isA<ReadOnlyModeException>()));
      owner.db.writeGuard.reason = null;
    } finally {
      await admin.from('company_plans').delete().eq('invoice_ref', 'TEST-LIMIT');
      await admin.dispose();
      await owner.close();
    }
  });
}
