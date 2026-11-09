/// Weekly wage sheet from GPS punches: days worked per labourer, what that
/// earns at their daily wage, what has already been paid to them (wages
/// and advances are site expenses tagged with the worker), and what is
/// still owed. Pure logic so the numbers can be tested.
library;

import 'package:fieldos_mobile/data/app_database.dart';

/// Hours on site that count as a full day / half day.
const fullDayHours = 7.0;
const halfDayHours = 3.5;
/// Hours beyond this in one day are shown as overtime (not paid automatically).
const overtimeAfterHours = 8.0;

/// A punch closed more than this long after it opened was not a shift: it
/// is a punch-out forgotten and done later, so it counts like an open one.
const longestShiftHours = 16.0;

/// How one day of punches counts towards pay. A punch that was never
/// closed counts as half a day and is flagged, so a forgotten punch-out
/// neither loses the worker a day nor silently pays a full one.
double dayCredit(double closedHours, {required bool hasOpenPunch}) {
  final credit = closedHours >= fullDayHours
      ? 1.0
      : closedHours >= halfDayHours
          ? 0.5
          : 0.0;
  return hasOpenPunch && credit < 0.5 ? 0.5 : credit;
}

/// What a hand mark can say about a day, as days of pay.
const markUnits = [0.0, 0.25, 0.5, 1.0, 1.5, 2.0, 3.0];

/// "½", "1½", "2×"... as shown on the register and the calendar.
String markLabel(double units) => switch (units) {
      0 => 'A',
      0.25 => '¼',
      0.5 => '½',
      1 => '1',
      1.5 => '1½',
      2 => '2×',
      3 => '3×',
      _ => units.toString(),
    };

/// yyyy-mm-dd for a local day, as marks store it.
String markDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The marks that count, as worker id -> day -> units. Cleared marks
/// (null units) are left out, so those days go back to their punches.
Map<String, Map<DateTime, double>> marksByWorker(Iterable<AttendanceMark> marks) {
  final out = <String, Map<DateTime, double>>{};
  for (final m in marks) {
    final u = m.units;
    final d = DateTime.tryParse(m.day);
    if (u == null || d == null) continue;
    out.putIfAbsent(m.workerId, () => {})[DateTime(d.year, d.month, d.day)] = u;
  }
  return out;
}

class WageLine {
  WageLine({required this.key, required this.name, this.workerId, this.dailyWage});

  final String key;
  final String name;
  final String? workerId;
  final double? dailyWage;
  double days = 0;
  double hours = 0;
  double overtimeHours = 0;
  int missingPunchOuts = 0;

  /// Days in the period whose pay comes from a hand mark.
  int markedDays = 0;
  double paidInPeriod = 0;
  double earnedBefore = 0;
  double paidBefore = 0;

  double get earned => days * (dailyWage ?? 0);

  /// Owed after this period: everything earned up to its end, minus
  /// everything paid up to its end. Negative means an advance not yet
  /// worked off.
  double get balanceDue => earnedBefore + earned - paidBefore - paidInPeriod;
}

class WageSheet {
  const WageSheet(this.from, this.to, this.lines);
  final DateTime from;
  final DateTime to; // exclusive
  final List<WageLine> lines;

  double get totalEarned => lines.fold(0, (s, l) => s + l.earned);
  double get totalPaid => lines.fold(0, (s, l) => s + l.paidInPeriod);
  double get totalDue => lines.fold(0, (s, l) => s + (l.balanceDue > 0 ? l.balanceDue : 0));
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Monday 00:00 of the week containing [t], local time.
DateTime weekStart(DateTime t) {
  final d = _day(t);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

WageSheet buildWageSheet({
  required List<Worker> workers,
  required List<LabourAttendanceData> punches,
  required List<SiteExpense> expenses,
  required DateTime from,
  required DateTime to,
  Iterable<AttendanceMark> marks = const [],
}) {
  final byId = {for (final w in workers) w.id: w};
  final marked = marksByWorker(marks);
  final lines = <String, WageLine>{};

  WageLine lineFor(String? workerId, String name) {
    final w = workerId == null ? null : byId[workerId];
    final key = w != null ? w.id : 'name:${name.trim().toLowerCase()}';
    return lines.putIfAbsent(
        key, () => WageLine(key: key, name: w?.name ?? name.trim(), workerId: w?.id, dailyWage: w?.dailyWage));
  }

  // Group punches per worker per day.
  final days = <String, Map<DateTime, List<LabourAttendanceData>>>{};
  for (final p in punches) {
    final line = lineFor(p.workerId, p.workerName);
    days.putIfAbsent(line.key, () => {}).putIfAbsent(_day(p.punchIn), () => []).add(p);
  }
  for (final entry in days.entries) {
    final line = lines[entry.key]!;
    for (final day in entry.value.entries) {
      var hours = 0.0;
      var open = false;
      for (final p in day.value) {
        final out = p.punchOut;
        final h = out == null ? null : out.difference(p.punchIn).inMinutes / 60.0;
        if (h == null || h < 0 || h > longestShiftHours) {
          open = true;
        } else {
          hours += h;
        }
      }
      // A hand mark for the day decides its pay; the hours stay on show.
      final mark = line.workerId == null ? null : marked[line.workerId]?[day.key];
      final credit = mark ?? dayCredit(hours, hasOpenPunch: open);
      if (day.key.isBefore(from)) {
        line.earnedBefore += credit * (line.dailyWage ?? 0);
      } else if (day.key.isBefore(to)) {
        line.days += credit;
        line.hours += hours;
        if (hours > overtimeAfterHours) line.overtimeHours += hours - overtimeAfterHours;
        if (open && mark == null) line.missingPunchOuts++;
        if (mark != null) line.markedDays++;
      }
    }
  }

  // Days marked by hand with no punch at all.
  for (final MapEntry(key: workerId, value: byDay) in marked.entries) {
    final w = byId[workerId];
    if (w == null) continue;
    final line = lineFor(w.id, w.name);
    final punched = days[line.key] ?? const {};
    for (final MapEntry(key: day, value: units) in byDay.entries) {
      if (punched.containsKey(day)) continue;
      if (day.isBefore(from)) {
        line.earnedBefore += units * (line.dailyWage ?? 0);
      } else if (day.isBefore(to)) {
        line.days += units;
        line.markedDays++;
      }
    }
  }

  for (final e in expenses) {
    final id = e.workerId;
    if (id == null) continue;
    final w = byId[id];
    final line = lineFor(id, w?.name ?? 'Worker');
    final on = DateTime.tryParse(e.incurredOn) ?? e.createdAt;
    final d = _day(on);
    if (d.isBefore(from)) {
      line.paidBefore += e.amount;
    } else if (d.isBefore(to)) {
      line.paidInPeriod += e.amount;
    }
  }

  // Active workers with nothing this week still appear (so nobody is forgotten).
  for (final w in workers.where((w) => w.status == 'active')) {
    lineFor(w.id, w.name);
  }

  final sorted = lines.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return WageSheet(from, to, sorted);
}
