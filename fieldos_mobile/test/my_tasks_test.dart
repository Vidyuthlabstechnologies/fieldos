import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/tasks_tab.dart';
import 'package:fieldos_mobile/features/tasks/my_tasks_screen.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

/// Tasks could not be given to anyone, and there was no list of your own
/// work across sites: you had to open every project to find it.
void main() {
  final now = DateTime(2026, 11, 6, 10);

  Task task(String id, {DateTime? due, String status = 'todo', String? assignee, String project = 'p1'}) => Task(
        id: id,
        projectId: project,
        title: id,
        assigneeId: assignee,
        dueDate: due,
        status: status,
        createdAt: now,
        updatedAt: now,
        progress: status == 'done' ? 100 : 0,
        priority: 'normal',
        startDate: null,
      );

  test('open tasks are grouped by when they are due, done ones left out', () {
    final groups = groupTasks([
      task('late', due: DateTime(2026, 11, 2)),
      task('soon', due: DateTime(2026, 11, 10)),
      task('later', due: DateTime(2026, 12, 20)),
      task('undated'),
      task('finished', due: DateTime(2026, 11, 1), status: 'done'),
    ], now);
    expect(groups.keys, [TaskGroup.late, TaskGroup.thisWeek, TaskGroup.later, TaskGroup.noDate]);
    expect([for (final l in groups.values) ...l.map((t) => t.id)], ['late', 'soon', 'later', 'undated']);
  });

  test('"given to me" keeps only my tasks', () {
    final all = [task('a', assignee: 'me'), task('b', assignee: 'other'), task('c')];
    final mine = groupTasks(all, now, myUserId: 'me', mine: true);
    expect(mine.values.expand((l) => l).map((t) => t.id), ['a']);
    expect(groupTasks(all, now, mine: true), isEmpty, reason: 'no cloud account, nothing is mine');
  });

  test('the team list is kept on the phone and names the assignee', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect(await loadRoster(db, 'c1'), isEmpty);
    await saveRoster(db, 'c1', const [
      CloudMember(userId: 'u1', email: 'meena@site.in', role: 'owner'),
      CloudMember(userId: 'u2', email: 'ravi@site.in', role: 'site_engineer'),
    ], myUserId: 'u1');
    final members = await loadRoster(db, 'c1');
    expect(members.map((m) => m.email), ['meena@site.in', 'ravi@site.in']);
    expect(await loadRoster(db, 'other-company'), isEmpty);
    final roster = TeamRoster(members: members, myUserId: await db.settingsDao.get(cloudUserIdKey));
    expect(roster.canAssign, isTrue);
    expect(roster.labelFor('u1'), 'You');
    expect(roster.labelFor('u2'), 'ravi');
    expect(roster.labelFor('gone'), 'Someone on the team');
    expect(roster.labelFor(null), isNull);
  });

  group('screens', () {
    Future<(ProviderContainer, AppDatabase, Project, Project)> pump(WidgetTester tester, {bool team = false}) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = AppDatabase.memory();
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      late Project a, b;
      await tester.runAsync(() async {
        a = await db.projectDao.create(ProjectsCompanion.insert(id: 'pa', companyId: 'c1', name: 'Green Valley'));
        b = await db.projectDao.create(ProjectsCompanion.insert(id: 'pb', companyId: 'c1', name: 'Lake View'));
        final due = DateTime.now().add(const Duration(days: 2));
        await db.taskDao.create(TasksCompanion.insert(id: 't1', projectId: a.id, title: 'Plinth beam', dueDate: Value(due), assigneeId: const Value('u1')));
        await db.taskDao.create(TasksCompanion.insert(id: 't2', projectId: b.id, title: 'Shuttering', assigneeId: const Value('u2')));
        await db.taskDao.create(TasksCompanion.insert(id: 't3', projectId: b.id, title: 'Old job', status: const Value('done')));
        if (team) {
          await saveRoster(db, 'c1', const [
            CloudMember(userId: 'u1', email: 'meena@site.in', role: 'owner'),
            CloudMember(userId: 'u2', email: 'ravi@site.in', role: 'site_engineer'),
          ], myUserId: 'u1');
        }
      });
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const MyTasksScreen(companyId: 'c1')),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      return (container, db, a, b);
    }

    testWidgets('without Team & sync, every open task from every site', (tester) async {
      await pump(tester);
      expect(find.text('Plinth beam'), findsOneWidget);
      expect(find.text('Shuttering'), findsOneWidget);
      expect(find.text('Old job'), findsNothing);
      expect(find.text('Green Valley'), findsOneWidget);
      expect(find.text('Lake View'), findsOneWidget);
      expect(find.text('Given to me'), findsNothing);
      expect(find.textContaining('Turn on Team & sync'), findsOneWidget);
      expect(find.text('Due in the next 7 days (1)'), findsOneWidget);
    });

    testWidgets('with a team, it starts on mine and Everyone shows who has the rest', (tester) async {
      await pump(tester, team: true);
      expect(find.text('Plinth beam'), findsOneWidget);
      expect(find.text('Shuttering'), findsNothing);
      await tester.tap(find.text('Everyone'));
      await tester.pumpAndSettle();
      expect(find.text('Shuttering'), findsOneWidget);
      expect(find.text('ravi'), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
    });

    testWidgets('a task can be given to someone from its sheet', (tester) async {
      final (_, db, _, _) = await pump(tester, team: true);
      await tester.tap(find.text('Plinth beam'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned to'), findsOneWidget);
      await tester.tap(find.textContaining('meena@site.in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ravi@site.in').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      final row = await tester.runAsync(() => (db.select(db.tasks)..where((t) => t.id.equals('t1'))).getSingle());
      expect(row!.assigneeId, 'u2');
      expect(find.text('Plinth beam'), findsNothing, reason: 'no longer mine');
      final queued = await tester.runAsync(() => db.select(db.syncOutbox).get());
      expect(queued!.where((r) => r.recordId == 't1' && r.payload.contains('"assignee_id":"u2"')), isNotEmpty);
    });

    testWidgets('without a team the sheet does not offer assigning', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Plinth beam'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned to'), findsNothing);
      expect(find.text('Duplicate this task'), findsOneWidget);
      expect(duplicateMarker, isNotEmpty);
    });
  });
}
