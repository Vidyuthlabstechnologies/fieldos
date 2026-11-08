import 'package:drift/drift.dart' hide Column, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/workers/worker_calendar.dart';
import 'package:fieldos_mobile/providers.dart';

/// A worker's attendance was only a list of punches; there was no way to
/// see their month, or settle "I came on the 14th".
void main() {
  final worker = Worker(
    id: 'w1',
    projectId: 'p',
    name: 'Ramesh',
    role: 'Mason',
    phone: null,
    dailyWage: 800,
    status: 'active',
    createdAt: DateTime(2026, 10, 1),
  );

  LabourAttendanceData punch(String id, DateTime inAt, DateTime? outAt, {String? workerId = 'w1', String name = 'Ramesh'}) =>
      LabourAttendanceData(
        id: id,
        projectId: 'p',
        workerName: name,
        workerId: workerId,
        recordedBy: 'u',
        punchIn: inAt,
        punchOut: outAt,
        lat: null,
        lng: null,
        withinGeofence: null,
        createdAt: inAt,
      );

  final punches = [
    punch('a', DateTime(2026, 11, 2, 8), DateTime(2026, 11, 2, 18)), // 10 h: full, 2 h overtime
    punch('b', DateTime(2026, 11, 3, 8), DateTime(2026, 11, 3, 12)), // 4 h: half
    punch('c', DateTime(2026, 11, 4, 8), null), // forgot to punch out: half, flagged
    punch('d', DateTime(2026, 11, 5, 8), DateTime(2026, 11, 5, 12)), // split shift on one day
    punch('e', DateTime(2026, 11, 5, 13), DateTime(2026, 11, 5, 17)),
    punch('f', DateTime(2026, 11, 6, 8), DateTime(2026, 11, 6, 16), workerId: null, name: ' ramesh '), // typed name
    punch('g', DateTime(2026, 11, 6, 8), DateTime(2026, 11, 6, 16), workerId: 'w2', name: 'Suresh'), // someone else
    punch('h', DateTime(2026, 10, 30, 8), DateTime(2026, 10, 30, 16)), // last month
  ];

  test('the month counts days the same way as the wage sheet', () {
    final m = buildWorkerMonth(punches, worker, DateTime(2026, 11, 20));
    expect(m.month, DateTime(2026, 11));
    expect(m.days.keys.toList()..sort(), [2, 3, 4, 5, 6]);
    expect(m.days[2]!.credit, 1);
    expect(m.days[2]!.overtime, 2);
    expect(m.days[3]!.credit, 0.5);
    expect(m.days[4]!.openPunch, isTrue);
    expect(m.days[4]!.credit, 0.5);
    expect(m.days[5]!.hours, 8);
    expect(m.days[5]!.credit, 1);
    expect(m.days[6]!.hours, 8, reason: 'the typed name matches, Suresh is not counted');
    expect(m.daysWorked, 4);
    expect(m.missedPunchOuts, 1);
    expect(fmtDays(m.daysWorked), '4');
    expect(fmtDays(4.5), '4.5');
    expect(buildWorkerMonth(punches, worker, DateTime(2026, 10, 1)).days.keys, [30]);
  });

  testWidgets('the calendar shows the month and moves back a month', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      for (final p in punches) {
        await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: p.id,
          projectId: 'p',
          workerName: p.workerName,
          workerId: Value(p.workerId),
          recordedBy: 'u',
          punchIn: p.punchIn,
          punchOut: Value(p.punchOut),
        ));
      }
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: WorkerCalendarScreen(worker: worker, now: DateTime(2026, 11, 20)),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('4 days worked'), findsOneWidget);
    expect(find.text('2.0 hours overtime'), findsOneWidget);
    expect(find.text('1 punch-outs missed'), findsOneWidget);
    expect(find.text('Earned ₹3,200'), findsOneWidget);
    expect(find.bySemanticsLabel('4, 0.0 h, no punch-out'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull,
        reason: 'no future months');

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('1 days worked'), findsOneWidget);
  });
}
