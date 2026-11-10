/// Upgrading to schema v24 adds selfie attendance and keeps a phone's
/// punches and salary list.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v23 -> v24 upgrade adds photos, staff check-ins and logins, and keeps old punches', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v24');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    final company = await db.companyDao.create('Sai Constructions');
    await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
        id: 'old', projectId: 'p', workerName: 'Raju', recordedBy: 'u', punchIn: DateTime(2026, 11, 1, 8), withinGeofence: const Value(true)));
    final staff = await db.payrollDao.addStaff(companyId: company.id, name: 'Anil', basic: 18000);
    await db.customStatement('DROP TABLE attendance_photos');
    await db.customStatement('DROP TABLE staff_attendance');
    for (final c in ['photo_id', 'distance_m', 'accuracy_m']) {
      await db.customStatement('ALTER TABLE labour_attendance DROP COLUMN $c');
    }
    await db.customStatement('ALTER TABLE staff_members DROP COLUMN user_id');
    await db.customStatement('PRAGMA user_version = 23');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final old = (await db.attendanceDao.forProject('p')).single;
    expect(old.workerName, 'Raju');
    expect(old.photoId, isNull);
    expect((await db.payrollDao.staffById(staff.id))!.userId, isNull);
    final r = await db.staffAttendanceDao.checkIn(
        companyId: company.id, projectId: 'p', userId: 'u', selfiePath: '/m/s.jpg', fence: null, reason: 'Office');
    expect(r.status, 'pending');
    expect((await db.staffAttendanceDao.photoById(r.inPhotoId))!.filePath, '/m/s.jpg');
  });
}
