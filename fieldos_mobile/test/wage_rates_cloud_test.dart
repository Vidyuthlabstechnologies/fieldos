/// A worker's daily wage reaches only the phones of people who may see
/// money (owner, project manager, accounts), and it travels through
/// worker_wage_rates() rather than the workers table, so the column can be
/// closed to reads later (supabase/deferred/20261125150001_revoke_workers_wage_read.sql)
/// without stopping any phone on this build from syncing workers.
/// Runs against the local Supabase stack; skips itself when it is not up.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('the pull never asks the workers table for the wage column', () {
    expect(SyncEngine.pullColumns['workers'], isNotNull);
    expect(SyncEngine.pullColumns['workers']!.split(','), isNot(contains('daily_wage')));
    // Everything the phone's mapper reads is still pulled.
    expect(SyncEngine.pullColumns['workers']!.split(','),
        containsAll(['id', 'project_id', 'name', 'role', 'phone', 'status']));
  });

  test('the owner sees a worker\'s wage on every phone; an engineer sees the worker, not the wage', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final engineer = await CloudPhone.signUp('engineer');
    final company = await owner.db.companyDao.create('Wage Co');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final site = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Villas', status: const Value('active')));
    final mason = await owner.db.workerDao.create(WorkersCompanion.insert(
        id: uuid.v4(), projectId: site.id, name: 'Ramesh', dailyWage: const Value(800)));
    expect((await owner.engine.pushPending()).failed, 0);
    await engineer.service.joinCompany(cloud.joinCode!);

    await engineer.engine.pullAll();
    final seen = await engineer.db.workerDao.forProject(site.id);
    expect(seen.map((w) => w.name), ['Ramesh']);
    expect(seen.single.dailyWage, isNull, reason: 'an engineer never receives the rate');

    // A rate typed by the engineer is refused by the server, not stored.
    final mine = await engineer.db.workerDao.create(WorkersCompanion.insert(
        id: uuid.v4(), projectId: site.id, name: 'Suresh', dailyWage: const Value(999)));
    expect((await engineer.engine.pushPending()).failed, 0);
    await owner.engine.pullAll();
    final suresh = (await owner.db.workerDao.forProject(site.id)).firstWhere((w) => w.id == mine.id);
    expect(suresh.dailyWage, isNull);

    // The owner's own rate survives a pull.
    expect((await owner.db.workerDao.forProject(site.id)).firstWhere((w) => w.id == mason.id).dailyWage, 800);
    await owner.engine.pullAll();
    expect((await owner.db.workerDao.forProject(site.id)).firstWhere((w) => w.id == mason.id).dailyWage, 800);
    await owner.close();
    await engineer.close();
  });
}
