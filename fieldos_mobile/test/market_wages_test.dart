/// Hourly pay and legal overtime in the markets that pay by the hour (US:
/// time and a half past 40 hours a week; UK: hours at the rate, no legal
/// premium), and the daily overtime rule of the others. India's day-based
/// wage sheet is covered by wage_sheet_and_stock_test.dart, its overtime
/// pay by overtime_pay_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';

Worker _worker(String id, String name, double? rate) =>
    Worker(id: id, projectId: 'p', name: name, dailyWage: rate, status: 'active', createdAt: DateTime(2026, 1, 1));

LabourAttendanceData _punch(String id, DateTime inAt, double? hours) => LabourAttendanceData(
      id: '${id}_$inAt',
      projectId: 'p',
      workerName: id,
      workerId: id,
      recordedBy: 'u',
      punchIn: inAt,
      punchOut: hours == null ? null : inAt.add(Duration(minutes: (hours * 60).round())),
      createdAt: inAt,
    );

void main() {
  tearDown(() => debugSetMarket(Market.india));
  final mon = DateTime(2026, 11, 2); // a Monday

  group('splitOvertime', () {
    test('US: the hours past 40 in the week are overtime, in date order', () {
      final split = splitOvertime({for (var i = 0; i < 5; i++) mon.add(Duration(days: i)): 9.0}, Market.us.config.overtime);
      expect(split.values.map((s) => s.$2), [0, 0, 0, 0, 5]);
      expect(split.values.fold<double>(0, (a, s) => a + s.$1), 40);
    });

    test('US: a 12-hour day is not overtime by itself; the week decides', () {
      final split = splitOvertime({mon: 12.0, mon.add(const Duration(days: 1)): 12.0}, Market.us.config.overtime);
      expect(split.values.every((s) => s.$2 == 0), isTrue);
    });

    test('US: a new week starts again at zero', () {
      final split = splitOvertime({
        for (var i = 0; i < 7; i++) mon.add(Duration(days: i)): 8.0, // 56 h: 16 OT
        mon.add(const Duration(days: 7)): 8.0, // next Monday: straight time
      }, Market.us.config.overtime);
      expect(split.values.fold<double>(0, (a, s) => a + s.$2), 16);
      expect(split[mon.add(const Duration(days: 7))], (8.0, 0.0));
    });

    test('Malaysia: past 8 hours a day, and past 45 in the week, never twice', () {
      final rule = Market.malaysia.config.overtime;
      expect(splitOvertime({mon: 10.0}, rule)[mon], (8.0, 2.0));
      final week = splitOvertime({for (var i = 0; i < 6; i++) mon.add(Duration(days: i)): 9.0}, rule);
      // 6 x 1 h daily OT, and 48 straight hours capped at 45: 3 more.
      expect(week.values.fold<double>(0, (a, s) => a + s.$2), 9);
      expect(week.values.fold<double>(0, (a, s) => a + s.$1 + s.$2), 54);
    });

    test('no hours, no overtime', () {
      expect(splitOvertime({}, Market.us.config.overtime), isEmpty);
      expect(splitOvertime({mon: 0.0}, Market.us.config.overtime)[mon], (0.0, 0.0));
    });
  });

  group('US wage sheet', () {
    test('pays hours at the hourly rate plus time and a half', () {
      debugSetMarket(Market.us);
      final sheet = buildWageSheet(
        workers: [_worker('mike', 'Mike', 30)],
        punches: [for (var i = 0; i < 5; i++) _punch('mike', mon.add(Duration(days: i, hours: 7)), 9)],
        expenses: const [],
        from: mon,
        to: mon.add(const Duration(days: 7)),
      );
      final l = sheet.lines.single;
      expect(l.hours, 45);
      expect(l.overtimeHours, 5);
      expect(l.earned, 40 * 30 + 5 * 45); // 1425
      expect(sheet.totalEarned, 1425);
    });

    test('a forgotten clock-out pays nothing until it is fixed, and a hand mark counts 8 hours', () async {
      debugSetMarket(Market.us);
      final sheet = buildWageSheet(
        workers: [_worker('ana', 'Ana', 20)],
        punches: [_punch('ana', mon.add(const Duration(hours: 7)), null)],
        expenses: const [],
        from: mon,
        to: mon.add(const Duration(days: 7)),
        marks: [
          AttendanceMark(id: 'm', projectId: 'p', workerId: 'ana', day: '2026-11-03', units: 1, recordedBy: 'u',
              updatedAt: DateTime(2026, 11, 3)),
        ],
      );
      final l = sheet.lines.single;
      expect(l.hours, 8);
      expect(l.earned, 160);
      expect(l.missingPunchOuts, 1);
    });

    test('hours before the period count towards that week, and are owed before', () {
      debugSetMarket(Market.us);
      final thu = mon.add(const Duration(days: 3));
      final sheet = buildWageSheet(
        workers: [_worker('mike', 'Mike', 10)],
        punches: [
          for (var i = 0; i < 4; i++) _punch('mike', mon.add(Duration(days: i, hours: 7)), 10), // Mon-Thu 40 h
          _punch('mike', mon.add(const Duration(days: 4, hours: 7)), 8), // Fri: all overtime
        ],
        expenses: const [],
        from: thu.add(const Duration(days: 1)),
        to: mon.add(const Duration(days: 7)),
      );
      final l = sheet.lines.single;
      expect(l.overtimeHours, 8);
      expect(l.earned, 8 * 15);
      expect(l.balanceDue, 400 + 120);
    });

    test('UK: hours at the rate, no legal overtime premium', () {
      debugSetMarket(Market.uk);
      final sheet = buildWageSheet(
        workers: [_worker('tom', 'Tom', 15)],
        punches: [for (var i = 0; i < 6; i++) _punch('tom', mon.add(Duration(days: i, hours: 7)), 9)],
        expenses: const [],
        from: mon,
        to: mon.add(const Duration(days: 7)),
      );
      expect(sheet.lines.single.earned, 54 * 15);
    });
  });

  test('India still pays by the day, plus overtime past 8 hours', () {
    final sheet = buildWageSheet(
      workers: [_worker('r', 'Ramesh', 800)],
      punches: [_punch('r', mon.add(const Duration(hours: 9)), 10)],
      expenses: const [],
      from: mon,
      to: mon.add(const Duration(days: 7)),
    );
    expect(sheet.lines.single.earned, 800 + 2 * 100 * 2);
  });
}
