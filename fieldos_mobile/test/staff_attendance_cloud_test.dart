/// Selfie attendance against the local Supabase stack (skips itself when it
/// is not running). An engineer checks in with a selfie at the site and
/// away from it; the server works out "inside" itself, so a changed app
/// cannot mark itself inside or approved; nobody approves their own day;
/// the owner approves from their phone; people see only their own days.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  String selfie(CloudPhone p, String name) {
    final f = File('${p.filesDir.path}/$name.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);
    return f.path;
  }

  test('check in with a selfie; the server decides inside, and the owner approves', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('att-owner');
    final engineer = await CloudPhone.signUp('att-engineer');
    addTearDown(() async {
      for (final p in [owner, engineer]) {
        await p.close();
      }
    });

    final company = await owner.db.companyDao.create('Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    await engineer.service.joinCompany(cloud.joinCode!);
    final siteId = uuid.v4();
    await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: siteId, companyId: company.id, name: 'Narapally', status: const Value('active')));
    await owner.db.geofenceDao.set(siteId, 17.4500, 78.3800, 100);
    await pushAll(owner);

    // --- The engineer at the gate, then a day at the yard -------------------
    await engineer.engine.pullAll();
    final fence = await engineer.db.geofenceDao.effectiveFor(siteId);
    expect(fence, isNotNull);
    final ed = engineer.db.staffAttendanceDao;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final inside = await ed.checkIn(
        companyId: company.id, projectId: siteId, userId: engineer.localUserId, selfiePath: selfie(engineer, 'in'),
        fence: fence, lat: 17.4503, lng: 78.3801, accuracyM: 9);
    final away = await ed.checkIn(
        companyId: company.id, projectId: siteId, userId: engineer.localUserId, selfiePath: selfie(engineer, 'yard'),
        fence: fence, lat: 17.4600, lng: 78.3800, reason: 'Steel at the yard', now: yesterday);
    await pushAll(engineer);

    final admin = adminClient();
    final rIn = await admin.from('staff_attendance').select().eq('id', inside.id).single();
    expect(rIn['user_id'], engineer.remoteUserId);
    expect(rIn['status'], 'ok');
    expect(rIn['within_geofence'], isTrue);
    final rAway = await admin.from('staff_attendance').select().eq('id', away.id).single();
    expect(rAway['status'], 'pending');
    expect((rAway['in_distance_m'] as num).toDouble(), greaterThan(1000));
    final photo = await admin.from('attendance_photos').select().eq('id', inside.inPhotoId!).single();
    expect(photo['file_path'], '$siteId/attendance/${inside.inPhotoId}.jpg');
    expect(photo['taken_by'], engineer.remoteUserId);
    final stored = await admin.storage.from('documents').download(photo['file_path'] as String);
    expect(stored, isNotEmpty);

    // --- A changed app cannot mark itself inside or approved ----------------
    final forged = await engineer.client.from('staff_attendance').insert({
      'id': uuid.v4(), 'company_id': company.id, 'project_id': siteId, 'user_id': owner.remoteUserId,
      'day': '2026-01-05', 'check_in': '2026-01-05T09:00:00Z', 'in_lat': 17.70, 'in_lng': 78.38,
      'within_geofence': true, 'status': 'approved',
    }).select('user_id, status, within_geofence').single();
    expect(forged['user_id'], engineer.remoteUserId, reason: 'a check-in is always your own');
    expect(forged['status'], 'pending');
    expect(forged['within_geofence'], isFalse);

    // Nobody approves their own day, or moves where they checked in.
    await expectLater(engineer.client.from('staff_attendance').update({'status': 'approved'}).eq('id', away.id).select(),
        throwsA(isA<PostgrestException>()));
    await expectLater(engineer.client.from('staff_attendance').update({'in_lat': 17.4501}).eq('id', away.id).select(),
        throwsA(isA<PostgrestException>()));

    // --- Check-out from the phone -------------------------------------------
    await ed.checkOut(inside.id, fence: fence, selfiePath: selfie(engineer, 'out'), lat: 17.4501, lng: 78.3800,
        now: DateTime.now().add(const Duration(seconds: 1)));
    await pushAll(engineer);
    final rOut = await admin.from('staff_attendance').select('check_out, out_within, status').eq('id', inside.id).single();
    expect(rOut['check_out'], isNotNull);
    expect(rOut['out_within'], isTrue);

    // --- The owner approves the yard day; it reaches the engineer -----------
    await owner.engine.pullAll();
    final od = owner.db.staffAttendanceDao;
    final seen = await od.forCompany(company.id);
    expect(seen.map((r) => r.id), containsAll([inside.id, away.id]));
    expect((await od.photoById(inside.inPhotoId))?.filePath, isNotNull, reason: 'the selfie came down with it');
    await od.review(away.id, approve: true, by: owner.localUserId, note: 'OK, steel came');
    await pushAll(owner);
    final rOk = await admin.from('staff_attendance').select('status, reviewed_by, review_note').eq('id', away.id).single();
    expect(rOk['status'], 'approved');
    expect(rOk['reviewed_by'], owner.remoteUserId);
    // The owner cannot check the engineer out.
    await expectLater(
        owner.client.from('staff_attendance').update({'check_out': DateTime.now().toUtc().toIso8601String()}).eq('id', away.id).select(),
        throwsA(isA<PostgrestException>()));

    await engineer.engine.pullAll();
    expect((await ed.byId(away.id))!.status, 'approved');

    // --- People see only their own days -------------------------------------
    final ownDay = await od.checkIn(
        companyId: company.id, projectId: siteId, userId: owner.localUserId, selfiePath: selfie(owner, 'owner'),
        fence: fence, lat: 17.4502, lng: 78.3800);
    await pushAll(owner);
    final engineerSees = await engineer.client.from('staff_attendance').select('id');
    expect(engineerSees.map((r) => r['id']), isNot(contains(ownDay.id)));
    expect(engineerSees.map((r) => r['id']), contains(away.id));
  });
}
