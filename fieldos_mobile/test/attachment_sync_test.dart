/// DPR photos and expense bills reach a teammate's phone (audit P1,
/// 2026-11-10), against the local Supabase stack (skips itself if it is not
/// running).
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  File fileOn(CloudPhone phone, String name, List<int> bytes) =>
      File('${phone.filesDir.path}/$name')..writeAsBytesSync(bytes);

  test("a DPR photo and an expense bill open on the second phone", () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final engineer = await CloudPhone.signUp('engineer');
    final company = await owner.db.companyDao.create('Evidence Co');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Plot 7', status: const Value('active')));
    expect((await owner.engine.pushPending()).failed, 0);
    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();

    // On site, the engineer files a report with a photo and pays for sand
    // with the bill photographed.
    final e = engineer.db;
    final dpr = await e.dprDao.create(DprEntriesCompanion.insert(
        id: uuid.v4(), projectId: project.id, createdBy: engineer.localUserId, entryDate: DateTime.utc(2026, 11, 10),
        workSummary: 'Plinth beam poured'));
    final photoBytes = List<int>.generate(4000, (i) => i % 251);
    final photo = await e.dprDao.addPhoto(DprPhotosCompanion.insert(
        id: uuid.v4(), dprEntryId: dpr.id, photoPath: fileOn(engineer, 'beam.jpg', photoBytes).path));
    final expense = await e.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: project.id, category: 'Material', amount: 6400, incurredOn: '2026-11-10',
        recordedBy: engineer.localUserId));
    final billBytes = '%PDF-1.4 sand bill'.codeUnits;
    final bill = await e.expenseDao.attach(expense.id, fileOn(engineer, 'sand-bill.pdf', billBytes).path);
    final push = await engineer.engine.pushPending();
    expect(push.failed, 0);
    expect(push.succeeded, 4, reason: 'report, photo, expense, bill');

    // The office phone pulls and can open both files.
    await owner.engine.pullAll();
    final photos = await owner.db.dprDao.photosFor(dpr.id);
    expect(photos.single.id, photo.id);
    expect(File(photos.single.photoPath).readAsBytesSync(), photoBytes);
    expect(photos.single.photoPath, startsWith(owner.filesDir.path), reason: "a path on the owner's phone, not the engineer's");
    final bills = await owner.db.expenseDao.attachmentsFor(expense.id);
    expect(bills.single.id, bill.id);
    expect(bills.single.mimeType, 'application/pdf');
    expect(File(bills.single.filePath).readAsBytesSync(), billBytes);

    // A second pull downloads nothing again and keeps the same rows.
    await owner.engine.pullAll();
    expect(await owner.db.dprDao.photosFor(dpr.id), hasLength(1));

    // Taking the bill off removes it from the server too.
    await e.expenseDao.removeAttachment(bill.id);
    expect((await engineer.engine.pushPending()).failed, 0);
    expect(await owner.client.from('expense_attachments').select().eq('id', bill.id), isEmpty);

    await owner.close();
    await engineer.close();
  });

  test('photos and bills taken before this version are queued once', () async {
    final db = AppDatabase.memory();
    final dir = Directory.systemTemp.createTempSync('fieldos-backfill-');
    final project = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Old site', status: const Value('active')));
    final dpr = await db.dprDao.create(DprEntriesCompanion.insert(
        id: uuid.v4(), projectId: project.id, createdBy: 'me', entryDate: DateTime.utc(2026, 11, 1), workSummary: 'x'));
    final expense = await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: project.id, category: 'Other', amount: 1, incurredOn: '2026-11-01', recordedBy: 'me'));
    // Written the old way: straight into the tables, nothing queued.
    final photoFile = File('${dir.path}/old.jpg')..writeAsBytesSync([1, 2, 3]);
    await db.into(db.dprPhotos).insert(DprPhotosCompanion.insert(id: uuid.v4(), dprEntryId: dpr.id, photoPath: photoFile.path));
    await db.into(db.dprPhotos).insert(
        DprPhotosCompanion.insert(id: uuid.v4(), dprEntryId: dpr.id, photoPath: '${dir.path}/deleted-since.jpg'));
    await db.into(db.expenseAttachments).insert(ExpenseAttachmentsCompanion.insert(
        id: uuid.v4(), expenseId: expense.id, filePath: photoFile.path, mimeType: 'image/jpeg'));
    final before = await db.syncOutboxDao.pendingCount();

    expect(await db.queueFilesFromBeforeSync(), 2, reason: 'the photo whose file is gone is skipped');
    expect(await db.syncOutboxDao.pendingCount(), before + 2);
    expect(await db.queueFilesFromBeforeSync(), 0, reason: 'only once');
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
