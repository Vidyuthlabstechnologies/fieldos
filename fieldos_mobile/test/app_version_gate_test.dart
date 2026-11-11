/// Minimum supported app version (issue #146): a build older than the
/// server's minimum stops syncing without touching the server or the
/// phone's unsent work; being offline, or a server without the check yet,
/// never stops anyone.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/app_version_gate.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const uuid = Uuid();

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  /// [minimum] null: the server has no min_app_build() yet (PGRST202).
  /// [offline]: every request fails at the socket.
  ({SupabaseClient client, List<String> hits}) server({Map<String, dynamic>? minimum, bool offline = false}) {
    final hits = <String>[];
    final client = SupabaseClient('http://gate.test', 'anon', httpClient: MockClient((req) async {
      hits.add('${req.method} ${req.url.path}');
      if (offline) throw http.ClientException('Failed host lookup', req.url);
      if (req.url.path.endsWith('/rpc/min_app_build')) {
        if (minimum == null) {
          return http.Response(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function'}), 404,
              headers: {'content-type': 'application/json'}, request: req);
        }
        return http.Response(jsonEncode(minimum), 200, headers: {'content-type': 'application/json'}, request: req);
      }
      if (req.method == 'POST') return http.Response('', 201, request: req);
      return http.Response('[]', 200, headers: {'content-type': 'application/json'}, request: req);
    }));
    return (client: client, hits: hits);
  }

  AppVersionGate gate(SupabaseClient client, {int build = 19, DateTime Function()? clock}) =>
      AppVersionGate(db: db, client: () => client, currentBuild: () async => build, platform: 'android', clock: clock);

  Future<void> unsentSite() async {
    await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Tower A', status: const Value('active')));
  }

  test('a build below the minimum never pushes, and its unsent work stays on the phone', () async {
    final s = server(minimum: {'android': 25, 'ios': 0, 'message': 'Sites moved to the new layout.'});
    await unsentSite();
    final before = (await db.syncOutboxDao.pending()).length;
    expect(before, greaterThan(0));
    final engine = SyncEngine(db: db, client: s.client, versionGate: gate(s.client));

    await expectLater(engine.pushPending(), throwsA(isA<AppUpdateRequired>()));
    await expectLater(engine.pullAll(), throwsA(isA<AppUpdateRequired>()));
    expect(s.hits.where((h) => !h.endsWith('/rpc/min_app_build')), isEmpty, reason: 'nothing else reached the server');
    expect((await db.syncOutboxDao.pending()).length, before);

    final e = (await gate(s.client).cached())!;
    expect(e.minBuild, 25);
    expect(e.note, 'Sites moved to the new layout.');
    expect(friendlyError(e), e.message);
  });

  test('a build at or above the minimum syncs as before', () async {
    final s = server(minimum: {'android': 19, 'ios': 30, 'message': null});
    await unsentSite();
    final engine = SyncEngine(db: db, client: s.client, versionGate: gate(s.client));
    final result = await engine.pushPending();
    expect(result.failed, 0);
    expect(result.succeeded, greaterThan(0));
    expect(await gate(s.client).cached(), isNull);
  });

  test('offline is never blocked, and the last answer seen is kept', () async {
    final off = server(offline: true);
    expect(await gate(off.client).check(), isNull, reason: 'nothing known: no minimum');

    final on = server(minimum: {'android': 25});
    expect(await gate(on.client).check(), isA<AppUpdateRequired>());
    // A day later, offline: the remembered minimum still applies.
    final later = DateTime.now().add(const Duration(days: 2));
    expect(await gate(off.client, clock: () => later).check(), isA<AppUpdateRequired>());
  });

  test('a server without the check yet means no minimum', () async {
    final s = server();
    await unsentSite();
    expect(await gate(s.client).check(), isNull);
    final engine = SyncEngine(db: db, client: s.client, versionGate: gate(s.client));
    expect((await engine.pushPending()).failed, 0);
  });

  test('the answer is asked for at most once a day', () async {
    final s = server(minimum: {'android': 0});
    final g = gate(s.client);
    await g.check();
    await g.check();
    await g.requireSupported();
    expect(s.hits.where((h) => h.endsWith('/rpc/min_app_build')).length, 1);
    await g.check(force: true);
    expect(s.hits.where((h) => h.endsWith('/rpc/min_app_build')).length, 2);
  });
}
