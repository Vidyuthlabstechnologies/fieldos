/// Malaysia: work on the rest day and public holidays pays more
/// (Employment Act 1955 s60, s60D); other markets are unchanged.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';

Worker _w() => Worker(id: 'w1', projectId: 'p', name: 'Agus', dailyWage: 100, status: 'active', createdAt: DateTime(2026));

LabourAttendanceData _punch(DateTime inAt, double hours) => LabourAttendanceData(
      id: '${inAt.toIso8601String()}-$hours',
      projectId: 'p',
      workerName: 'Agus',
      workerId: 'w1',
      recordedBy: 'u',
      punchIn: inAt,
      punchOut: inAt.add(Duration(minutes: (hours * 60).round())),
      createdAt: inAt,
    );

void main() {
  tearDown(() => debugSetMarket(Market.india));

  // Week of Mon 16 Nov 2026; Sunday 22 Nov is the rest day; Thu 19 Nov a holiday.
  final mon = DateTime(2026, 11, 16);
  final cal = PayCalendar(restDays: {DateTime.sunday}, holidays: {DateTime(2026, 11, 19)});
  final punches = [
    _punch(mon.add(const Duration(hours: 8)), 8), // normal day: 1
    _punch(DateTime(2026, 11, 19, 8), 8), // public holiday: 3
    _punch(DateTime(2026, 11, 21, 8), 4), // Saturday, half: 0.5
    _punch(DateTime(2026, 11, 22, 8), 8), // rest day, full: 2
  ];

  WageSheet sheet() => buildWageSheet(
      workers: [_w()], punches: punches, expenses: const [], from: mon, to: mon.add(const Duration(days: 7)), calendar: cal);

  test('rest day and holiday work pay the Employment Act rates', () {
    debugSetMarket(Market.malaysia);
    final l = sheet().lines.single;
    expect(l.days, 1 + 3 + 0.5 + 2);
    expect(l.earned, 650);
  });

  test('a short rest-day shift pays one day', () {
    debugSetMarket(Market.malaysia);
    expect(cal.creditFor(DateTime(2026, 11, 22), 0.5), 1);
    expect(cal.creditFor(DateTime(2026, 11, 22), 0), 0);
  });

  test('India ignores the calendar', () {
    debugSetMarket(Market.india);
    expect(sheet().lines.single.days, 1 + 1 + 0.5 + 1);
  });
}
