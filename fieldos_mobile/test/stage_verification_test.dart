/// Stage checklists and on-site verification: a stage becomes one task per
/// step (Dressing is one task of at least a day), each task needs a check
/// made at the site before it can reach 100%, a phone too far from the site
/// is refused, a manager is exempt, and every check is queued for the cloud.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/activity_templates.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('a stage becomes a task per step; nothing reaches 100% without a check at the site', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.siteOpsDao;
    await expectLater(x.addStageChecklist(projectId: 'p1', stageIds: const [], start: DateTime(2026, 12, 1)), throwsA(isA<ExecutionRefused>()));

    final n = await x.addStageChecklist(projectId: 'p1', stageIds: const ['columns', 'dressing'], start: DateTime(2026, 12, 1));
    expect(n, stageById('columns')!.steps.length + 1);
    expect(stageById('columns')!.steps, hasLength(8));
    final tasks = await db.taskDao.forProject('p1');
    expect(tasks.every((t) => t.verifyRequired), isTrue);
    final dressing = tasks.singleWhere((t) => t.title == 'Dressing');
    expect(dressing.dueDate, DateTime(2026, 12, 2), reason: 'dressing takes at least a day');
    final casting = tasks.singleWhere((t) => t.title == 'Columns: Casting');

    await expectLater(db.taskDao.edit(casting.id, const TasksCompanion(status: Value('done'), progress: Value(100))),
        throwsA(isA<ExecutionRefused>()));
    await expectLater(db.taskDao.setProgress(casting.id, 100), throwsA(isA<ExecutionRefused>()));
    await db.taskDao.setProgress(casting.id, 50);

    await db.geofenceDao.set('p1', 17.4500, 78.3800, 100);
    await expectLater(x.verifyTask(casting.id, lat: 17.4600, lng: 78.3800, by: 'u1'), throwsA(isA<ExecutionRefused>()),
        reason: 'over a kilometre away');
    expect(await x.checksFor('p1'), isEmpty);

    final check = await x.verifyTask(casting.id, lat: 17.4501, lng: 78.3801, by: 'u1', accuracyM: 8);
    expect(check.distanceM, lessThan(30));
    await db.taskDao.edit(casting.id, const TasksCompanion(status: Value('done'), progress: Value(100)));
    expect((await db.taskDao.forProject('p1')).singleWhere((t) => t.id == casting.id).status, 'done');

    final shuttering = tasks.firstWhere((t) => t.title == 'Columns: Shuttering');
    await db.taskDao.edit(shuttering.id, const TasksCompanion(status: Value('done')), asManager: true);

    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'site_task_checks') e.operation];
    expect(queued, ['insert']);
    expect(siteExecutionProjectScoped, contains('site_task_checks'));
    expect(executionToRemote('site_task_checks', check).keys, containsAll(['task_id', 'lat', 'lng', 'checked_by', 'distance_m']));
  });
}
