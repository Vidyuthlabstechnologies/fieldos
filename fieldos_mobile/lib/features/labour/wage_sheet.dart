/// Weekly wage sheet from GPS punches: days worked per labourer, what that
/// earns at their daily wage, what has already been paid to them (wages
/// and advances are site expenses tagged with the worker), and what is
/// still owed. Pure logic so the numbers can be tested.
library;

import 'package:fieldos_mobile/core/market.dart';
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

/// The company's rest day and public holidays, where the market pays more
/// for work on them (Malaysia's Employment Act 1955, s60 and s60D):
/// a rest day worked is 1 day's pay for up to half the normal hours and 2
/// days' for more; a public holiday worked is 2 days' pay on top of the
/// holiday's own pay, so 3 in all. Overtime hours stay on show, as on
/// other days. Elsewhere the calendar is empty and nothing changes.
class PayCalendar {
  const PayCalendar({this.restDays = const {}, this.holidays = const {}});

  /// Weekdays (DateTime.monday..sunday) that are the rest day.
  final Set<int> restDays;

  /// Public holidays the company observes, as local days.
  final Set<DateTime> holidays;

  bool isHoliday(DateTime day) => holidays.contains(DateTime(day.year, day.month, day.day));
  bool isRestDay(DateTime day) => restDays.contains(day.weekday);

  /// A punched day's [credit] (0, ½ or 1 day) as days of pay.
  double creditFor(DateTime day, double credit) {
    if (credit <= 0 || !market.premiumRestAndHolidayPay) return credit;
    if (isHoliday(day)) return 3;
    if (isRestDay(day)) return credit >= 1 ? 2 : 1;
    return credit;
  }
}

/// The market's minimum daily rate when [dailyWage] is under it, for a
/// week with the calendar's rest days off; null when it is not (or the
/// market sets no national minimum, or no wage is set).
double? belowMinimumWage(double? dailyWage, PayCalendar calendar) {
  final min = market.minimumWage;
  if (min == null || dailyWage == null || dailyWage <= 0) return null;
  final workDays = 7 - (calendar.restDays.isEmpty ? 1 : calendar.restDays.length);
  final floor = min.dailyFor(workDays);
  return dailyWage + 0.005 < floor ? floor : null;
}

/// Settings keys for a company's pay calendar.
String restDayKey(String companyId) => 'rest_day:$companyId';
String publicHolidaysKey(String companyId) => 'public_holidays:$companyId';

/// Reads the company's pay calendar; Sunday is the rest day unless set.
Future<PayCalendar> loadPayCalendar(AppDatabase db, String companyId) async {
  if (!market.premiumRestAndHolidayPay) return const PayCalendar();
  final rest = int.tryParse((await db.settingsDao.get(restDayKey(companyId))) ?? '') ?? DateTime.sunday;
  final raw = (await db.settingsDao.get(publicHolidaysKey(companyId))) ?? '';
  final days = <DateTime>{
    for (final d in raw.split(',').map((e) => DateTime.tryParse(e.trim())).whereType<DateTime>())
      DateTime(d.year, d.month, d.day),
  };
  return PayCalendar(restDays: {rest}, holidays: days);
}

/// Hours a hand-marked day stands for where crews are paid by the hour.
const markedDayHours = 8.0;

/// One worker's days split into straight-time and overtime hours by the
/// market's rule ([OvertimeRule]): past [OvertimeRule.dailyHours] in a day,
/// and past [OvertimeRule.weeklyHours] in a work week (Monday to Sunday),
/// counted in date order so the hours that tip the week over 40 are the
/// overtime ones. An hour is never counted as overtime twice.
Map<DateTime, (double regular, double overtime)> splitOvertime(Map<DateTime, double> hoursByDay, OvertimeRule rule) {
  final out = <DateTime, (double, double)>{};
  final weekTotals = <DateTime, double>{};
  for (final day in hoursByDay.keys.toList()..sort()) {
    final h = hoursByDay[day]!;
    var ot = rule.dailyHours == null ? 0.0 : (h - rule.dailyHours!).clamp(0, h).toDouble();
    var regular = h - ot;
    final week = weekStart(day);
    final before = weekTotals[week] ?? 0;
    if (rule.weeklyHours != null) {
      final room = (rule.weeklyHours! - before).clamp(0, double.infinity).toDouble();
      if (regular > room) {
        ot += regular - room;
        regular = room;
      }
    }
    weekTotals[week] = before + regular;
    out[day] = (regular, ot);
  }
  return out;
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

  /// Pay for hours, where the market pays by the hour (set by
  /// [buildWageSheet]); null where pay goes by days.
  double? hourlyEarned;
  double hourlyEarnedBefore = 0;

  /// [dailyWage] is the rate per hour where the market pays by the hour.
  double get earned => hourlyEarned ?? days * (dailyWage ?? 0);

  /// Owed after this period: everything earned up to its end, minus
  /// everything paid up to its end. Negative means an advance not yet
  /// worked off.
  double get balanceDue => earnedBefore + hourlyEarnedBefore + earned - paidBefore - paidInPeriod;
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
  return addDays(d, -(d.weekday - DateTime.monday));
}

/// The local midnight [n] calendar days from [day]'s. Adding
/// `Duration(days: 7)` adds 168 hours, which lands an hour off midnight
/// across a daylight-saving change (US, UK): the next Monday's punches
/// then fell into the week before.
DateTime addDays(DateTime day, int n) => DateTime(day.year, day.month, day.day + n);

WageSheet buildWageSheet({
  required List<Worker> workers,
  required List<LabourAttendanceData> punches,
  required List<SiteExpense> expenses,
  required DateTime from,
  required DateTime to,
  Iterable<AttendanceMark> marks = const [],
  PayCalendar calendar = const PayCalendar(),
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

  // A punch by typed name (a walk-in later added to the list, or "type
  // name manually") is that worker's, as the calendar and day register
  // count it -- unless two workers share the name.
  final byName = <String, String?>{};
  for (final w in workers) {
    final n = w.name.trim().toLowerCase();
    byName[n] = byName.containsKey(n) ? null : w.id;
  }

  // Group punches per worker per day.
  final days = <String, Map<DateTime, List<LabourAttendanceData>>>{};
  for (final p in punches) {
    final line = lineFor(p.workerId ?? byName[p.workerName.trim().toLowerCase()], p.workerName);
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
      // A hand mark is the supervisor's own call (2× and 3× included).
      final credit = mark ?? calendar.creditFor(day.key, dayCredit(hours, hasOpenPunch: open));
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

  if (market.payHourly) _payByTheHour(lines, days, marked, from, to);

  final sorted = lines.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return WageSheet(from, to, sorted);
}

/// Hourly markets: every day's hours (a hand mark counts as
/// [markedDayHours] per day of pay), split by the overtime rule, paid at
/// the worker's hourly rate. Overtime shown is the legal overtime, weekly
/// in the US, not the "past 8 hours" hint the daily-wage markets show.
void _payByTheHour(Map<String, WageLine> lines, Map<String, Map<DateTime, List<LabourAttendanceData>>> punchDays,
    Map<String, Map<DateTime, double>> marked, DateTime from, DateTime to) {
  final rule = market.overtime;
  for (final line in lines.values) {
    final hoursByDay = <DateTime, double>{};
    for (final MapEntry(key: day, value: ps) in (punchDays[line.key] ?? const {}).entries) {
      var h = 0.0;
      for (final p in ps) {
        final out = p.punchOut;
        final d = out == null ? null : out.difference(p.punchIn).inMinutes / 60.0;
        if (d != null && d >= 0 && d <= longestShiftHours) h += d;
      }
      hoursByDay[day] = h;
    }
    final marks = line.workerId == null ? null : marked[line.workerId];
    marks?.forEach((day, units) => hoursByDay[day] = units * markedDayHours);

    final rate = line.dailyWage ?? 0;
    var inPeriod = 0.0, before = 0.0, hours = 0.0, ot = 0.0;
    splitOvertime(hoursByDay, rule).forEach((day, split) {
      final pay = split.$1 * rate + split.$2 * rate * rule.multiplier;
      if (day.isBefore(from)) {
        before += pay;
      } else if (day.isBefore(to)) {
        inPeriod += pay;
        hours += split.$1 + split.$2;
        ot += split.$2;
      }
    });
    line
      ..hourlyEarned = _round2(inPeriod)
      ..hourlyEarnedBefore = _round2(before)
      ..earnedBefore = 0
      ..hours = hours
      ..overtimeHours = ot;
  }
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
