/// A photo that cannot go up on a weak link must not hold back the records
/// behind it (customer review, 26 Nov 2026), against the local Supabase stack
/// (skips itself if it is not running). On a stalled 3G upload the whole queue
/// used to stop at the photo, so a day's text records sat unsent behind it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

import 'support/cloud_phone.dart';

/// Storage uploads fail at the socket, as on a stalled mobile link; every
/// other request goes through.
class _StorageDown extends http.BaseClient {
  _StorageDown(this.inner);
  final http.Client inner;
  int storageTries = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path.contains('/storage/v1/')) {
      storageTries++;
      throw const SocketException('link dropped during upload');
    }
    return inner.send(request);
  }
}

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<({SyncEngine engine, _StorageDown link})> weakLink(CloudPhone phone) async {
    final link = _StorageDown(http.Client());
    final client = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey,
        httpClient: link, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    await client.auth.recoverSession(jsonEncode(phone.client.auth.currentSession!.toJson()));
    final engine = SyncEngine(db: phone.db, client: client, resolveDocumentsDirectory: () async => phone.filesDir)
      ..localUserId = phone.localUserId;
    return (engine: engine, link: link);
  }

  test('a photo that will not upload does not stop the records queued behind it', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final phone = await CloudPhone.signUp('weak');
    final company = await phone.db.companyDao.create('Weak Link Co');
    await phone.service.registerCompany(companyId: company.id, name: company.name);
    final project = await phone.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Plot 3', status: const Value('active')));
    expect((await phone.engine.pushPending()).failed, 0);

    // The evening's work, in the order it was saved: report, its photo, then more.
    final dpr = await phone.db.dprDao.create(DprEntriesCompanion.insert(
        id: uuid.v4(), projectId: project.id, createdBy: phone.localUserId, entryDate: DateTime.utc(2026, 11, 26),
        workSummary: 'Slab shuttering'));
    final photoFile = File('${phone.filesDir.path}/slab.jpg')..writeAsBytesSync(List<int>.generate(3000, (i) => i % 251));
    final photo = await phone.db.dprDao.addPhoto(DprPhotosCompanion.insert(
        id: uuid.v4(), dprEntryId: dpr.id, photoPath: photoFile.path));
    final task = await phone.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: project.id, title: 'Cure the plinth'));
    final expense = await phone.db.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: project.id, category: 'Material', amount: 1200, incurredOn: '2026-11-26',
        recordedBy: phone.localUserId));

    final weak = await weakLink(phone);
    final first = await weak.engine.pushPending();
    expect(weak.link.storageTries, greaterThan(0), reason: 'the photo was tried');
    expect(first.succeeded, 3, reason: 'report, task and expense go; only the photo waits');
    expect(await phone.client.from('tasks').select().eq('id', task.id), hasLength(1));
    expect(await phone.client.from('site_expenses').select().eq('id', expense.id), hasLength(1));
    expect(await phone.client.from('dpr_photos').select().eq('id', photo.id), isEmpty);

    // Being on a bad link must never park the photo or count a try against it.
    final waiting = await phone.db.syncOutboxDao.pending();
    expect(waiting.map((e) => e.recordId), [photo.id]);
    expect(waiting.single.retryCount, 0);
    expect(await phone.db.syncOutboxDao.parkedCount(), 0);
    expect(waiting.single.lastError, isNotNull, reason: 'Team & sync can say why');

    // Back on a good link the photo goes up on the next run.
    final second = await phone.engine.pushPending();
    expect(second.failed, 0);
    expect(await phone.client.from('dpr_photos').select().eq('id', photo.id), hasLength(1));
    expect(await phone.db.syncOutboxDao.pendingCount(), 0);

    await weak.engine.dispose();
    await phone.close();
  });

  test('a link that is down for everything still stops the run and parks nothing', () async {
    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: SupabaseClient('http://127.0.0.1:9', 'anon'));
    final p = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Offline', status: const Value('active')));
    final dir = Directory.systemTemp.createTempSync('fieldos-offline-');
    final file = File('${dir.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
    final dpr = await db.dprDao.create(DprEntriesCompanion.insert(
        id: uuid.v4(), projectId: p.id, createdBy: 'u', entryDate: DateTime.utc(2026, 11, 26), workSummary: 'x'));
    await db.dprDao.addPhoto(DprPhotosCompanion.insert(id: uuid.v4(), dprEntryId: dpr.id, photoPath: file.path));
    await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Queued'));
    for (var i = 0; i < 6; i++) {
      expect((await engine.pushPending()).succeeded, 0);
    }
    expect(await db.syncOutboxDao.parkedCount(), 0);
    expect((await db.syncOutboxDao.pending()).every((e) => e.retryCount == 0), isTrue);
    await engine.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });
}
