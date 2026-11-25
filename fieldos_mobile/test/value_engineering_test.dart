/// Value engineering: work value done against spend, the spend-ahead
/// alert, delay and what it costs, spend per day.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/value_engineering.dart';

SiteExpense _e(String day, double amount, {bool voided = false}) => SiteExpense(
      id: day + amount.toString(),
      projectId: 'p1',
      category: 'Material',
      amount: amount,
      incurredOn: day,
      recordedBy: 'u1',
      createdAt: DateTime(2026, 11, 1),
      voided: voided,
      gstInterState: false,
    );

void main() {
  final start = DateTime(2026, 11, 1);
  final end = DateTime(2026, 11, 30); // 30 days

  test('no budget or no dates means nothing to compare', () {
    expect(readValue(budget: 0, spent: 10, progressPct: 10, start: start, end: end, now: DateTime(2026, 11, 10)), isNull);
    expect(readValue(budget: 100, spent: 10, progressPct: 10, start: null, end: end, now: DateTime(2026, 11, 10)), isNull);
  });

  test('on track: spend follows progress, no alerts', () {
    final r = readValue(budget: 3000000, spent: 1000000, progressPct: 33, start: start, end: end, now: DateTime(2026, 11, 10))!;
    expect(r.plannedPct, 33);
    expect(r.workValueDone, 990000);
    expect(r.plannedValue, closeTo(1000000, 1));
    expect(r.spendPerDay, 100000);
    expect(r.plannedPerDay, 100000);
    expect(r.spendOutpacesProgress, isFalse);
    expect(r.behindPlan, isFalse);
    expect(r.delayCost, 0);
  });

  test('spend ahead of progress is flagged; being behind is costed at the planned daily spend', () {
    final r = readValue(budget: 3000000, spent: 1800000, progressPct: 30, start: start, end: end, now: DateTime(2026, 11, 15))!;
    expect(r.spendAheadPoints, 30);
    expect(r.spendOutpacesProgress, isTrue);
    expect(r.plannedPct, 50);
    expect(r.delayDays, 6);
    expect(r.delayCost, 600000);
    expect(r.costEfficiency, closeTo(0.5, 0.001));
  });

  test('past the end date unfinished, every day over counts as delay; finished is never flagged', () {
    final late = readValue(budget: 3000000, spent: 2000000, progressPct: 95, start: start, end: end, now: DateTime(2026, 12, 10))!;
    expect(late.delayDays, 10);
    final done = readValue(budget: 3000000, spent: 3300000, progressPct: 100, start: start, end: end, now: DateTime(2026, 12, 10))!;
    expect(done.delayDays, 0);
    expect(done.spendOutpacesProgress, isFalse);
  });

  test('spend by day covers the last days, oldest first, without cancelled entries', () {
    final days = spendByDay([_e('2026-11-10', 100), _e('2026-11-10', 50), _e('2026-11-09', 70), _e('2026-11-10', 999, voided: true)], DateTime(2026, 11, 10), days: 3);
    expect([for (final d in days) d.amount], [0, 70, 150]);
    expect(days.first.day, DateTime(2026, 11, 8));
  });
}
