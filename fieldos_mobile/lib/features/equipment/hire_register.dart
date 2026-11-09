/// Machines by the hour and the hire register, kept apart from the
/// screens so the money can be tested. From Onsite's Play reviews: "JCB
/// hourly charges", "machinery on rent, how many days", "when to return".
library;

import 'package:fieldos_mobile/data/app_database.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool isHired(EquipmentData e) => e.ownership == 'hired';

/// What a usage log costs at the machine's hourly rate, or null when the
/// machine has none or no hours were logged.
double? costAtHourlyRate(EquipmentData e, double? hours) {
  final rate = e.hourlyRate;
  if (rate == null || hours == null || hours <= 0) return null;
  return (rate * hours * 100).roundToDouble() / 100;
}

/// Days on hire, both ends counted, up to the return or [now].
int daysOnHire(EquipmentData e, DateTime now) {
  final from = e.hiredOn;
  if (from == null) return 0;
  final to = _day(e.returnedOn ?? now);
  final n = to.difference(_day(from)).inDays + 1;
  return n < 0 ? 0 : n;
}

enum HireState { onHire, dueSoon, overdue, returned }

/// Due soon is within two days of the agreed return.
HireState hireState(EquipmentData e, DateTime now) {
  if (e.returnedOn != null) return HireState.returned;
  final due = e.returnDueOn;
  if (due == null) return HireState.onHire;
  final left = _day(due).difference(_day(now)).inDays;
  if (left < 0) return HireState.overdue;
  if (left <= 2) return HireState.dueSoon;
  return HireState.onHire;
}

/// Days past the agreed return (0 when not late).
int daysOverdue(EquipmentData e, DateTime now) {
  final due = e.returnDueOn;
  if (due == null) return 0;
  final end = _day(e.returnedOn ?? now);
  final late = end.difference(_day(due)).inDays;
  return late > 0 ? late : 0;
}

/// What the hire has cost so far. By the hour when the machine has an
/// hourly rate (hours from its usage logs), else by the day.
class HireCharge {
  const HireCharge({required this.amount, required this.hours, required this.days, required this.byHour});
  final double amount;
  final double hours;
  final int days;
  final bool byHour;
}

HireCharge hireCharge(EquipmentData e, Iterable<EquipmentLog> logs, DateTime now) {
  final days = daysOnHire(e, now);
  final from = e.hiredOn == null ? null : _day(e.hiredOn!);
  final to = e.returnedOn == null ? null : _day(e.returnedOn!);
  final hours = logs
      .where((l) => l.equipmentId == e.id && l.logType == 'usage' && l.hoursUsed != null)
      .where((l) => from == null || !_day(l.logDate).isBefore(from))
      .where((l) => to == null || !_day(l.logDate).isAfter(to))
      .fold<double>(0, (s, l) => s + l.hoursUsed!);
  if (e.hourlyRate != null) {
    return HireCharge(amount: (e.hourlyRate! * hours * 100).roundToDouble() / 100, hours: hours, days: days, byHour: true);
  }
  return HireCharge(amount: (e.dailyRate ?? 0) * days, hours: hours, days: days, byHour: false);
}

/// The hire register: machines on hire first (overdue at the top, then by
/// return date), returned ones after, newest return first.
List<EquipmentData> hireRegister(Iterable<EquipmentData> all, DateTime now) {
  final hired = all.where(isHired).toList();
  int rank(EquipmentData e) => switch (hireState(e, now)) {
        HireState.overdue => 0,
        HireState.dueSoon => 1,
        HireState.onHire => 2,
        HireState.returned => 3,
      };
  hired.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    if (a.returnedOn != null && b.returnedOn != null) return b.returnedOn!.compareTo(a.returnedOn!);
    final ad = a.returnDueOn ?? DateTime(9999);
    final bd = b.returnDueOn ?? DateTime(9999);
    return ad.compareTo(bd);
  });
  return hired;
}
