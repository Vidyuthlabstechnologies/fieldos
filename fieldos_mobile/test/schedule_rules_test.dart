import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/schedule/schedule_rules.dart';

/// The Gantt chart's maths: where a late task pushes the work after it,
/// which tasks have no spare days, and that links never make a loop.
void main() {
  final now = DateTime(2026, 11, 10, 9);
  Task t(String id, {int? start, int? due, String status = 'todo', int progress = 0}) => Task(verifyRequired: false, 
        id: id,
        projectId: 'p',
        title: 'Task $id',
        status: status,
        progress: progress,
        priority: 'normal',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
        startDate: start == null ? null : DateTime(2026, 11, start),
        dueDate: due == null ? null : DateTime(2026, 11, due),
      );
  TaskConstraint link(String from, String to, {bool cleared = false}) => TaskConstraint(
        id: 'c-$from-$to',
        projectId: 'p',
        taskId: to,
        kind: 'predecessor',
        description: 'Task $from',
        linkId: from,
        raisedBy: 'u',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
        clearedAt: cleared ? DateTime(2026, 11, 2) : null,
      );
  DateTime day(int d) => DateTime.utc(2026, 11, d);

  test('a late task pushes the ones linked after it, keeping their length', () {
    // A is due on the 9th but still open on the 10th: it finishes today at
    // the earliest, so B (planned 10-12) moves to 11-13, and C after B.
    final s = buildSchedule([
      t('a', start: 5, due: 9),
      t('b', start: 10, due: 12),
      t('c', start: 13, due: 14),
      t('x', start: 10, due: 30),
    ], [link('a', 'b'), link('b', 'c')], now);
    expect(s.byId['a']!.finish, day(10));
    expect(s.byId['b']!.start, day(11));
    expect(s.byId['b']!.finish, day(13));
    expect(s.byId['b']!.pushedBy, 'a');
    expect(s.byId['c']!.start, day(14));
    expect(s.byId['c']!.finish, day(15));
    expect(s.plannedFinish, day(30));
    expect(s.daysLate, 0, reason: 'x finishes last and on time');
    // x alone sets the finish: it is critical, the a-b-c chain has spare days.
    expect(s.byId['x']!.critical, isTrue);
    expect(s.byId['c']!.spareDays, 15);
    expect(s.byId['a']!.critical, isFalse);
  });

  test('the chain that sets the finish is the critical path', () {
    final s = buildSchedule([
      t('a', start: 10, due: 12),
      t('b', start: 13, due: 20),
      t('side', start: 10, due: 11),
      t('done', start: 1, due: 3, status: 'done'),
    ], [link('a', 'b')], now);
    expect([for (final r in s.critical) r.task.id], ['a', 'b']);
    expect(s.byId['side']!.spareDays, 9);
    expect(s.byId['done']!.critical, isFalse);
    expect(s.byId['done']!.finish, day(3), reason: 'done tasks stay where they were');
  });

  test('a slow pace moves the finish, and the site is late by the slip', () {
    // Started on the 6th, 25% after 5 days: heading for 20 days, the 25th.
    final s = buildSchedule([t('a', start: 6, due: 15, progress: 25)], const [], now);
    expect(s.byId['a']!.finish, day(25));
    expect(s.daysLate, 10);
  });

  test('a finished earlier task does not hold anything back', () {
    final s = buildSchedule([t('a', start: 1, due: 12, status: 'done'), t('b', start: 10, due: 11)], [link('a', 'b')], now);
    expect(s.byId['b']!.start, day(10));
    expect(s.byId['b']!.pushedBy, isNull);
  });

  test('undated tasks are listed apart; removed and broken links are ignored', () {
    final s = buildSchedule([t('a', start: 10, due: 11), t('b', due: 12), t('n')],
        [link('a', 'b', cleared: true), link('gone', 'b'), link('b', 'b')], now);
    expect(s.unscheduled.map((x) => x.id), ['n']);
    expect(s.links, isEmpty);
    expect(s.byId['b']!.start, day(12), reason: 'only a due date: a one-day bar');
  });

  test('loops are refused, and ones arriving from sync do not hang the chart', () {
    final links = scheduleLinks([t('a', start: 10, due: 11), t('b', start: 12, due: 13), t('c', start: 14, due: 15)],
        [link('a', 'b'), link('b', 'c')]);
    expect(wouldLoop(links, from: 'c', to: 'a'), isTrue);
    expect(wouldLoop(links, from: 'a', to: 'c'), isFalse);
    expect(wouldLoop(links, from: 'a', to: 'a'), isTrue);
    final s = buildSchedule([t('a', start: 10, due: 11), t('b', start: 12, due: 13)], [link('a', 'b'), link('b', 'a')], now);
    expect(s.rows, hasLength(2));
  });

  test('an earlier-work constraint linked to a task clears when that task is done', () {
    ExecutionData data(String status) => ExecutionData(
          projectId: 'p',
          tasks: [t('a', start: 1, due: 2, status: status), t('b', start: 3, due: 4)],
          constraints: [link('a', 'b')],
          drawings: const [],
          revisions: const [],
          rfis: const [],
          holdPoints: const [],
          defects: const [],
          photos: const [],
          units: const [],
          checks: const [],
        );
    expect(data('todo').openConstraintsOf('b'), hasLength(1));
    expect(data('done').openConstraintsOf('b'), isEmpty);
  });
}
