/// Read-only mode (lib/data/write_guard.dart) refuses the person's own
/// changes, never what sync needs to catch the phone up.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';

const uuid = Uuid();

void main() {
  late AppDatabase db;
  late Directory dir;
  setUp(() {
    db = AppDatabase.memory();
    dir = Directory.systemTemp.createTempSync('fieldos-hunt-ro-');
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('a read-only phone still queues its photos from before sync, so starting sync does not fail', () async {
    final project = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Old site', status: const Value('active')));
    final dpr = await db.dprDao.create(DprEntriesCompanion.insert(
        id: uuid.v4(), projectId: project.id, createdBy: 'me', entryDate: DateTime(2026, 11, 1), workSummary: 'x'));
    final photo = File('${dir.path}/old.jpg')..writeAsBytesSync([1, 2, 3]);
    await db.into(db.dprPhotos).insert(DprPhotosCompanion.insert(id: uuid.v4(), dprEntryId: dpr.id, photoPath: photo.path));
    final before = await db.syncOutboxDao.pendingCount();

    // Offline for over 7 days, then back on the network: sync starts with
    // this step (CloudSyncBootstrap.ensureRunning).
    db.writeGuard.reason = ReadOnlyReason.offlineTooLong;
    expect(await db.queueFilesFromBeforeSync(), 1);
    expect(await db.syncOutboxDao.pendingCount(), before + 1);
    expect(await db.queueFilesFromBeforeSync(), 0, reason: 'only once');

    // The person's own changes are still refused.
    await expectLater(db.projectDao.setStatus(project.id, 'completed'), throwsA(isA<ReadOnlyModeException>()));
  });

  test('settings upserts are allowed and other upserts refused', () {
    expect(WriteGuard.changesData('INSERT INTO "app_settings" ("key", "value") VALUES (?, ?) '
        'ON CONFLICT("key") DO UPDATE SET "value" = excluded."value"'), isFalse);
    expect(WriteGuard.changesData('INSERT INTO "tasks" ("id") VALUES (?) ON CONFLICT("id") DO UPDATE SET "title" = ?'),
        isTrue);
    expect(WriteGuard.changesData('  \n  update or replace "issues" SET "status" = ?'), isTrue);
    expect(WriteGuard.changesData('VACUUM INTO ?'), isFalse);
    expect(WriteGuard.changesData('BEGIN TRANSACTION'), isFalse);
  });
}
