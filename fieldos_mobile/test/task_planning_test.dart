/// Task planning: progress, the delay view, the look-ahead list, the late
/// counts on home, the upgrade that adds the columns, and their sync.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

Task task({
  String id = 't',
  String projectId = 'p',
  String status = 'todo',
  int progress = 0,
  String priority = 'normal',
  DateTime? start,
  DateTime? due,
}) =>
    Task(
      id: id,
      projectId: projectId,
      title: id,
      status: status,
      progress: progress,
      priority: priority,
      startDate: start,
      dueDate: due,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );

void main() {
  final now = DateTime(2026, 11, 10, 15, 30);

  group('delay view', () {
    test('past due and open is late by whole days', () {
      final t = task(due: DateTime(2026, 11, 7));
      expect(isOverdue(t, now), isTrue);
      expect(daysLate(t, now), 3);
      expect(lateLabel(t, now), '3 days late');
    });

    test('due today is not late', () {
      expect(isLate(task(due: DateTime(2026, 11, 10)), now), isFalse);
    });

    test('done is never late', () {
      expect(isLate(task(status: 'done', due: DateTime(2026, 11, 1)), now), isFalse);
    });

    test('a slow pace forecasts a finish after the due date', () {
      // Started 1 Nov, 10 days in (counting today) and 50% done: 20 days in
      // all, so it finishes 20 Nov against a 15 Nov due date.
      final t = task(start: DateTime(2026, 11, 1), due: DateTime(2026, 11, 15), progress: 50);
      expect(forecastFinish(t, now), DateTime(2026, 11, 20));
      expect(daysLate(t, now), 5);
      expect(lateLabel(t, now), 'Heading 5 days late');
    });

    test('on pace is not late', () {
      final t = task(start: DateTime(2026, 11, 1), due: DateTime(2026, 11, 30), progress: 50);
      expect(isLate(t, now), isFalse);
      expect(lateLabel(t, now), isNull);
    });

    test('no start date or no progress: no forecast', () {
      expect(forecastFinish(task(progress: 40, due: DateTime(2026, 11, 20)), now), isNull);
      expect(forecastFinish(task(start: DateTime(2026, 11, 1), due: DateTime(2026, 11, 20)), now), isNull);
    });

    test('1 day reads singular', () {
      expect(lateLabel(task(due: DateTime(2026, 11, 9)), now), '1 day late');
    });
  });

  test('look-ahead takes open tasks starting or due in the window, soonest first', () {
    final tasks = [
      task(id: 'due-in-20', due: DateTime(2026, 11, 30)),
      task(id: 'starts-in-3', start: DateTime(2026, 11, 13), due: DateTime(2026, 12, 30)),
      task(id: 'due-tomorrow', due: DateTime(2026, 11, 11)),
      task(id: 'done', status: 'done', due: DateTime(2026, 11, 12)),
      task(id: 'overdue', due: DateTime(2026, 11, 1)),
      task(id: 'no-dates'),
    ];
    expect(lookAhead(tasks, now, 14).map((t) => t.id), ['due-tomorrow', 'starts-in-3']);
  });

  test('list order: open, late, priority, due date', () {
    final tasks = [
      task(id: 'done', status: 'done'),
      task(id: 'low', priority: 'low', due: DateTime(2026, 11, 11)),
      task(id: 'high', priority: 'high', due: DateTime(2026, 11, 20)),
      task(id: 'late', due: DateTime(2026, 11, 2)),
      task(id: 'normal-soon', due: DateTime(2026, 11, 12)),
    ];
    expect(sortTasks(tasks, now).map((t) => t.id), ['late', 'high', 'normal-soon', 'low', 'done']);
  });

  test('late counts by project and project progress', () {
    final tasks = [
      task(id: 'a', projectId: 'p1', due: DateTime(2026, 11, 1)),
      task(id: 'b', projectId: 'p1', due: DateTime(2026, 11, 2)),
      task(id: 'c', projectId: 'p2', due: DateTime(2026, 12, 1)),
    ];
    expect(lateCountByProject(tasks, now), {'p1': 2});
    expect(projectProgress([task(progress: 50), task(status: 'done'), task()]), 50);
    expect(projectProgress([]), 0);
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    Future<void> seed() async {
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p', companyId: 'c', name: 'Site'));
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'q', companyId: 'other', name: 'Other'));
      await db.taskDao.create(TasksCompanion.insert(id: 't1', projectId: 'p', title: 'Plaster'));
      await db.taskDao.create(TasksCompanion.insert(id: 't2', projectId: 'q', title: 'Not ours'));
    }

    test('progress from a report moves status and reaches done at 100', () async {
      await seed();
      await db.taskDao.setProgress('t1', 40);
      var t = (await db.taskDao.forProject('p')).single;
      expect((t.progress, t.status), (40, 'in_progress'));
      await db.taskDao.setProgress('t1', 120);
      t = (await db.taskDao.forProject('p')).single;
      expect((t.progress, t.status), (100, 'done'));
    });

    test('marking done sets 100% and each change is queued with the new fields', () async {
      await seed();
      await db.taskDao.edit('t1', TasksCompanion(priority: const Value('high'), startDate: Value(DateTime(2026, 11, 3))));
      await db.taskDao.updateStatus('t1', 'done');
      final last = (await db.syncOutboxDao.pending()).where((o) => o.recordId == 't1').last;
      final json = jsonDecode(last.payload) as Map<String, dynamic>;
      expect(json['status'], 'done');
      expect(json['progress'], 100);
      expect(json['priority'], 'high');
      expect(json['start_date'], '2026-11-03');
    });

    test('open tasks for a company leave out other companies and done tasks', () async {
      await seed();
      await db.taskDao.create(TasksCompanion.insert(id: 't3', projectId: 'p', title: 'Done', status: const Value('done')));
      expect((await db.taskDao.openForCompany('c')).map((t) => t.id), ['t1']);
    });

    test('a row from the cloud keeps its planning fields, and old rows default', () {
      final c = taskFromSupabaseJson({
        'id': 'x',
        'project_id': 'p',
        'title': 'Slab',
        'status': 'in_progress',
        'progress': 60,
        'priority': 'high',
        'start_date': '2026-11-02',
      });
      expect(c.progress.value, 60);
      expect(c.priority.value, 'high');
      expect(c.startDate.value, DateTime(2026, 11, 2));
      final old = taskFromSupabaseJson({'id': 'y', 'project_id': 'p', 'title': 'Old'});
      expect(old.progress.value, 0);
      expect(old.priority.value, 'normal');
      expect(old.startDate.value, isNull);
    });
  });

  test('v7 -> v8 upgrade keeps tasks and defaults the new fields', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v8');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.tasks).insert(TasksCompanion.insert(id: 't', projectId: 'p', title: 'Footing'));
    for (final c in ['progress', 'priority', 'start_date']) {
      await db.customStatement('ALTER TABLE tasks DROP COLUMN $c');
    }
    await db.customStatement('DROP TABLE client_bills');
    await db.customStatement('PRAGMA user_version = 7');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final t = (await db.taskDao.forProject('p')).single;
    expect((t.title, t.progress, t.priority, t.startDate), ('Footing', 0, 'normal', null));
    await db.close();
  });
}
