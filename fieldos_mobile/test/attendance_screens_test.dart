/// Selfie attendance on a phone: an engineer at the site checks in with a
/// selfie and out again; away from the site they give a reason and the day
/// waits; the owner approves it from Staff attendance; the salary sheet
/// offers the days from attendance; Telugu on a 320 px phone fits.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/attendance/attendance_camera.dart';
import 'package:fieldos_mobile/features/attendance/attendance_screens.dart';
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart' show monthKey;
import 'package:fieldos_mobile/features/payroll/payroll_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/location_service.dart';

class _FakeLocation extends LocationService {
  _FakeLocation(this.fix);
  LocationFix? fix;
  @override
  Future<LocationFix> currentFix() async => fix ?? (throw const LocationUnavailable('Location is turned off.'));
}

class _FakeCamera implements AttendanceCamera {
  final taken = <bool>[];
  @override
  Future<String?> take({required bool selfie, String? place, LocationFix? fix}) async {
    taken.add(selfie);
    return '/tmp/fieldos-test-selfie-${taken.length}.jpg';
  }
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));
  const inside = LocationFix(17.4503, 78.3801, 10);
  const away = LocationFix(17.4600, 78.3800, 10);

  Future<(ProviderContainer, AppDatabase, String, String, _FakeLocation, _FakeCamera)> setUpCompany(WidgetTester tester,
      {LocationFix? fix}) async {
    final db = AppDatabase.memory();
    final location = _FakeLocation(fix);
    final camera = _FakeCamera();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      locationServiceProvider.overrideWithValue(location),
      attendanceCameraProvider.overrideWithValue(camera),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String companyId, userId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      userId = container.read(sessionProvider).user!.id;
      for (final (id, name) in [('p-1', 'Narapally'), ('p-2', 'Kompally')]) {
        await db.projectDao.create(ProjectsCompanion.insert(id: id, companyId: companyId, name: name, status: const Value('active')));
      }
      await db.geofenceDao.set('p-1', 17.4500, 78.3800, 100);
      await db.geofenceDao.set('p-2', 17.5400, 78.4900, 150);
    });
    return (container, db, companyId, userId, location, camera);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home, {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await settle(tester);
  }

  Future<List<StaffAttendanceData>> rows(WidgetTester tester, AppDatabase db, String companyId) async =>
      (await tester.runAsync(() => db.staffAttendanceDao.forCompany(companyId)))!;

  testWidgets('at the site: the nearest site is chosen, check in with a selfie, then out', (tester) async {
    final (container, db, companyId, userId, _, camera) = await setUpCompany(tester, fix: inside);
    await pumpApp(tester, container, MyAttendanceScreen(companyId: companyId, userId: userId));
    expect(find.text('Narapally'), findsOneWidget);
    expect(find.textContaining('from the site'), findsOneWidget);

    await tester.tap(find.byKey(const Key('check-in')));
    await settle(tester);
    expect(camera.taken, [true], reason: 'a selfie, from the front camera');
    final r = (await rows(tester, db, companyId)).single;
    expect(r.status, 'ok');
    expect(r.projectId, 'p-1');
    expect(find.byKey(const Key('check-out')), findsOneWidget);
    expect(find.text('At site'), findsWidgets);

    await tester.tap(find.byKey(const Key('check-out')));
    await settle(tester);
    expect((await rows(tester, db, companyId)).single.checkOut, isNotNull);
    expect(camera.taken, [true, true]);
    expect(find.textContaining('Checked out of Narapally'), findsOneWidget);
    expect(find.byKey(const Key('check-in')), findsOneWidget, reason: 'they can still check in at another site');
  });

  testWidgets('away from the site: a reason, and the day waits for an OK', (tester) async {
    final (container, db, companyId, userId, _, _) = await setUpCompany(tester, fix: away);
    await pumpApp(tester, container, MyAttendanceScreen(companyId: companyId, userId: userId));
    await tester.tap(find.byKey(const Key('check-in')));
    await settle(tester);
    expect(find.byKey(const Key('checkin-reason')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('checkin-reason')), 'Collecting steel at the yard');
    await tester.tap(find.byKey(const Key('reason-save')));
    await settle(tester);
    final r = (await rows(tester, db, companyId)).single;
    expect(r.status, 'pending');
    expect(r.reason, 'Collecting steel at the yard');
    expect(find.textContaining('waiting for OK'), findsOneWidget);
  });

  testWidgets('the owner approves a day from Staff attendance, and the salary offers the days', (tester) async {
    final (container, db, companyId, userId, _, _) = await setUpCompany(tester);
    late StaffMember ravi;
    late StaffAttendanceData pending;
    final now = DateTime.now();
    await tester.runAsync(() async {
      ravi = await db.payrollDao.addStaff(companyId: companyId, name: 'Ravi Teja', basic: 20000, userId: 'login-ravi');
      pending = await db.staffAttendanceDao.checkIn(
          companyId: companyId, projectId: 'p-2', userId: 'login-ravi', selfiePath: '/tmp/none.jpg',
          fence: await db.geofenceDao.effectiveFor('p-2'), lat: away.lat, lng: away.lng, reason: 'Client meeting');
    });
    await pumpApp(tester, container, StaffAttendanceScreen(companyId: companyId, userId: userId));
    expect(find.textContaining('Ravi Teja'), findsOneWidget, reason: 'today, by the name on the salary list');
    await tester.tap(find.text('Waiting'));
    await settle(tester);
    expect(find.text('“Client meeting”'), findsOneWidget);
    await tester.tap(find.byKey(Key('approve-${pending.id}')));
    await settle(tester);
    expect((await rows(tester, db, companyId)).single.status, 'approved');
    expect(find.text('Nothing is waiting for your OK.'), findsOneWidget);

    // The month's payslip offers the days from attendance.
    await tester.runAsync(() => db.payrollDao.makeMonth(companyId, monthKey(now), by: userId));
    final line = (await tester.runAsync(() => db.payrollDao.linesForMonth(companyId, monthKey(now))))!.single;
    final data = (await tester.runAsync(() => container.read(payrollDataProvider(companyId).future)))!;
    await pumpApp(tester, container,
        Scaffold(body: PayslipSheet(line: line, staff: ravi, data: data, companyId: companyId, userId: userId)));
    expect(find.byKey(const Key('slip-use-attendance')), findsOneWidget);
    await tester.tap(find.byKey(const Key('slip-use-attendance')));
    await tester.pump();
    final days = tester.widget<TextField>(find.byKey(const Key('slip-days'))).controller!.text;
    expect(double.parse(days), greaterThanOrEqualTo(1));
  });

  testWidgets('Telugu on a 320 px phone fits both screens', (tester) async {
    setCurrentLanguage(AppLanguage.te);
    final (container, db, companyId, userId, _, _) = await setUpCompany(tester, fix: away);
    await tester.runAsync(() async {
      await db.staffAttendanceDao.checkIn(
          companyId: companyId, projectId: 'p-1', userId: 'login-ravi', selfiePath: '/tmp/none.jpg',
          fence: await db.geofenceDao.effectiveFor('p-1'), lat: away.lat, lng: away.lng, reason: 'Yard');
    });
    await pumpApp(tester, container, MyAttendanceScreen(companyId: companyId, userId: userId), size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    await pumpApp(tester, container, StaffAttendanceScreen(companyId: companyId, userId: userId), size: const Size(320, 640));
    await tester.tap(find.byType(Tab).at(1));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
