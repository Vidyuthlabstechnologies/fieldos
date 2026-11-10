/// A simulated phone for sync tests against the local Supabase stack: its
/// own Drift database, local account id, Supabase client and sync engine.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const uuid = Uuid();

Future<bool> localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

SupabaseClient adminClient() => SupabaseClient(SyncConfig.local.url, localServiceRoleKey);

class MemoryStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? sessionJson) async => value = sessionJson;
}

class CloudPhone {
  CloudPhone._(this.db, this.client, this.engine, this.service, this.localUserId, this.filesDir);

  final AppDatabase db;
  final SupabaseClient client;
  final SyncEngine engine;
  final CloudSyncService service;
  final String localUserId;
  final Directory filesDir;

  static Future<CloudPhone> signUp(String label) async {
    final db = AppDatabase.memory();
    final client = SyncConfig.local.createClient();
    final filesDir = Directory.systemTemp.createTempSync('fieldos-$label-');
    final engine = SyncEngine(db: db, client: client, resolveDocumentsDirectory: () async => filesDir);
    final service = CloudSyncService(client: client, engine: engine, sessionStore: MemoryStore());
    final localUserId = uuid.v4();
    engine.localUserId = localUserId;
    final result = await service.enableSync(email: '$label-${uuid.v4()}@test.local', password: 'test-password-123!');
    expect(result.outcome, CloudSyncOutcome.signedUp);
    return CloudPhone._(db, client, engine, service, localUserId, filesDir);
  }

  String get remoteUserId => client.auth.currentUser!.id;

  Future<void> close() async {
    await service.dispose();
    await engine.dispose();
    await client.dispose();
    await db.close();
    if (filesDir.existsSync()) filesDir.deleteSync(recursive: true);
  }
}
