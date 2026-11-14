/// Malaysia and the UAE pay the overtime premium on a day rate; India
/// shows the hours and leaves the pay to the supervisor.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  final mon = DateTime(2026, 11, 16);
  LabourAttendanceData punch(DateTime day, double hours, {bool open = false}) => LabourAttendanceData(
        id: 'p${day.day}-$hours',
        projectId: 'p',
        workerName: 'Agus',
        workerId: 'w1',
        recordedBy: 'u',
        punchIn: day.add(const Duration(hours: 7)),
        punchOut: open ? null : day.add(Duration(minutes: 7 * 60 + (hours * 60).round())),
        createdAt: day,
      );
  WageLine line(List<LabourAttendanceData> punches, {PayCalendar calendar = const PayCalendar(), DateTime? from}) =>
      buildWageSheet(
        workers: [Worker(id: 'w1', projectId: 'p', name: 'Agus', dailyWage: 100, status: 'active', createdAt: DateTime(2026))],
        punches: punches,
        expenses: const [],
        from: from ?? mon,
        to: mon.add(const Duration(days: 7)),
        calendar: calendar,
      ).lines.single;

  test('Malaysia: 10 hours on a day rate of 100 pays 2 hours at 1.5 times 100/8', () {
    debugSetMarket(Market.malaysia);
    final l = line([punch(mon, 10)]);
    expect(l.days, 1);
    expect(l.overtimeHours, 2);
    expect(l.overtimePay, 37.5);
    expect(l.earned, 137.5);
  });

  test('Malaysia: rest day overtime is twice, public holiday three times', () {
    debugSetMarket(Market.malaysia);
    final sun = DateTime(2026, 11, 22), tue = DateTime(2026, 11, 17);
    final cal = PayCalendar(restDays: {DateTime.sunday}, holidays: {tue});
    expect(line([punch(sun, 10)], calendar: cal).overtimePay, 50);
    expect(line([punch(tue, 10)], calendar: cal).overtimePay, 75);
  });

  test('UAE: 25% extra past 8 hours', () {
    debugSetMarket(Market.uae);
    expect(line([punch(mon, 10)]).overtimePay, 31.25);
    expect(line([punch(mon, 8)]).overtimePay, 0);
  });

  test('no premium for a missing punch-out, and earlier weeks carry it into the balance', () {
    debugSetMarket(Market.malaysia);
    expect(line([punch(mon, 10, open: true)]).overtimePay, 0);
    final before = line([punch(mon, 10)], from: mon.add(const Duration(days: 1)));
    expect(before.overtimePay, 0);
    expect(before.balanceDue, 137.5);
  });

  test('India pays overtime at twice the hourly rate (labour codes)', () {
    final l = line([punch(mon, 10)]);
    expect(l.overtimeHours, 2);
    expect(l.overtimePay, 50); // 2 h × 100/8 × 2
    expect(l.earned, 150);
  });
}
