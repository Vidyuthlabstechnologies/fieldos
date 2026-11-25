/// Value engineering: is the money going out at the pace the work is
/// getting done? Work value done is the budget times the share of work
/// finished; the plan is the budget times the share of the time gone. When
/// the spend share runs ahead of the progress share the site is paying for
/// work it has not got yet, and a site behind its plan pays for every day
/// of delay at the planned daily spend. All plain arithmetic on figures the
/// phone already has, no AI.
library;

import 'package:fieldos_mobile/data/app_database.dart';

/// Points the spend share may run ahead of the progress share before the
/// site is flagged.
const spendAheadWarnPoints = 10;

class ValueReading {
  const ValueReading({
    required this.budget,
    required this.spent,
    required this.progressPct,
    required this.plannedPct,
    required this.workValueDone,
    required this.plannedValue,
    required this.spendPerDay,
    required this.plannedPerDay,
    required this.spendAheadPoints,
    required this.delayDays,
    required this.delayCost,
  });

  final double budget;
  final double spent;

  /// Work finished, 0-100, from the tasks.
  final int progressPct;

  /// Share of the time gone, 0-100, between the site's start and end dates.
  final int plannedPct;
  final double workValueDone;
  final double plannedValue;
  final double spendPerDay;
  final double plannedPerDay;

  /// Spend share less progress share, in points; positive is paying ahead
  /// of the work.
  final int spendAheadPoints;
  final int delayDays;
  final double delayCost;

  bool get spendOutpacesProgress => progressPct < 100 && spent > 0 && spendAheadPoints >= spendAheadWarnPoints;
  bool get behindPlan => delayDays > 0;

  /// Work value done per rupee spent; below 1 the work costs more than its
  /// budget share.
  double? get costEfficiency => spent <= 0 ? null : workValueDone / spent;
}

/// Null when there is no budget, or the site has no start and end dates to
/// plan against.
ValueReading? readValue({
  required double budget,
  required double spent,
  required int progressPct,
  required DateTime? start,
  required DateTime? end,
  required DateTime now,
}) {
  if (budget <= 0 || start == null || end == null) return null;
  final s = DateTime(start.year, start.month, start.day);
  final e = DateTime(end.year, end.month, end.day);
  final today = DateTime(now.year, now.month, now.day);
  final total = DateTime.utc(e.year, e.month, e.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1;
  if (total <= 0) return null;
  final elapsed = (DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(s.year, s.month, s.day)).inDays + 1).clamp(0, total);
  final progress = progressPct.clamp(0, 100);
  final plannedFrac = elapsed / total;
  final planned = (plannedFrac * 100).round();
  final plannedPerDay = budget / total;
  final lateShare = plannedFrac - progress / 100;
  var delayDays = lateShare > 0 && progress < 100 ? (lateShare * total).round() : 0;
  if (progress < 100 && today.isAfter(e)) {
    final over = DateTime.utc(today.year, today.month, today.day).difference(DateTime.utc(e.year, e.month, e.day)).inDays;
    if (over > delayDays) delayDays = over;
  }
  return ValueReading(
    budget: budget,
    spent: spent,
    progressPct: progress,
    plannedPct: planned,
    workValueDone: budget * progress / 100,
    plannedValue: budget * plannedFrac,
    spendPerDay: elapsed == 0 ? 0 : spent / elapsed,
    plannedPerDay: plannedPerDay,
    spendAheadPoints: ((spent / budget) * 100).round() - progress,
    delayDays: delayDays,
    delayCost: delayDays * plannedPerDay,
  );
}

/// Spend on each of the last [days] days ending [now], oldest first, for
/// the per-day view. Cancelled entries are left out.
List<({DateTime day, double amount})> spendByDay(Iterable<SiteExpense> expenses, DateTime now, {int days = 7}) {
  final today = DateTime(now.year, now.month, now.day);
  final sums = <String, double>{};
  for (final e in expenses.where((e) => !e.voided)) {
    final key = e.incurredOn.length >= 10 ? e.incurredOn.substring(0, 10) : e.incurredOn;
    sums[key] = (sums[key] ?? 0) + e.amount;
  }
  String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return [
    for (var i = days - 1; i >= 0; i--)
      (day: DateTime(today.year, today.month, today.day - i), amount: sums[ymd(DateTime(today.year, today.month, today.day - i))] ?? 0),
  ];
}
