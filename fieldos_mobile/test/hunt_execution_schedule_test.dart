/// Bug hunt on the site schedule and task planning maths: links that
/// arrive from sync in a loop, diamonds and parallel chains, tasks with
/// only one date, and day counts across a daylight-saving change.
///
/// The daylight-saving tests only bite in a US or UK time zone; run them
/// with `TZ=America/New_York flutter test test/hunt_execution_schedule_test.dart`
/// (in UTC there is no clock change and they pass either way).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/schedule/schedule_rules.dart';

void main() {
  final now = DateTime(2026, 11, 10, 9);
  Task t(String id, {DateTime? start, DateTime? due, String status = 'todo', int progress = 0}) => Task(
        id: id,
        projectId: 'p',
        title: 'Task $id',
        status: status,
        progress: progress,
        priority: 'normal',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        startDate: start,
        dueDate: due,
      );
  DateTime nov(int d) => DateTime(2026, 11, d);
  DateTime day(int d) => DateTime.utc(2026, 11, d);
  TaskConstraint link(String from, String to, {String? id}) => TaskConstraint(
        id: id ?? 'c-$from-$to',
        projectId: 'p',
        taskId: to,
        kind: 'predecessor',
        description: 'Task $from',
        linkId: from,
        raisedBy: 'u',
        createdAt: DateTime(2026, 11, 1),
        updatedAt: DateTime(2026, 11, 1),
      );

  group('links from sync', () {
    test('a task after a loop still waits for the task it is linked to', () {
      // a <-> b arrived from two phones as a loop; c waits for b and is not
      // in the loop, so b still pushes it.
      final s = buildSchedule([
        t('c', start: nov(12), due: nov(13)),
        t('a', start: nov(5), due: nov(9)),
        t('b', start: nov(10), due: nov(11)),
      ], [link('a', 'b'), link('b', 'a'), link('b', 'c')], now);
      expect(s.rows, hasLength(3));
      expect(s.byId['b']!.start, day(11), reason: 'a is open past its due date and finishes today at the earliest');
      expect(s.byId['c']!.start, day(13));
      expect(s.byId['c']!.pushedBy, 'b');
      expect(s.byId['c']!.critical, isTrue, reason: 'c sets the finish');
    });

    test('a link sent twice is one link, and removing it lists every copy', () {
      final links = scheduleLinks(
          [t('a', start: nov(10), due: nov(11)), t('b', start: nov(12), due: nov(13))], [link('a', 'b', id: 'x1'), link('a', 'b', id: 'x2')]);
      expect(links, hasLength(1));
      expect(links.single.ids, ['x1', 'x2']);
    });
  });

  group('shapes of a schedule', () {
    test('a diamond waits for the later of its two branches', () {
      final s = buildSchedule([
        t('a', start: nov(10), due: nov(11)),
        t('short', start: nov(12), due: nov(12)),
        t('long', start: nov(12), due: nov(16)),
        t('d', start: nov(13), due: nov(14)),
      ], [link('a', 'short'), link('a', 'long'), link('short', 'd'), link('long', 'd')], now);
      expect(s.byId['d']!.start, day(17));
      expect(s.byId['d']!.pushedBy, 'long');
      expect([for (final r in s.critical) r.task.id]..sort(), ['a', 'd', 'long']);
      expect(s.byId['short']!.spareDays, 4);
    });

    test('two parallel chains: the shorter has spare days, the longer none', () {
      final s = buildSchedule([
        t('a1', start: nov(10), due: nov(12)),
        t('a2', start: nov(13), due: nov(20)),
        t('b1', start: nov(10), due: nov(11)),
        t('b2', start: nov(12), due: nov(14)),
      ], [link('a1', 'a2'), link('b1', 'b2')], now);
      expect(s.byId['a1']!.critical && s.byId['a2']!.critical, isTrue);
      expect(s.byId['b2']!.spareDays, 6);
      expect(s.byId['b1']!.spareDays, 6);
    });

    test('only a start date or due before start is a one-day bar on the start', () {
      final s = buildSchedule([t('s', start: nov(12)), t('r', start: nov(14), due: nov(12))], const [], now);
      expect((s.byId['s']!.start, s.byId['s']!.finish), (day(12), day(12)));
      expect((s.byId['r']!.plannedStart, s.byId['r']!.plannedFinish), (day(14), day(14)));
    });

    test('bars across a month end keep their length', () {
      final s = buildSchedule([
        t('a', start: DateTime(2026, 11, 28), due: DateTime(2026, 12, 2)),
        t('b', start: DateTime(2026, 11, 30), due: DateTime(2026, 12, 1)),
      ], [link('a', 'b')], now);
      expect(s.byId['b']!.start, DateTime.utc(2026, 12, 3));
      expect(s.byId['b']!.finish, DateTime.utc(2026, 12, 4));
      expect(s.byId['a']!.duration, 5);
    });
  });

  group('across a daylight-saving change', () {
    test('days late count calendar days, not 24-hour blocks', () {
      // US clocks go forward on 8 Mar 2026: Mar 1 to Mar 10 is 9 days.
      final due = t('x', start: DateTime(2026, 2, 20), due: DateTime(2026, 3, 1));
      expect(daysOverdue(due, DateTime(2026, 3, 10, 9)), 9);
      expect(lateLabel(due, DateTime(2026, 3, 10, 9)), '9 days late');
    });

    test('the pace forecast lands on the right day', () {
      // Half done after 10 days (25 Oct to 3 Nov, clocks back on 1 Nov):
      // 20 days in all, so it ends on 13 Nov.
      final x = t('x', start: DateTime(2026, 10, 25), due: DateTime(2026, 11, 5), progress: 50);
      expect(forecastFinish(x, DateTime(2026, 11, 3, 9)), DateTime(2026, 11, 13));
      // And in spring: 1 Mar to 10 Mar is 10 days counted, 20 in all.
      final y = t('y', start: DateTime(2026, 3, 1), due: DateTime(2026, 3, 5), progress: 50);
      expect(forecastFinish(y, DateTime(2026, 3, 10, 9)), DateTime(2026, 3, 20));
    });

    test('the look-ahead window is the days asked for', () {
      // From Mon 2 Mar, seven days is up to Sun 8 Mar; Mon 9 Mar is out.
      final list = lookAhead([t('in', start: DateTime(2026, 3, 8)), t('out', start: DateTime(2026, 3, 9))], DateTime(2026, 3, 2, 9), 7);
      expect(list.map((x) => x.id), ['in']);
    });

    test('the two-week site lookahead keeps the 14th day when clocks go back', () {
      ExecutionData data(List<Task> tasks) => ExecutionData(
            projectId: 'p',
            tasks: tasks,
            constraints: const [],
            drawings: const [],
            revisions: const [],
            rfis: const [],
            holdPoints: const [],
            defects: const [],
            photos: const [],
            units: const [],
            checks: const [],
          );
      final d = data([t('day14', start: DateTime(2026, 11, 2)), t('day15', start: DateTime(2026, 11, 3))]);
      expect(d.lookahead(DateTime(2026, 10, 19, 9)).map((i) => i.task.id), ['day14']);
    });

    test('a defect raised a week ago at the same hour is ageing', () {
      final d = ExecutionData(
        projectId: 'p',
        tasks: const [],
        constraints: const [],
        drawings: const [],
        revisions: const [],
        rfis: const [],
        holdPoints: const [],
        defects: const [],
        photos: const [],
        units: const [],
        checks: const [],
      );
      final defect = Defect(
        id: 'd',
        projectId: 'p',
        description: 'Crack',
        severity: 'minor',
        status: 'open',
        reopenCount: 0,
        raisedBy: 'u',
        createdAt: DateTime(2026, 3, 2, 10),
        updatedAt: DateTime(2026, 3, 2, 10),
      );
      expect(d.defectAgeing(defect, DateTime(2026, 3, 9, 10)), isTrue);
      expect(d.defectAgeing(defect, DateTime(2026, 3, 9, 9)), isFalse);
    });
  });
}
