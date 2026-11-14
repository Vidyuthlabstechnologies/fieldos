/// Workers' permits and site cards (Malaysia, UAE, UK): kinds per market,
/// expiry status, masking, renewals that replace the old date, the cloud
/// outbox, and reminders 90/60/30/7 days before.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/workers/worker_permits.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('each market tracks its own papers; India and the US none', () {
    debugSetMarket(Market.india);
    expect(permitKinds, isEmpty);
    debugSetMarket(Market.us);
    expect(permitKinds, isEmpty);
    debugSetMarket(Market.malaysia);
    expect(permitKinds.map((k) => k.key), ['plks', 'green_card', 'passport', 'fomema']);
    expect(permitKind('plks')!.blocksSiteWork, isTrue);
    expect(permitKind('passport')!.blocksSiteWork, isFalse);
    debugSetMarket(Market.uae);
    expect(permitKinds.map((k) => k.key), contains('emirates_id'));
    debugSetMarket(Market.uk);
    expect(permitKinds.map((k) => k.key), contains('cscs'));
  });

  test('numbers are masked to the last 4', () {
    expect(maskedNumber('A12345678'), '••••5678');
    expect(maskedNumber('123'), '123');
    expect(maskedNumber(null), '');
  });

  test('a renewal replaces the date, is queued for the cloud, and drives the status', () async {
    debugSetMarket(Market.malaysia);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final w = await db.workerDao.create(WorkersCompanion.insert(id: 'w1', projectId: 'p1', name: 'Agus'));
    final today = DateTime(2026, 11, 14);
    final first = await db.siteExecutionDao.savePermit(
        projectId: 'p1', workerId: w.id, kind: 'plks', expiresOn: DateTime(2026, 11, 1), by: 'u1', number: 'PLKS-998877');
    var all = await db.siteExecutionDao.permitsFor('p1');
    expect(permitStatus(all.single, today), PermitStatus.expired);
    expect(blockingExpired(all, w.id, today), hasLength(1));
    expect(workerPermitStatus(all, w.id, today), PermitStatus.expired);

    await db.siteExecutionDao.savePermit(
        projectId: 'p1', workerId: w.id, kind: 'plks', expiresOn: DateTime(2027, 1, 20, 15, 30), by: 'u1');
    all = await db.siteExecutionDao.permitsFor('p1');
    expect(all.single.id, first.id);
    expect(all.single.expiresOn, DateTime(2027, 1, 20));
    expect(permitStatus(all.single, today), PermitStatus.dueSoon);
    expect(daysLeft(all.single, today), 67);
    expect(blockingExpired(all, w.id, today), isEmpty);

    await db.siteExecutionDao.savePermit(
        projectId: 'p1', workerId: w.id, kind: 'passport', expiresOn: DateTime(2030, 5, 1), by: 'u1');
    all = await db.siteExecutionDao.permitsFor('p1');
    expect(all.first.kind, 'plks'); // soonest first
    expect(permitStatus(all.last, today), PermitStatus.ok);

    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'worker_permits') e.operation];
    expect(queued, ['insert', 'update', 'insert']);
    expect(siteExecutionProjectScoped, contains('worker_permits'));
    final remote = executionToRemote('worker_permits', all.first);
    expect(remote.keys, containsAll(['worker_id', 'expires_on', 'created_by', 'project_id']));
    expect(executionFromRemote('worker_permits', {...remote, 'synced_at': 'x'}), isNotNull);
  });

  test('owners get a reminder 90, 60, 30 and 7 days before', () {
    debugSetMarket(Market.malaysia);
    final now = DateTime(2026, 11, 14, 7);
    List<PlannedReminder> plan(DateTime expires, {bool owner = true}) => planReminders(
          now: now,
          settings: const ReminderSettings(reportOn: false, tasksOn: false, briefOn: false),
          runningSites: 1,
          reportedToday: true,
          openTasks: const [],
          isOwner: owner,
          permits: [(worker: 'Agus', permit: 'PLKS work permit', expiresOn: expires)],
        );
    final in30 = plan(DateTime(2026, 12, 14));
    expect(in30, hasLength(1));
    expect(in30.single.at, DateTime(2026, 11, 14, 9));
    expect(in30.single.body, contains('Agus'));
    expect(in30.single.payload, 'permits');
    expect(plan(DateTime(2026, 12, 20)), hasLength(1)); // 30 days before falls on 20 Nov
    expect(plan(DateTime(2026, 12, 30)), isEmpty); // no 90/60/30/7 mark this week
    expect(plan(DateTime(2026, 12, 14), owner: false), isEmpty);
  });
}
