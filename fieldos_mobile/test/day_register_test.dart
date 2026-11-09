import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/day_register.dart';
import 'package:fieldos_mobile/features/labour/day_register_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/workers/worker_calendar.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

/// Attendance marked by hand, from Onsite's Play reviews: quarter and half
/// days, 1½, double and triple for overtime, and how many of each trade
/// came. A mark takes the place of that day's punches in the pay.
Worker _w(String id, String name, {String? role, double? wage = 600, String status = 'active'}) => Worker(
    id: id, projectId: 'p', name: name, role: role, dailyWage: wage, status: status, createdAt: DateTime(2026, 11));

LabourAttendanceData _punch(String workerId, String name, DateTime inAt, {DateTime? out}) => LabourAttendanceData(
    id: '$workerId$inAt', projectId: 'p', workerName: name, workerId: workerId, recordedBy: 'u', punchIn: inAt,
    punchOut: out, createdAt: inAt);

AttendanceMark _m(String workerId, String day, double? units, {DateTime? at}) => AttendanceMark(
    id: '$workerId$day', projectId: 'p', workerId: workerId, day: day, units: units, recordedBy: 'u',
    updatedAt: at ?? DateTime(2026, 11, 8));

void main() {
  final suresh = _w('w1', 'Suresh', role: 'mason', wage: 900);
  final ramesh = _w('w2', 'Ramesh', role: 'Helper', wage: 550.5);
  final lakshmi = _w('w3', 'Lakshmi', role: 'helper', wage: 500);
  final old = _w('w4', 'Old hand', role: 'Carpenter', status: 'inactive');
  final workers = [suresh, ramesh, lakshmi, old];

  group('wage sheet with marks', () {
    final from = DateTime(2026, 11, 2); // Monday
    final to = DateTime(2026, 11, 9);

    test('a mark replaces the punches of its day, and marks alone count too', () {
      final sheet = buildWageSheet(
        workers: workers,
        punches: [
          // A full day of punches, but marked as double (worked through the night).
          _punch('w1', 'Suresh', DateTime(2026, 11, 3, 8), out: DateTime(2026, 11, 3, 17)),
          // An open punch: half a day and flagged, unless a mark settles it.
          _punch('w1', 'Suresh', DateTime(2026, 11, 4, 8)),
        ],
        expenses: const [],
        marks: [
          _m('w1', '2026-11-03', 2),
          _m('w1', '2026-11-04', 1),
          _m('w2', '2026-11-05', 0.25),
          _m('w2', '2026-11-06', 1.5),
          _m('w2', '2026-11-07', null), // cleared: back to punches (none)
          _m('w3', '2026-11-01', 1), // the Sunday before: earned before this week
        ],
        from: from,
        to: to,
      );
      final s = sheet.lines.firstWhere((l) => l.name == 'Suresh');
      expect(s.days, 3);
      expect(s.hours, 9);
      expect(s.missingPunchOuts, 0); // the mark settled the open punch
      expect(s.markedDays, 2);
      expect(s.earned, 2700);

      final r = sheet.lines.firstWhere((l) => l.name == 'Ramesh');
      expect(r.days, 1.75);
      expect(r.earned, closeTo(963.375, 1e-9)); // paise wages stay exact
      expect(r.markedDays, 2);

      final l = sheet.lines.firstWhere((l) => l.name == 'Lakshmi');
      expect(l.days, 0);
      expect(l.balanceDue, 500); // owed from before the week
    });

    test('without marks the sheet is as before', () {
      final sheet = buildWageSheet(
        workers: workers,
        punches: [_punch('w1', 'Suresh', DateTime(2026, 11, 3, 8), out: DateTime(2026, 11, 3, 12))],
        expenses: const [],
        from: from,
        to: to,
      );
      expect(sheet.lines.firstWhere((l) => l.name == 'Suresh').days, 0.5);
    });

    test('the calendar agrees with the wage sheet', () {
      final m = buildWorkerMonth(
        [_punch('w1', 'Suresh', DateTime(2026, 11, 4, 8))],
        suresh,
        DateTime(2026, 11, 15),
        marks: [_m('w1', '2026-11-04', 1), _m('w1', '2026-11-10', 3), _m('w1', '2026-10-31', 1)],
      );
      expect(m.daysWorked, 4);
      expect(m.days[10]!.marked, 3);
      expect(m.missedPunchOuts, 0);
      expect(m.days.containsKey(31), isFalse);
    });

    test('labels', () {
      expect(markUnits.map(markLabel), ['A', '¼', '½', '1', '1½', '2×', '3×']);
      expect(markDay(DateTime(2026, 1, 5)), '2026-01-05');
    });
  });

  group('register and headcount', () {
    final day = DateTime(2026, 11, 8);

    test('every active worker, in trade order, with punches and marks', () {
      final rows = buildRegister(
        workers: workers,
        punches: [_punch('w1', 'Suresh', DateTime(2026, 11, 8, 8), out: DateTime(2026, 11, 8, 16))],
        marks: [_m('w2', '2026-11-08', 0.5), _m('w3', '2026-11-08', 0), _m('w3', '2026-11-07', 1)],
        day: day,
      );
      expect(rows.map((r) => r.worker.name), ['Lakshmi', 'Ramesh', 'Suresh']); // Helper, Helper, Mason; inactive left out
      final s = rows.last;
      expect(s.punched, isTrue);
      expect(s.fromPunches, 1);
      expect(s.marked, isNull);
      expect(s.cost, 900);
      expect(rows[1].units, 0.5);
      expect(rows.first.present, isFalse); // marked absent

      final heads = headcountByTrade(rows);
      expect(heads.map((t) => (t.trade, t.people, t.days)), [('Helper', 1, 0.5), ('Mason', 1, 1.0)]);
    });

    test('an inactive worker shows up on a day they were marked', () {
      final rows = buildRegister(workers: workers, punches: const [], marks: [_m('w4', '2026-11-08', 1)], day: day);
      expect(rows.map((r) => r.worker.name), contains('Old hand'));
      expect(tradeOf(_w('x', 'x', role: '  ')), 'Other');
    });

    test('people punched in by a typed name are counted once', () {
      final punches = [
        LabourAttendanceData(id: 'a', projectId: 'p', workerName: 'Venkat', recordedBy: 'u', punchIn: DateTime(2026, 11, 8, 8), createdAt: day),
        LabourAttendanceData(id: 'b', projectId: 'p', workerName: 'venkat ', recordedBy: 'u', punchIn: DateTime(2026, 11, 8, 14), createdAt: day),
        LabourAttendanceData(id: 'c', projectId: 'p', workerName: 'Suresh', recordedBy: 'u', punchIn: DateTime(2026, 11, 8, 8), createdAt: day),
        LabourAttendanceData(id: 'd', projectId: 'p', workerName: 'Other day', recordedBy: 'u', punchIn: DateTime(2026, 11, 7, 8), createdAt: day),
      ];
      expect(unlistedPunched(workers, punches, day), 1);
    });
  });

  group('on the phone and in sync', () {
    test('one row per worker per day, the same id on every phone, queued as an upsert', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final a = await db.attendanceDao.setMark(projectId: 'p', workerId: 'w1', day: '2026-11-08', units: 1, by: 'u');
      final b = await db.attendanceDao.setMark(projectId: 'p', workerId: 'w1', day: '2026-11-08', units: 1.5, by: 'u2');
      expect(a.id, b.id);
      expect(a.id, AttendanceDao.markId('p', 'w1', '2026-11-08'));
      expect(AttendanceDao.markId('p', 'w1', '2026-11-09'), isNot(a.id));
      final all = await db.attendanceDao.marksForProject('p');
      expect(all.single.units, 1.5);
      expect(all.single.recordedBy, 'u2');

      final queued = await db.syncOutboxDao.pending();
      expect(queued.map((o) => (o.targetTable, o.operation)).toSet(), {('site_attendance_marks', 'upsert')});
      final json = jsonDecode(queued.last.payload) as Map<String, dynamic>;
      expect(json['units'], 1.5);
      expect(json['day'], '2026-11-08');
      expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(json['id'] as String), isTrue);

      await db.attendanceDao.setMark(projectId: 'p', workerId: 'w1', day: '2026-11-08', units: null, by: 'u');
      expect((await db.attendanceDao.marksForProject('p')).single.units, isNull);
    });

    test('a teammate\'s older mark doesn\'t replace a newer one here', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final mine = await db.attendanceDao.setMark(
          projectId: 'p', workerId: 'w1', day: '2026-11-08', units: 1, by: 'u', now: DateTime(2026, 11, 8, 18));
      final json = attendanceMarkToSupabaseJson(mine);
      await db.attendanceDao.upsertMarkFromRemote(attendanceMarkFromSupabaseJson(
          {...json, 'units': 0.5, 'updated_at': DateTime(2026, 11, 8, 9).toUtc().toIso8601String()}));
      expect((await db.attendanceDao.marksForProject('p')).single.units, 1);
      await db.attendanceDao.upsertMarkFromRemote(attendanceMarkFromSupabaseJson(
          {...json, 'units': 2, 'updated_at': DateTime(2026, 11, 8, 20).toUtc().toIso8601String()}));
      expect((await db.attendanceDao.marksForProject('p')).single.units, 2);
    });
  });

  testWidgets('the register: tap to mark, the headcount follows, and the rest marked in one tap', (tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      for (final w in [suresh, ramesh, lakshmi]) {
        await db.workerDao.create(WorkersCompanion.insert(
            id: w.id, projectId: 'p', name: w.name, role: Value(w.role), dailyWage: Value(w.dailyWage)));
      }
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: DayRegisterScreen(projectId: 'p', userId: 'u', now: DateTime(2026, 11, 8, 10)),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    await settle();
    String headcount() => tester.widget<Text>(find.byKey(const Key('register-headcount'))).data!;
    expect(headcount(), '0 on site');
    expect(find.text('HELPER'), findsOneWidget);
    expect(find.text('MASON'), findsOneWidget);

    await tester.tap(find.byKey(const Key('mark-w1-2.0')));
    await settle();
    expect(headcount(), '1 on site');
    expect(find.text('Marked: Double'), findsOneWidget);
    expect(find.text('₹1,800'), findsOneWidget);

    await tester.tap(find.byKey(const Key('register-rest-present')));
    await settle();
    expect(headcount(), '3 on site');
    expect(find.textContaining('4 days of pay · ₹2,850.50'), findsOneWidget);
    expect(find.text('Helper 2'), findsOneWidget);

    // Tapping the chosen mark again goes back to the punches (none here).
    await tester.tap(find.byKey(const Key('mark-w1-2.0')));
    await settle();
    expect(headcount(), '2 on site');
    final marks = await tester.runAsync(() => db.attendanceDao.marksForProject('p'));
    expect(marks!.firstWhere((m) => m.workerId == 'w1').units, isNull);
    expect(tester.takeException(), isNull);
  });
}
