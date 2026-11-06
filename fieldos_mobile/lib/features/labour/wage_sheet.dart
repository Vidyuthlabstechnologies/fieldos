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
}) {
  final byId = {for (final w in workers) w.id: w};
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
      final credit = dayCredit(hours, hasOpenPunch: open);
      if (day.key.isBefore(from)) {
        line.earnedBefore += credit * (line.dailyWage ?? 0);
      } else if (day.key.isBefore(to)) {
        line.days += credit;
        line.hours += hours;
        if (hours > overtimeAfterHours) line.overtimeHours += hours - overtimeAfterHours;
        if (open) line.missingPunchOuts++;
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
