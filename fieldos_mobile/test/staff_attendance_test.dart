/// Selfie and geofence attendance: inside the site a check-in counts at
/// once, away from it it needs a reason and a manager's OK, nobody approves
/// their own day, the month's days feed the salary, and photos sync with
/// the punches.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/attendance/staff_attendance.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

void main() {
  late AppDatabase db;
  late String companyId;
  // Narapally's centre and a 100 m fence.
  final fence = ProjectGeofence(projectId: 'a', centerLat: 17.4500, centerLng: 78.3800, radiusMeters: 100, updatedAt: DateTime(2026));
  const insideLat = 17.4503, insideLng = 78.3801; // about 35 m
  const awayLat = 17.4600, awayLng = 78.3800; // about 1.1 km

  setUp(() async {
    db = AppDatabase.memory();
    companyId = (await db.companyDao.create('Sai Constructions')).id;
    await db.projectDao.create(ProjectsCompanion.insert(id: 'a', companyId: companyId, name: 'Narapally', status: const Value('active')));
    await db.projectDao.create(ProjectsCompanion.insert(id: 'b', companyId: companyId, name: 'Kompally', status: const Value('active')));
  });
  tearDown(() => db.close());

  StaffAttendanceDao dao() => db.staffAttendanceDao;

  test('geofence: inside, outside, no fix, no site location, nearest site', () {
    final inside = geoCheck(insideLat, insideLng, fence);
    expect(inside.within, isTrue);
    expect(inside.distanceM, closeTo(35, 5));
    final away = geoCheck(awayLat, awayLng, fence);
    expect(away.within, isFalse);
    expect(away.distanceM, closeTo(1112, 10));
    expect(geoCheck(null, null, fence).within, isNull);
    expect(geoCheck(insideLat, insideLng, null).distanceM, isNull);
    final other = ProjectGeofence(projectId: 'b', centerLat: 17.5400, centerLng: 78.4900, radiusMeters: 150, updatedAt: DateTime(2026));
    expect(nearestSite(insideLat, insideLng, {'a': fence, 'b': other})!.$1, 'a');
    expect(nearestSite(insideLat, insideLng, {}), isNull);
    expect(distanceText(38.4), '38 m');
    expect(distanceText(2420), '2.4 km');
  });

  test('a check-in inside the site counts at once, with its selfie queued first', () async {
    final at = DateTime(2026, 11, 10, 9, 5);
    final r = await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/selfie_1.jpg', fence: fence,
        lat: insideLat, lng: insideLng, accuracyM: 12, now: at);
    expect(r.status, 'ok');
    expect(r.withinGeofence, isTrue);
    expect(r.day, '2026-11-10');
    expect(r.inAccuracyM, 12);
    final photo = await dao().photoById(r.inPhotoId);
    expect(photo!.filePath, '/m/selfie_1.jpg');
    expect(photo.takenBy, 'u1');
    final queued = [for (final o in await db.syncOutboxDao.pending()) if (o.targetTable != 'projects') o];
    expect([for (final o in queued) o.targetTable], ['attendance_photos', 'staff_attendance']);
    final photoJson = jsonDecode(queued.first.payload) as Map<String, dynamic>;
    expect(photoJson['file_path'], 'a/attendance/${photo.id}.jpg');
    expect(photoJson['_local_file_path'], '/m/selfie_1.jpg');
  });

  test('away from the site, without a fix or without a site location: a reason, then it waits', () async {
    expect(
        () => dao().checkIn(companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence, lat: awayLat, lng: awayLng),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('away from the site'))));
    expect(() => dao().checkIn(companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: null, fence: fence),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('selfie'))));
    final away = await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence,
        lat: awayLat, lng: awayLng, reason: ' At the supplier\'s yard ');
    expect(away.status, 'pending');
    expect(away.reason, 'At the supplier\'s yard');
    expect(away.inDistanceM, greaterThan(1000));
    final noSite = await dao().checkIn(
        companyId: companyId, projectId: 'b', userId: 'u1', selfiePath: '/m/s2.jpg', fence: null,
        lat: insideLat, lng: insideLng, reason: 'Site office');
    expect(noSite.status, 'pending');
    expect(noSite.withinGeofence, isNull);
  });

  test('one check-in a site a day; check-out after check-in, once', () async {
    final at = DateTime(2026, 11, 10, 9);
    final r = await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence, lat: insideLat, lng: insideLng, now: at);
    expect(
        () => dao().checkIn(
            companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence, lat: insideLat, lng: insideLng,
            now: at.add(const Duration(hours: 1))),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('already checked in'))));
    expect(() => dao().checkOut(r.id, fence: fence, now: at), throwsArgumentError);
    final out = await dao().checkOut(r.id,
        fence: fence, selfiePath: '/m/out.jpg', lat: awayLat, lng: awayLng, now: at.add(const Duration(hours: 9, minutes: 30)));
    expect(out.checkOut, at.add(const Duration(hours: 9, minutes: 30)));
    expect(out.outWithin, isFalse);
    expect(out.outPhotoId, isNotNull);
    expect(out.status, 'ok', reason: 'leaving from elsewhere does not undo the day');
    expect(hoursOnSite(out), 9.5);
    expect(() => dao().checkOut(r.id, fence: fence), throwsArgumentError);
    expect(
        () => dao().checkIn(
            companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence, lat: insideLat, lng: insideLng,
            now: at.add(const Duration(hours: 11))),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('in and out'))));
  });

  test('a manager approves or turns down; nobody approves their own day', () async {
    final r = await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence, lat: awayLat, lng: awayLng,
        reason: 'Meeting the client');
    expect(() => dao().review(r.id, approve: true, by: 'u1'), throwsArgumentError);
    final ok = await dao().review(r.id, approve: true, by: 'boss', now: DateTime(2026, 11, 10, 18));
    expect(ok.status, 'approved');
    expect(ok.reviewedBy, 'boss');
    final no = await dao().review(r.id, approve: false, by: 'boss', note: 'Not on the site plan');
    expect(no.status, 'rejected');
    expect(no.reviewNote, 'Not on the site plan');
    final ops = [for (final o in await db.syncOutboxDao.pending()) if (o.targetTable == 'staff_attendance') o.operation];
    expect(ops, ['insert', 'update', 'update']);
  });

  test('the month: days at work, waiting, turned down, and paid Sundays', () async {
    StaffAttendanceData row(String day, String status) => StaffAttendanceData(
        id: day + status, companyId: 'c', projectId: 'a', userId: 'u', day: day, checkIn: DateTime.parse('${day}T09:00:00'),
        status: status, createdAt: DateTime(2026));
    final rows = [
      row('2026-11-02', 'ok'),
      row('2026-11-03', 'approved'),
      row('2026-11-03', 'pending'), // a second site the same day
      row('2026-11-04', 'pending'),
      row('2026-11-05', 'rejected'),
      row('2026-11-08', 'ok'), // a Sunday worked
      row('2026-10-30', 'ok'), // last month
    ];
    final m = staffMonth(rows, '2026-11', now: DateTime(2026, 11, 20));
    expect(m.present, 3);
    expect(m.waiting, 1);
    expect(m.notApproved, 1);
    // Sundays up to the 20th: 1, 8, 15; the 8th was worked.
    expect(m.weeklyOffs, 2);
    expect(m.paidDays, 5);
    expect(m.hasAny, isTrue);
    final joined = staffMonth(rows, '2026-11', now: DateTime(2026, 12, 2), joinedOn: DateTime(2026, 11, 10));
    expect(joined.weeklyOffs, 3, reason: 'the 15th, 22nd and 29th, not the 1st before joining');
    expect(staffMonth(const [], '2026-11', now: DateTime(2026, 11, 20)).hasAny, isFalse);
  });

  test('sync: staff attendance round trips; punches leave out photo fields they lack', () async {
    final r = await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/s.jpg', fence: fence, lat: awayLat, lng: awayLng,
        accuracyM: 8, reason: 'Yard', now: DateTime(2026, 11, 10, 9));
    final json = staffAttendanceToSupabaseJson(r);
    expect(json['day'], '2026-11-10');
    final back = staffAttendanceFromSupabaseJson({...json, 'day': '2026-11-10'});
    expect(back.status.value, 'pending');
    expect(back.inDistanceM.value, r.inDistanceM);
    expect(back.checkIn.value, r.checkIn);

    final punch = await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
        id: 'p1', projectId: 'a', workerName: 'Raju', recordedBy: 'u1', punchIn: DateTime(2026, 11, 10, 8)));
    expect(attendanceToSupabaseJson(punch).containsKey('photo_id'), isFalse,
        reason: 'old servers without the new columns still take plain punches');
    final photo = await dao().addPhoto(projectId: 'a', filePath: '/m/roll.jpg', by: 'u1');
    final withPhoto = await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
        id: 'p2', projectId: 'a', workerName: 'Ravi', recordedBy: 'u1', punchIn: DateTime(2026, 11, 10, 8),
        photoId: Value(photo.id), distanceM: const Value(240)));
    final pj = attendanceToSupabaseJson(withPhoto);
    expect(pj['photo_id'], photo.id);
    expect(pj['distance_m'], 240);
    expect(attendanceFromSupabaseJson(pj).photoId.value, photo.id);
  });

  test('a salary links to one login, and editing keeps the link', () async {
    final p = db.payrollDao;
    final anil = await p.addStaff(companyId: companyId, name: 'Anil', basic: 18000, userId: 'login-anil');
    expect(anil.userId, 'login-anil');
    expect(() => p.addStaff(companyId: companyId, name: 'Bala', basic: 15000, userId: 'login-anil'),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('Anil'))));
    await p.updateStaff(anil.id, name: 'Anil Kumar', basic: 19000);
    expect((await p.staffById(anil.id))!.userId, 'login-anil');
    await p.updateStaff(anil.id, name: 'Anil Kumar', basic: 19000, userId: const Value(null));
    expect((await p.staffById(anil.id))!.userId, isNull);
    expect(staffMemberToSupabaseJson((await p.staffById(anil.id))!).containsKey('user_id'), isFalse);
  });

  test('reports: check-ins and days per person, for managers only', () async {
    final staff = await db.payrollDao.addStaff(companyId: companyId, name: 'Anil', basic: 18000, userId: 'u1');
    expect(staff.userId, 'u1');
    await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/1.jpg', fence: fence, lat: insideLat, lng: insideLng,
        now: DateTime(2026, 11, 3, 9));
    await dao().checkIn(
        companyId: companyId, projectId: 'a', userId: 'u1', selfiePath: '/m/2.jpg', fence: fence, lat: awayLat, lng: awayLng,
        reason: 'Yard', now: DateTime(2026, 11, 4, 9));
    final sites = await db.projectDao.forCompany(companyId);
    Future<ReportInput> input(bool manager) => loadReportInput(db,
        companyId: companyId, sites: sites, from: DateTime(2026, 11), to: DateTime(2026, 12), manager: manager, moneyIn: manager,
        now: DateTime(2026, 11, 20));
    final d = await input(true);
    final checkins = reportById('staff-checkins')!.build(d);
    expect(checkins.rows, hasLength(2));
    expect(checkins.rows.first.sublist(1, 3), ['Anil', 'Narapally']);
    expect(checkins.rows.last[7], 'Waiting for OK');
    expect(reportById('staff-days')!.build(d).rows.single, ['Anil', 1.0, 1.0]);
    expect(reportById('staff-days')!.build(await input(false)).rows, isEmpty);
  });
}
