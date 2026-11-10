/// The day register: every active worker of the site for one day, what
/// their punches count, and what was marked by hand (absent, ¼, ½, full,
/// 1½, double, triple), with the headcount by trade. Onsite's reviews ask
/// for manual attendance with quarter days and overtime multiples, and
/// for "how many masons and helpers came today".
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/workers/worker_calendar.dart' show punchIsFor;

class RegisterRow {
  RegisterRow({required this.worker, required this.fromPunches, required this.hours, required this.punched, this.marked});

  final Worker worker;

  /// What the day's punches count, as the wage sheet would.
  final double fromPunches;
  final double hours;
  final bool punched;

  /// Marked by hand; replaces [fromPunches].
  final double? marked;

  double get units => marked ?? fromPunches;
  bool get present => units > 0;
  double get cost => units * (worker.dailyWage ?? 0);
}

/// Trades people type most often. Shown through tr(), so a worker saved as
/// "Mason" reads in the app's language; other trades show as typed.
const commonTrades = [
  'Mason', 'Helper', 'Carpenter', 'Bar bender', 'Electrician', 'Plumber', 'Painter', 'Welder', 'Tiler',
  'Labourer', 'Supervisor', 'Driver', 'Operator', 'Fitter', 'Other',
];

/// "Mason" and "mason " are one trade; workers without one are "Other".
String tradeOf(Worker w) {
  final r = w.role?.trim() ?? '';
  if (r.isEmpty) return 'Other';
  return r[0].toUpperCase() + r.substring(1);
}

/// One row per active worker (and any inactive one marked or punched that
/// day), in trade then name order.
List<RegisterRow> buildRegister({
  required List<Worker> workers,
  required List<LabourAttendanceData> punches,
  required List<AttendanceMark> marks,
  required DateTime day,
}) {
  final d = DateTime(day.year, day.month, day.day);
  final next = d.add(const Duration(days: 1));
  final key = markDay(d);
  final marked = {for (final m in marks.where((m) => m.day == key && m.units != null)) m.workerId: m.units!};
  final rows = <RegisterRow>[];
  for (final w in workers) {
    var hours = 0.0;
    var open = false;
    var punched = false;
    for (final p in punches) {
      if (!punchIsFor(p, w)) continue;
      final at = p.punchIn.toLocal();
      if (at.isBefore(d) || !at.isBefore(next)) continue;
      punched = true;
      final out = p.punchOut;
      final h = out == null ? null : out.difference(p.punchIn).inMinutes / 60.0;
      if (h == null || h < 0 || h > longestShiftHours) {
        open = true;
      } else {
        hours += h;
      }
    }
    if (w.status != 'active' && !punched && !marked.containsKey(w.id)) continue;
    rows.add(RegisterRow(
      worker: w,
      fromPunches: punched ? dayCredit(hours, hasOpenPunch: open) : 0,
      hours: hours,
      punched: punched,
      marked: marked[w.id],
    ));
  }
  rows.sort((a, b) {
    final t = tradeOf(a.worker).toLowerCase().compareTo(tradeOf(b.worker).toLowerCase());
    return t != 0 ? t : a.worker.name.toLowerCase().compareTo(b.worker.name.toLowerCase());
  });
  return rows;
}

class TradeCount {
  const TradeCount(this.trade, this.people, this.days);
  final String trade;
  final int people;

  /// Days of pay, so 2 helpers on half days show as 1.
  final double days;
}

/// Who came, by trade, most people first.
List<TradeCount> headcountByTrade(Iterable<RegisterRow> rows) {
  final people = <String, int>{};
  final days = <String, double>{};
  for (final r in rows.where((r) => r.present)) {
    final t = tradeOf(r.worker);
    people[t] = (people[t] ?? 0) + 1;
    days[t] = (days[t] ?? 0) + r.units;
  }
  final out = [for (final t in people.keys) TradeCount(t, people[t]!, days[t]!)]
    ..sort((a, b) => b.people != a.people ? b.people.compareTo(a.people) : a.trade.compareTo(b.trade));
  return out;
}

/// People punched in that day by a typed name that isn't in the worker
/// list, so the headcount doesn't miss them.
int unlistedPunched(List<Worker> workers, List<LabourAttendanceData> punches, DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final next = d.add(const Duration(days: 1));
  final names = <String>{};
  for (final p in punches) {
    final at = p.punchIn.toLocal();
    if (at.isBefore(d) || !at.isBefore(next)) continue;
    if (workers.any((w) => punchIsFor(p, w))) continue;
    names.add(p.workerName.trim().toLowerCase());
  }
  return names.length;
}
