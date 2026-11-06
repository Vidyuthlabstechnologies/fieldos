/// Planning rules for tasks: what is late, when an open task will really
/// finish, what comes up next, and the order the list shows them in.
///
/// Pure functions on [Task] rows so they are unit-tested without a phone.
library;

import 'package:fieldos_mobile/data/app_database.dart';

const taskPriorities = {'high': 'High', 'normal': 'Normal', 'low': 'Low'};

int priorityRank(String p) => switch (p) { 'high' => 0, 'low' => 2, _ => 1 };

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool isOpen(Task t) => t.status != 'done';

/// Past its due date and not done.
bool isOverdue(Task t, DateTime now) => isOpen(t) && t.dueDate != null && _day(t.dueDate!).isBefore(_day(now));

/// Days past the due date (0 when not overdue).
int daysOverdue(Task t, DateTime now) => isOverdue(t, now) ? _day(now).difference(_day(t.dueDate!)).inDays : 0;

/// When the task will finish at the pace logged so far: the days since
/// [Task.startDate] stretched to 100%. Null without a start date or any
/// progress, or once it is done.
DateTime? forecastFinish(Task t, DateTime now) {
  if (!isOpen(t) || t.startDate == null || t.progress <= 0) return null;
  final start = _day(t.startDate!);
  final today = _day(now);
  if (today.isBefore(start)) return null;
  // Count today as a working day, so 50% on day one forecasts two days.
  final elapsed = today.difference(start).inDays + 1;
  final total = (elapsed * 100 / t.progress).ceil();
  return start.add(Duration(days: total - 1));
}

/// How many days after its due date the task is heading to finish, from
/// either fact: already past due, or a pace that ends after it. 0 means on
/// time or no way to tell.
int daysLate(Task t, DateTime now) {
  if (!isOpen(t) || t.dueDate == null) return 0;
  final due = _day(t.dueDate!);
  final overdue = daysOverdue(t, now);
  final forecast = forecastFinish(t, now);
  final slip = forecast == null ? 0 : forecast.difference(due).inDays;
  return overdue > slip ? overdue : (slip > 0 ? slip : 0);
}

bool isLate(Task t, DateTime now) => daysLate(t, now) > 0;

/// One line for the task card: "3 days late", "Heading 2 days late", or null.
String? lateLabel(Task t, DateTime now) {
  final overdue = daysOverdue(t, now);
  final late = daysLate(t, now);
  if (late <= 0) return null;
  String days(int n) => n == 1 ? '1 day' : '$n days';
  if (overdue >= late) return '${days(late)} late';
  return 'Heading ${days(late)} late';
}

/// Open tasks that start or fall due within the next [days] days (today
/// included), soonest first. The look-ahead list a site engineer plans
/// labour and material from.
List<Task> lookAhead(Iterable<Task> tasks, DateTime now, int days) {
  final today = _day(now);
  final end = today.add(Duration(days: days));
  DateTime? key(Task t) {
    final dates = [t.startDate, t.dueDate].whereType<DateTime>().map(_day).where((d) => !d.isBefore(today) && d.isBefore(end));
    return dates.isEmpty ? null : dates.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  final picked = [
    for (final t in tasks)
      if (isOpen(t) && key(t) != null) t,
  ]..sort((a, b) => key(a)!.compareTo(key(b)!));
  return picked;
}

/// The list order: open before done, late first, then priority, then the
/// soonest due date.
List<Task> sortTasks(Iterable<Task> tasks, DateTime now) {
  return [...tasks]..sort((a, b) {
      final ad = isOpen(a) ? 0 : 1, bd = isOpen(b) ? 0 : 1;
      if (ad != bd) return ad - bd;
      final al = isLate(a, now) ? 0 : 1, bl = isLate(b, now) ? 0 : 1;
      if (al != bl) return al - bl;
      final ap = priorityRank(a.priority), bp = priorityRank(b.priority);
      if (ap != bp) return ap - bp;
      final ax = a.dueDate ?? DateTime(9999), bx = b.dueDate ?? DateTime(9999);
      return ax.compareTo(bx);
    });
}

/// Late open tasks per project id, for the home screen.
Map<String, int> lateCountByProject(Iterable<Task> tasks, DateTime now) {
  final out = <String, int>{};
  for (final t in tasks) {
    if (isLate(t, now)) out[t.projectId] = (out[t.projectId] ?? 0) + 1;
  }
  return out;
}

/// Overall progress of a project: the average of its tasks' progress.
int projectProgress(Iterable<Task> tasks) {
  final list = tasks.toList();
  if (list.isEmpty) return 0;
  final sum = list.fold<int>(0, (s, t) => s + (t.status == 'done' ? 100 : t.progress));
  return (sum / list.length).round();
}
