/// Real-infrastructure test for Documents sync: the FILE itself must move
/// through Supabase Storage (bucket 'documents'), not just a metadata row --
/// this is the exact failure mode the original no-sync decision existed to
/// prevent (a row pointing at a path that only exists on one phone). Push
/// asserts the object is downloadable with identical bytes from real
/// Storage; pull asserts the downloaded file lands on local disk.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _serviceRoleKey = localServiceRoleKey;

final _uuid = Uuid();

Future<bool> _localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool stackUp;

  setUpAll(() async {
    stackUp = await _localStackReachable();
  });

  test('Document push uploads the real file to Storage and lands metadata in Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-docs-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Docs Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final docId = _uuid.v4();
    final payloadBytes = List<int>.generate(4096, (i) => i % 251);
    final tempFile = File('${Directory.systemTemp.path}/fieldos_doc_${_uuid.v4()}.pdf');
    await tempFile.writeAsBytes(payloadBytes);

    final doc = await db.documentDao.create(DocumentsCompanion.insert(
      id: docId,
      projectId: projectId,
      name: 'structural drawing set',
      category: const Value('drawing'),
      filePath: tempFile.path,
      fileSize: Value(payloadBytes.length),
      mimeType: const Value('application/pdf'),
      uploadedBy: userId,
    ));

    expect(await db.syncOutboxDao.pendingCount(), 1);
    final result = await engine.pushPending();
    expect(result.succeeded, 1);
    expect(result.failed, 0);

    // Metadata row in real Postgres, with file_path holding the storage path.
    final remoteRow = await adminClient.from('documents').select().eq('id', doc.id);
    expect(remoteRow.length, 1);
    expect(remoteRow.first['file_path'], '$projectId/${doc.id}');
    expect(remoteRow.first['name'], 'structural drawing set');
    expect(remoteRow.first['version'], 1);

    // The actual bytes are downloadable from real Storage under RLS-scoped
    // service access -- proving the file moved, not just the metadata.
    final downloaded = await adminClient.storage.from('documents').download('$projectId/${doc.id}');
    expect(downloaded.length, payloadBytes.length);
    for (var i = 0; i < payloadBytes.length; i++) {
      if (downloaded[i] != payloadBytes[i]) fail('byte mismatch at offset $i');
    }
    await db.close();
    await tempFile.delete();
    await userClient.dispose();
    await adminClient.dispose();
  });

  test('pullAll downloads a remotely-created document and stores it locally', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-docs-pull-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    final docId = _uuid.v4();
    final storagePath = '$projectId/$docId';
    final payloadBytes = Uint8List.fromList('site permit scan v2'.codeUnits);
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull Docs Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});
    await adminClient.storage.from('documents').uploadBinary(storagePath, payloadBytes);
    await adminClient.from('documents').insert({
      'id': docId,
      'project_id': projectId,
      'name': 'site permit.pdf',
      'version': 2,
      'file_path': storagePath,
      'file_size': payloadBytes.length,
      'mime_type': 'application/pdf',
      'uploaded_by': userId,
    });

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final tempDocsDir = await Directory.systemTemp.createTemp('fieldos_docs_pull');
    final engine = SyncEngine(
      db: db,
      client: userClient,
      resolveDocumentsDirectory: () async => tempDocsDir,
    );
    await engine.pullAll();

    final docs = await db.documentDao.forProject(projectId);
    expect(docs.length, 1);
    expect(docs.single.name, 'site permit.pdf');
    expect(docs.single.version, 2);
    // The local row must point at a real local file with the same bytes --
    // never at another device's filesystem.
    final localFile = File(docs.single.filePath);
    expect(await localFile.exists(), isTrue);
    expect(await localFile.readAsBytes(), payloadBytes);

    await db.close();
    await tempDocsDir.delete(recursive: true);
    await userClient.dispose();
    await adminClient.dispose();
  });
}
