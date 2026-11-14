/// The site schedule as a Gantt chart: each dated task as a bar, the
/// "earlier work" links between tasks (finish-to-start), where a late task
/// pushes the ones after it, and the critical path, the chain of tasks with
/// no spare days, so the site knows which delays move the handover.
///
/// A link is a task constraint of kind `predecessor` whose `linkId` is
/// another task of the site. It clears itself when that task is done (see
/// ExecutionData.isOpen), and is removed by clearing it by hand.
///
/// Pure functions on [Task] and [TaskConstraint] rows, so they are
/// unit-tested without a phone. Days are whole calendar days.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart' show forecastFinish;

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
int _days(DateTime a, DateTime b) => b.difference(a).inDays;

/// "Earlier work" link: [to] starts only after [from] is done.
class ScheduleLink {
  const ScheduleLink({required this.id, required this.from, required this.to});

  /// The constraint row the link is stored as.
  final String id;
  final String from;
  final String to;
}

/// Links still in force: predecessor constraints pointing at another task of
/// the site, not removed by hand. A finished predecessor still counts: its
/// bar still sits before the task.
List<ScheduleLink> scheduleLinks(Iterable<Task> tasks, Iterable<TaskConstraint> constraints) {
  final ids = {for (final t in tasks) t.id};
  final seen = <(String, String)>{};
  return [
    for (final c in constraints)
      if (c.kind == 'predecessor' &&
          c.clearedAt == null &&
          c.linkId != null &&
          c.linkId != c.taskId &&
          ids.contains(c.linkId) &&
          ids.contains(c.taskId) &&
          seen.add((c.linkId!, c.taskId)))
        ScheduleLink(id: c.id, from: c.linkId!, to: c.taskId),
  ];
}

/// Would a link making [to] wait for [from] close a loop (directly or
/// through other tasks)? The phone refuses it: a loop has no start.
bool wouldLoop(Iterable<ScheduleLink> links, {required String from, required String to}) {
  if (from == to) return true;
  final next = <String, List<String>>{};
  for (final l in links) {
    next.putIfAbsent(l.from, () => []).add(l.to);
  }
  // A loop exists if [from] can already be reached from [to].
  final stack = [to];
  final seen = <String>{};
  while (stack.isNotEmpty) {
    final x = stack.removeLast();
    if (x == from) return true;
    if (!seen.add(x)) continue;
    stack.addAll(next[x] ?? const []);
  }
  return false;
}

class ScheduledTask {
  ScheduledTask({
    required this.task,
    required this.plannedStart,
    required this.plannedFinish,
    required this.start,
    required this.finish,
    required this.pushedBy,
  });

  final Task task;

  /// The dates on the task (start, due), first and last day included.
  final DateTime plannedStart;
  final DateTime plannedFinish;

  /// Where it is heading: moved later by unfinished earlier work, by a slow
  /// pace, or because it is still open after its due date.
  final DateTime start;
  final DateTime finish;

  /// The earlier task that holds the start back, if any.
  final String? pushedBy;

  /// Days it can slip before it moves the site's finish.
  int spareDays = 0;
  bool critical = false;

  bool get done => task.status == 'done';
  int get duration => _days(plannedStart, plannedFinish) + 1;
  int get startSlip => _days(plannedStart, start);
  int get finishSlip => _days(plannedFinish, finish);
}

class Schedule {
  Schedule({required this.rows, required this.unscheduled, required this.links});

  /// Dated tasks, by projected start then planned finish.
  final List<ScheduledTask> rows;

  /// Tasks with no start or due date: not on the chart.
  final List<Task> unscheduled;
  final List<ScheduleLink> links;

  late final Map<String, ScheduledTask> byId = {for (final r in rows) r.task.id: r};

  DateTime? get first => rows.isEmpty ? null : rows.map((r) => r.plannedStart.isBefore(r.start) ? r.plannedStart : r.start).reduce(_min);
  DateTime? get last => rows.isEmpty ? null : rows.map((r) => r.plannedFinish.isAfter(r.finish) ? r.plannedFinish : r.finish).reduce(_max);

  /// The last planned day of the site, and where it is heading.
  DateTime? get plannedFinish => rows.isEmpty ? null : rows.map((r) => r.plannedFinish).reduce(_max);
  DateTime? get projectedFinish => rows.isEmpty ? null : rows.map((r) => r.finish).reduce(_max);

  /// Days the site is heading past its planned finish (0 when on time).
  int get daysLate {
    final p = plannedFinish, f = projectedFinish;
    if (p == null || f == null) return 0;
    final d = _days(p, f);
    return d > 0 ? d : 0;
  }

  List<ScheduledTask> get critical => [for (final r in rows) if (r.critical) r];

  /// Tasks [taskId] waits for, and those waiting for it.
  List<ScheduleLink> linksInto(String taskId) => [for (final l in links) if (l.to == taskId) l];
  List<ScheduleLink> linksOutOf(String taskId) => [for (final l in links) if (l.from == taskId) l];
}

DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
DateTime _max(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

/// Lays the site's tasks out on the calendar as of [now].
///
/// Forward pass: an open task starts no earlier than its own start date and
/// the day after every earlier task's projected finish, keeps its planned
/// length, and never finishes before its pace forecast or before today.
/// Done tasks stay where they were planned. Backward pass from the latest
/// projected finish gives each open task its spare days; those with none
/// are the critical path. Links that would make a loop are ignored.
Schedule buildSchedule(List<Task> tasks, List<TaskConstraint> constraints, DateTime now) {
  final today = _day(now);
  final dated = <Task>[];
  final unscheduled = <Task>[];
  for (final t in tasks) {
    (t.startDate == null && t.dueDate == null ? unscheduled : dated).add(t);
  }
  final links = scheduleLinks(dated, constraints);
  final preds = <String, List<String>>{};
  final succs = <String, List<String>>{};
  for (final l in links) {
    preds.putIfAbsent(l.to, () => []).add(l.from);
    succs.putIfAbsent(l.from, () => []).add(l.to);
  }

  // Kahn's order; whatever is left in a loop goes last, its loop links
  // ignored (the phone refuses new ones, but rows can arrive from sync).
  final indegree = {for (final t in dated) t.id: (preds[t.id] ?? const []).length};
  final queue = [for (final t in dated) if (indegree[t.id] == 0) t.id];
  final order = <String>[];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    order.add(id);
    for (final s in succs[id] ?? const <String>[]) {
      indegree[s] = indegree[s]! - 1;
      if (indegree[s] == 0) queue.add(s);
    }
  }
  final placed = order.toSet();
  order.addAll([for (final t in dated) if (!placed.contains(t.id)) t.id]);

  final taskById = {for (final t in dated) t.id: t};
  final out = <String, ScheduledTask>{};
  for (final id in order) {
    final t = taskById[id]!;
    final ps = _day(t.startDate ?? t.dueDate!);
    var pf = _day(t.dueDate ?? t.startDate!);
    if (pf.isBefore(ps)) pf = ps;
    if (t.status == 'done') {
      out[id] = ScheduledTask(task: t, plannedStart: ps, plannedFinish: pf, start: ps, finish: pf, pushedBy: null);
      continue;
    }
    var start = ps;
    String? pushedBy;
    for (final p in preds[id] ?? const <String>[]) {
      final before = out[p];
      // Not placed yet means a loop: that link is ignored.
      if (before == null || before.done) continue;
      final earliest = before.finish.add(const Duration(days: 1));
      if (earliest.isAfter(start)) {
        start = earliest;
        pushedBy = p;
      }
    }
    var finish = start.add(Duration(days: _days(ps, pf)));
    final pace = forecastFinish(t, now);
    if (pace != null && _day(pace).isAfter(finish)) finish = _day(pace);
    if (finish.isBefore(today)) finish = today;
    out[id] = ScheduledTask(task: t, plannedStart: ps, plannedFinish: pf, start: start, finish: finish, pushedBy: pushedBy);
  }

  if (out.isNotEmpty) {
    final end = out.values.map((r) => r.finish).reduce(_max);
    final latestFinish = <String, DateTime>{};
    for (final id in order.reversed) {
      final r = out[id]!;
      var lf = end;
      for (final s in succs[id] ?? const <String>[]) {
        final next = out[s]!;
        final lfs = latestFinish[s];
        if (lfs == null || next.done) continue;
        final ls = lfs.subtract(Duration(days: _days(next.start, next.finish)));
        final before = ls.subtract(const Duration(days: 1));
        if (before.isBefore(lf)) lf = before;
      }
      latestFinish[id] = lf;
      if (!r.done) {
        r.spareDays = _days(r.finish, lf);
        if (r.spareDays < 0) r.spareDays = 0;
        r.critical = r.spareDays == 0;
      }
    }
  }

  final rows = out.values.toList()
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.finish.compareTo(b.finish);
    });
  return Schedule(rows: rows, unscheduled: unscheduled, links: links);
}
