/// A task cannot move on while a hold point on it is not released (customer
/// review: a quality officer's consultant would reject records where a pending
/// hold point stopped nothing). The server refuses the same
/// (20261128100000_hold_points_block_progress.sql); the phone checks first so
/// no refused write is left stuck in the outbox.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  late AppDatabase db;
  late Project project;

  Future<Task> task(String title, {int progress = 0, String status = 'todo'}) => db.taskDao.create(
      TasksCompanion.insert(id: 't-$title', projectId: project.id, title: title, progress: Value(progress), status: Value(status)));

  Future<void> hold(String id, {String? taskId, String status = 'pending'}) => db.into(db.holdPoints).insert(
      HoldPointsCompanion.insert(
          id: id, projectId: project.id, title: 'Rebar check', taskId: Value(taskId), status: Value(status), raisedBy: 'u1'));

  Future<Task> reload(String id) => (db.select(db.tasks)..where((x) => x.id.equals(id))).getSingle();

  setUp(() async {
    db = AppDatabase.memory();
    addTearDown(db.close);
    project = await db.projectDao
        .create(ProjectsCompanion.insert(id: 'p1', companyId: 'c1', name: 'Tower A', status: const Value('active')));
  });

  test('progress, starting and finishing are refused while the hold point is pending', () async {
    final t = await task('Slab');
    await hold('h1', taskId: t.id);
    await expectLater(db.taskDao.setProgress(t.id, 10), throwsA(isA<HoldPointRefused>()));
    await expectLater(db.taskDao.updateStatus(t.id, 'in_progress'), throwsA(isA<HoldPointRefused>()));
    await expectLater(db.taskDao.updateStatus(t.id, 'done'), throwsA(isA<HoldPointRefused>()));
    final row = await reload(t.id);
    expect((row.progress, row.status), (0, 'todo'), reason: 'nothing was written');
    final queued = (await db.syncOutboxDao.pending()).where((e) => e.targetTable == 'tasks' && e.operation == 'update');
    expect(queued, isEmpty, reason: 'and nothing refused is queued for the server');
  });

  test('the message names the task, in the person\'s language', () async {
    final t = await task('Slab');
    await hold('h1', taskId: t.id);
    try {
      await db.taskDao.setProgress(t.id, 10);
      fail('should be refused');
    } on HoldPointRefused catch (e) {
      expect(e.message, 'A hold point on "Slab" is not released yet.');
    }
    setCurrentLanguage(AppLanguage.hi);
    try {
      await db.taskDao.setProgress(t.id, 10);
      fail('should be refused');
    } on HoldPointRefused catch (e) {
      expect(e.message, contains('Slab'));
      expect(e.message, isNot(contains('A hold point on')), reason: 'translated');
    }
  });

  test('a rejected hold point holds too; releasing it lets the task move', () async {
    final t = await task('Slab');
    await hold('h1', taskId: t.id, status: 'rejected');
    await expectLater(db.taskDao.setProgress(t.id, 10), throwsA(isA<HoldPointRefused>()));
    await db.siteExecutionDao.decideHoldPoint('h1', release: true, by: 'qo');
    await db.taskDao.setProgress(t.id, 10);
    expect((await reload(t.id)).progress, 10);
  });

  test('a hold point reached through a constraint holds the task, until it is released', () async {
    final t = await task('Waits');
    await hold('h2'); // not linked to any task itself
    await db.into(db.taskConstraints).insert(TaskConstraintsCompanion.insert(
        id: 'c1',
        projectId: project.id,
        taskId: t.id,
        kind: 'hold_point',
        description: 'Shuttering check',
        linkId: const Value('h2'),
        raisedBy: 'u1'));
    await expectLater(db.taskDao.setProgress(t.id, 5), throwsA(isA<HoldPointRefused>()));
    await db.siteExecutionDao.decideHoldPoint('h2', release: true, by: 'pm');
    await db.taskDao.setProgress(t.id, 5);
    expect((await reload(t.id)).progress, 5);
  });

  test('going backwards is never blocked, and an unrelated task is untouched', () async {
    final started = await task('Column', progress: 40, status: 'in_progress');
    final free = await task('Free');
    await hold('h3', taskId: started.id);
    await db.taskDao.setProgress(started.id, 30);
    await expectLater(db.taskDao.setProgress(started.id, 60), throwsA(isA<HoldPointRefused>()));
    await db.taskDao.updateStatus(started.id, 'blocked');
    await db.taskDao.setProgress(free.id, 80);
    expect((await reload(free.id)).progress, 80);
  });

  test('a manager cannot go round a hold point: the way past is to release it', () async {
    final t = await task('Slab');
    await hold('h1', taskId: t.id);
    await expectLater(
        db.taskDao.edit(t.id, const TasksCompanion(progress: Value(50)), asManager: true), throwsA(isA<HoldPointRefused>()));
  });

  test('it is a kind of refusal the daily report can tell apart from "verify on site first"', () {
    expect(HoldPointRefused('x'), isA<ExecutionRefused>());
  });
}
