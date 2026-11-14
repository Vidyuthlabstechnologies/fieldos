/// Overtime pay: daily-wage markets pay the hours past the normal day at
/// the day wage / normal hours x the company's rate (default India 2x,
/// UAE 1.25x, Malaysia 1.5x; the UK, paid by the hour, 1x), and the US app
/// pays California's daily overtime when the company is there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_pack.dart' show overtimeCell;
import 'package:fieldos_mobile/features/labour/overtime_settings_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/providers.dart';

Worker _worker(String id, double? wage) =>
    Worker(id: id, projectId: 'p', name: id, dailyWage: wage, status: 'active', createdAt: DateTime(2026, 1, 1));

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

final mon = DateTime(2026, 11, 2); // a Monday
final nextMon = addDays(mon, 7);

/// One worker's week: [hours] per day from Monday, punched in at 7 am.
WageLine _week(List<double> hours,
    {double rate = 800, OvertimePolicy? overtime, PayCalendar calendar = const PayCalendar(), List<AttendanceMark> marks = const []}) {
  final sheet = buildWageSheet(
    workers: [_worker('w', rate)],
    punches: [
      for (final (i, h) in hours.indexed)
        if (h > 0) _punch('w', addDays(mon, i).add(const Duration(hours: 7)), h),
    ],
    expenses: const [],
    from: mon,
    to: nextMon,
    overtime: overtime,
    calendar: calendar,
    marks: marks,
  );
  return sheet.lines.single;
}

void main() {
  tearDown(() => debugSetMarket(Market.india));

  group('daily-wage markets pay overtime', () {
    test('India: hours past 8 at twice the hourly rate (day wage / 8)', () {
      final l = _week([10, 8]);
      expect(l.overtimeHours, 2);
      expect(l.overtimePay, 2 * 800 / 8 * 2); // 400
      expect(l.earned, 2 * 800 + 400);
      expect(l.balanceDue, 2000);
    });

    test('UAE: 1.25x', () {
      debugSetMarket(Market.uae);
      final l = _week([11], rate: 200);
      expect(l.overtimeHours, 3);
      expect(l.overtimePay, 3 * 200 / 8 * 1.25); // 93.75
      expect(l.earned, 293.75);
    });

    test('Malaysia: 1.5x, at least 2x on the rest day and 3x on a public holiday', () {
      debugSetMarket(Market.malaysia);
      expect(_week([10], rate: 80).overtimePay, 2 * 10 * 1.5); // 30
      final cal = PayCalendar(restDays: {DateTime.sunday}, holidays: {addDays(mon, 1)});
      // Tue is a holiday, Sun the rest day: 2 h past 8 on each.
      final l = _week([0, 10, 0, 0, 0, 0, 10], rate: 80, calendar: cal);
      expect(l.overtimePay, 2 * 10 * 3 + 2 * 10 * 2);
      expect(l.days, 3 + 2, reason: 'the days themselves keep the Employment Act day rates');
    });

    test("the company's rate replaces the market default", () {
      final l = _week([10], overtime: const OvertimePolicy(multiplier: 1.5));
      expect(l.overtimePay, 2 * 100 * 1.5);
    });

    test('no overtime: earned is the days, as before', () {
      final l = _week([8, 7.5, 4]);
      expect(l.overtimePay, 0);
      expect(l.earned, 2.5 * 800);
    });

    test('a day marked by hand keeps the mark and pays no overtime on top', () {
      final l = _week([12], marks: [
        AttendanceMark(id: 'm', projectId: 'p', workerId: 'w', day: markDay(mon), units: 1.5, recordedBy: 'u',
            updatedAt: mon),
      ]);
      expect(l.days, 1.5);
      expect(l.overtimePay, 0);
      expect(l.earned, 1200);
    });

    test('no daily wage, no overtime pay', () {
      expect(_week([10], rate: 0).overtimePay, 0);
    });

    test('overtime before the period is owed in the balance', () {
      final sheet = buildWageSheet(
        workers: [_worker('w', 800)],
        punches: [_punch('w', addDays(mon, -3).add(const Duration(hours: 7)), 10)],
        expenses: const [],
        from: mon,
        to: nextMon,
      );
      final l = sheet.lines.single;
      expect(l.earned, 0);
      expect(l.overtimePayBefore, 400);
      expect(l.balanceDue, 800 + 400);
    });

    test('share text and the weekly close pack show the overtime pay', () {
      final l = _week([10, 8]);
      final text = wageSheetShareText(WageSheet(mon, nextMon, [l]), projectName: 'Site', range: 'week');
      expect(text, contains('w: 2 days × ₹800 + 2 h overtime ₹400 = ₹2,000'));
      expect(overtimeCell(l), '2 h, Rs. 400');
      expect(overtimeCell(_week([8])), '-');
    });
  });

  group('UK (by the hour)', () {
    test('1x by default; the company can set a premium', () {
      debugSetMarket(Market.uk);
      final hours = <double>[10, 10, 10, 10, 10]; // 50 h, 2 past the 48 h week
      expect(_week(hours, rate: 15).earned, 50 * 15);
      final l = _week(hours, rate: 15, overtime: const OvertimePolicy(multiplier: 1.5));
      expect(l.overtimeHours, 2);
      expect(l.earned, 48 * 15 + 2 * 15 * 1.5);
    });
  });

  group('California daily overtime', () {
    Map<DateTime, double> days(List<double> h) => {for (final (i, v) in h.indexed) addDays(mon, i): v};
    double sum(Map<DateTime, (double, double, double)> s, double Function((double, double, double)) f) =>
        s.values.fold(0.0, (a, x) => a + f(x));

    test('1.5x past 8 in a day, 2x past 12', () {
      final s = splitCaliforniaOvertime(days([10, 13, 8]));
      expect(s[mon], (8.0, 2.0, 0.0));
      expect(s[addDays(mon, 1)], (8.0, 4.0, 1.0));
      expect(s[addDays(mon, 2)], (8.0, 0.0, 0.0));
    });

    test('the 7th day in a row: 1.5x for 8 hours, 2x after, none of it straight time', () {
      final s = splitCaliforniaOvertime(days([8, 8, 8, 8, 8, 2, 10]));
      expect(s[addDays(mon, 6)], (0.0, 8.0, 2.0));
      // Mon-Fri 40 h straight; Saturday's 2 h are past the 40 in the week.
      expect(s[addDays(mon, 5)], (0.0, 2.0, 0.0));
    });

    test('a Sunday after a day off is not a 7th day', () {
      final s = splitCaliforniaOvertime(days([8, 8, 8, 8, 0, 8, 10]));
      expect(s[addDays(mon, 6)], (0.0, 10.0, 0.0), reason: '32 + 8 straight on Sat = 40, so all of Sunday is weekly OT');
      final short = splitCaliforniaOvertime(days([0, 0, 0, 0, 0, 0, 10]));
      expect(short[addDays(mon, 6)], (8.0, 2.0, 0.0));
    });

    test('weekly 40 counts only straight-time hours, so no hour is paid twice', () {
      final s = splitCaliforniaOvertime(days([9, 9, 9, 9, 9, 9])); // 54 h
      // 6 h daily OT; 48 straight hours, capped at 40: 8 more.
      expect(sum(s, (x) => x.$1), 40);
      expect(sum(s, (x) => x.$2), 14);
      expect(sum(s, (x) => x.$1 + x.$2 + x.$3), 54);
      final federal = splitOvertime(days([9, 9, 9, 9, 9, 9]), Market.us.config.overtime);
      expect(federal.values.fold(0.0, (a, x) => a + x.$2), 14, reason: 'same total here, differently placed');
    });

    test('the US wage sheet pays it when the company is in California', () {
      debugSetMarket(Market.us);
      const ca = OvertimePolicy(multiplier: 1.5, usState: 'CA');
      final l = _week([13, 8], rate: 20, overtime: ca);
      expect(l.hours, 21);
      expect(l.overtimeHours, 5);
      expect(l.doubleTimeHours, 1);
      expect(l.earned, 16 * 20 + 4 * 30 + 1 * 40); // 480
      final text = wageSheetShareText(WageSheet(mon, nextMon, [l]), projectName: 'Site', range: 'week');
      expect(text, contains(r'w: 21 h (5 h overtime, 1 h of it double time) × $20/hr = $480'));
    });

    test('other states keep federal weekly overtime', () {
      debugSetMarket(Market.us);
      for (final p in [null, const OvertimePolicy(multiplier: 1.5, usState: 'TX')]) {
        final l = _week([13, 8], rate: 20, overtime: p);
        expect(l.overtimeHours, 0);
        expect(l.earned, 21 * 20);
      }
    });

    test('California only applies in the US app', () {
      expect(const OvertimePolicy(multiplier: 2, usState: 'CA').californiaDaily, isFalse);
      debugSetMarket(Market.us);
      expect(const OvertimePolicy(multiplier: 1.5, usState: 'CA').californiaDaily, isTrue);
    });
  });

  group('company setting', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    test('defaults to the market rate, and keeps what the company sets', () async {
      for (final (m, rate) in [(Market.india, 2.0), (Market.uae, 1.25), (Market.malaysia, 1.5), (Market.uk, 1.0)]) {
        debugSetMarket(m);
        expect((await loadOvertimePolicy(db, 'c')).multiplier, rate, reason: '$m');
      }
      debugSetMarket(Market.india);
      await saveOvertimeMultiplier(db, 'c', 1.5);
      expect((await loadOvertimePolicy(db, 'c')).multiplier, 1.5);
      expect((await loadOvertimePolicy(db, 'other')).multiplier, 2, reason: 'per company');
      expect(() => saveOvertimeMultiplier(db, 'c', 0.5), throwsArgumentError);
    });

    test('the US app ignores a stored rate and reads the state', () async {
      debugSetMarket(Market.us);
      await db.settingsDao.set(overtimeMultiplierKey('c'), '3');
      await saveUsState(db, 'c', 'ca');
      final p = await loadOvertimePolicy(db, 'c');
      expect(p.multiplier, 1.5);
      expect(p.usState, 'CA');
      expect(p.californiaDaily, isTrue);
      await saveUsState(db, 'c', '');
      expect((await loadOvertimePolicy(db, 'c')).usState, isNull);
    });

    Future<void> pumpSettings(WidgetTester tester) async {
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: OvertimeSettingsScreen(companyId: 'c')),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    testWidgets('the screen saves the rate the company types', (tester) async {
      await pumpSettings(tester);
      expect(find.byKey(const Key('us-state')), findsNothing);
      await tester.enterText(find.byKey(const Key('overtime-rate')), '0.5');
      await tester.pump();
      expect(find.text('Enter a number from 1 to 5'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('overtime-rate')), '1.5');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.text('Enter a number from 1 to 5'), findsNothing);
      expect(await tester.runAsync(() => loadOvertimePolicy(db, 'c')).then((p) => p!.multiplier), 1.5);
    });

    testWidgets('the US screen asks for the state, not a rate', (tester) async {
      debugSetMarket(Market.us);
      await pumpSettings(tester);
      expect(find.byKey(const Key('overtime-rate')), findsNothing);
      await tester.tap(find.byKey(const Key('us-state')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('California').last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => loadOvertimePolicy(db, 'c')).then((p) => p!.usState), 'CA');
    });
  });
}
