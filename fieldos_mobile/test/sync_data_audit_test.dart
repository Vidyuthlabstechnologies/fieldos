/// Sync and offline-data regressions found in the 2026-11-14 audit. No
/// network: the server is a small PostgREST stand-in behind MockClient.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

http.Response _json(http.Request req, Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'}, request: req);

/// A saved sign-in whose access token ran out an hour ago.
String _expiredSessionJson() {
  String part(Map<String, dynamic> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final exp = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  final jwt = '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': 'u1', 'exp': exp})}.c2ln';
  return jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-1',
    'user': {'id': 'u1', 'aud': 'authenticated', 'created_at': '2026-11-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}},
  });
}

/// Enough of PostgREST for a pull: eq/gt/in filters on id and seq, order,
/// limit and offset, and the change-log functions (unless [changeLog] is
/// off, as on a backend without 20261110020000_incremental_sync.sql).
class _Cloud {
  _Cloud({this.changeLog = true});
  final bool changeLog;
  final rows = <String, List<Map<String, dynamic>>>{};

  /// seq, table_name, row_id, op, changed_at, and 'visible' (false while
  /// the writing transaction has not committed).
  final changes = <Map<String, dynamic>>[];

  /// Runs after each page of [table] is answered (a colleague's write
  /// landing mid-pull).
  void Function(String table, int page)? afterPage;
  final _pages = <String, int>{};

  Future<http.Response> handle(http.Request req) async {
    final seg = req.url.pathSegments;
    if (seg.contains('rpc')) {
      final fn = seg.last;
      final visible = [for (final c in changes) if (c['visible'] != false) c['seq'] as int];
      if (changeLog && fn == 'sync_changes_floor') return _json(req, 0);
      if (changeLog && fn == 'sync_changes_head') return _json(req, visible.isEmpty ? 0 : visible.reduce((a, b) => a > b ? a : b));
      return _json(req, {'code': 'PGRST202', 'message': 'Could not find the function public.$fn'}, 404);
    }
    final table = seg.last;
    if (req.method != 'GET') return http.Response('', 201, request: req);
    final Iterable<Map<String, dynamic>> source =
        table == 'sync_changes' ? changes.where((c) => c['visible'] != false) : rows[table] ?? const [];
    var list = [
      for (final r in source) {for (final e in r.entries) if (e.key != 'visible') e.key: e.value}
    ];
    final q = req.url.queryParametersAll;
    for (final column in ['id', 'seq']) {
      for (final f in q[column] ?? const <String>[]) {
        if (f.startsWith('gt.')) {
          final v = f.substring(3);
          list = list.where((r) => column == 'seq' ? (r['seq'] as int) > int.parse(v) : (r['id'] as String).compareTo(v) > 0).toList();
        } else if (f.startsWith('in.(')) {
          final ids = f.substring(4, f.length - 1).split(',').map((v) => v.replaceAll('"', '')).toSet();
          list = list.where((r) => ids.contains(r['id'])).toList();
        }
      }
    }
    final order = req.url.queryParameters['order'];
    if (order != null) {
      final col = order.split('.').first;
      list.sort((a, b) => Comparable.compare(a[col] as Comparable, b[col] as Comparable));
      if (order.contains('.desc')) list = list.reversed.toList();
    }
    final offset = int.tryParse(req.url.queryParameters['offset'] ?? '') ?? 0;
    final limit = int.tryParse(req.url.queryParameters['limit'] ?? '');
    list = list.skip(offset).take(limit ?? list.length).toList();
    final response = _json(req, list);
    final n = _pages[table] = (_pages[table] ?? 0) + 1;
    afterPage?.call(table, n);
    return response;
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<Project> site() => db.projectDao.create(
      ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Tower A', status: const Value('active')));

  group('timestamps go to the server with their time zone', () {
    // Postgres reads an ISO time with no offset as UTC, so a phone's local
    // wall-clock time sent without one lands hours off (5:30 in India).
    void expectSameInstantInUtc(Object? sent, DateTime local) {
      expect(sent, isA<String>());
      final parsed = DateTime.parse(sent as String);
      expect(parsed.isUtc, isTrue, reason: '"$sent" has no time zone');
      expect(parsed.isAtSameMomentAs(local), isTrue);
    }

    test('a resolved issue', () async {
      final p = await site();
      final issue = await db.issueDao.create(IssuesCompanion.insert(id: uuid.v4(), projectId: p.id, description: 'Crack'));
      await db.issueDao.resolve(issue.id);
      final queued = (await db.syncOutboxDao.pending()).lastWhere((e) => e.targetTable == 'issues');
      final row = (await db.issueDao.forProject(p.id)).single;
      expectSameInstantInUtc((jsonDecode(queued.payload) as Map)['resolved_at'], row.resolvedAt!);
    });

    test('a decided approval and an approved purchase request', () async {
      final p = await site();
      final issue = await db.issueDao.create(IssuesCompanion.insert(id: uuid.v4(), projectId: p.id, description: 'x'));
      final local = DateTime(2026, 11, 10, 9, 30);
      final approval = Approval(
          id: uuid.v4(),
          projectId: p.id,
          entityType: 'budget_overrun',
          entityId: issue.id,
          requestedBy: 'u1',
          status: 'approved',
          decidedAt: local,
          createdAt: local);
      expectSameInstantInUtc(approvalToSupabaseJson(approval)['decided_at'], local);

      final req = await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
          id: uuid.v4(), projectId: p.id, raisedBy: 'u1', materialName: 'Cement', unit: const Value('bags')));
      expectSameInstantInUtc(purchaseRequestToSupabaseJson(req.copyWith(approvedAt: Value(local)))['approved_at'], local);
    });
  });

  group('a sign-in that cannot be refreshed never parks the outbox', () {
    // [runs]: an offline refresh retries for a few seconds inside gotrue on
    // each run; one counted try per run is what used to park the outbox
    // after syncOutboxMaxRetries runs.
    Future<void> push(int runs, Future<http.Response> Function(http.Request) server) async {
      var restHits = 0;
      final client = SupabaseClient('http://cloud.test', 'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((req) {
            if (req.url.path.startsWith('/rest/')) restHits++;
            return server(req);
          }));
      await client.auth.setInitialSession(_expiredSessionJson());
      final engine = SyncEngine(db: db, client: client);
      final p = await site();
      await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Plinth beam'));
      for (var i = 0; i < runs; i++) {
        expect((await engine.pushPending()).succeeded, 0);
      }
      final queued = await db.syncOutboxDao.pending();
      expect(queued, hasLength(2), reason: 'nothing parked');
      expect(queued.every((e) => e.retryCount == 0), isTrue, reason: '${[for (final e in queued) e.retryCount]}');
      expect(queued.first.lastError, isNotNull);
      expect(await db.syncOutboxDao.parkedCount(), 0);
      expect(restHits, 0);
      await engine.dispose();
      client.dispose();
    }

    test('offline with an expired access token (the refresh itself fails)', timeout: const Timeout(Duration(minutes: 2)),
        () async {
      await push(2, (req) async => throw http.ClientException('Failed host lookup: cloud.test', req.url));
    });

    test('the refresh token was revoked', () async {
      // That signs the client out; the app's sync paths stop there
      // (CloudSyncService.isSignedIn) until the person signs in again.
      await push(1, (req) async => req.url.path.contains('/auth/v1/token')
          ? _json(req, {'code': 400, 'error_code': 'refresh_token_not_found', 'msg': 'Invalid Refresh Token'}, 400)
          : _json(req, {'code': '42501', 'message': 'new row violates row-level security policy'}, 401));
    });

    test('classification', () {
      expect(isAuthSyncError(AuthRetryableFetchException()), isTrue);
      expect(isAuthSyncError(const PostgrestException(message: 'JWT expired', code: 'PGRST303')), isTrue);
      expect(isAuthSyncError(const PostgrestException(message: 'rls', code: '42501')), isFalse);
    });
  });

  group('incremental and full pulls', () {
    SyncEngine engineFor(_Cloud cloud) =>
        SyncEngine(db: db, client: SupabaseClient('http://cloud.test', 'anon', httpClient: MockClient(cloud.handle)));

    Future<void> setCursor(int seq) async {
      await db.settingsDao.set('sync_cursor:null', '$seq');
      await db.settingsDao.set('sync_cursor_settled:null', '$seq');
    }

    /// A site and its tasks already synced: on the phone with nothing
    /// queued, and the same rows on the server.
    Future<(Project, List<Task>)> syncedSite(_Cloud cloud, int tasks) async {
      final p = await site();
      for (var i = 0; i < tasks; i++) {
        await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Task $i'));
      }
      await db.delete(db.syncOutbox).go();
      final list = await db.taskDao.forProject(p.id);
      cloud.rows['projects'] = [projectToSupabaseJson(p)];
      cloud.rows['tasks'] = [for (final t in list) taskToSupabaseJson(t)];
      return (p, list);
    }

    test('a row deleted on the server during a full pull does not take another row off the phone', () async {
      final cloud = _Cloud(changeLog: false);
      final (p, tasks) = await syncedSite(cloud, SyncEngine.pullPageSize + 1);
      final byId = [...tasks]..sort((a, b) => a.id.compareTo(b.id));
      // A colleague deletes the first task once the first page is read.
      cloud.afterPage = (table, page) {
        if (table == 'tasks' && page == 1) cloud.rows['tasks']!.removeWhere((r) => r['id'] == byId.first.id);
      };
      final engine = engineFor(cloud);
      await engine.pullAll();
      final left = {for (final t in await db.taskDao.forProject(p.id)) t.id};
      expect(left.contains(byId.last.id), isTrue, reason: 'the task after the page break was never read, so it was removed');
      expect(left, hasLength(SyncEngine.pullPageSize + 1), reason: 'the deleted one goes on the next pull, from the log');
      await engine.dispose();
    });

    test('a change whose line commits after a newer one is still applied', () async {
      final cloud = _Cloud();
      final (_, tasks) = await syncedSite(cloud, 2);
      final (a, b) = (tasks[0], tasks[1]);
      await setCursor(10);
      final now = DateTime.now().toUtc().toIso8601String();
      // Both tasks were edited; A's write took its line number first but
      // its transaction committed after B's.
      cloud.rows['tasks'] = [
        {...taskToSupabaseJson(a), 'progress': 40},
        {...taskToSupabaseJson(b), 'progress': 70},
      ];
      cloud.changes.addAll([
        {'seq': 11, 'table_name': 'tasks', 'row_id': a.id, 'op': 'u', 'changed_at': now, 'visible': false},
        {'seq': 12, 'table_name': 'tasks', 'row_id': b.id, 'op': 'u', 'changed_at': now},
      ]);
      final engine = engineFor(cloud);
      await engine.pullAll();
      Future<int> progress(String id) async =>
          (await (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle()).progress;
      expect(await progress(b.id), 70);

      cloud.changes.first['visible'] = true;
      await engine.pullAll();
      expect(await progress(a.id), 40, reason: 'line 11 was behind the cursor by the time it could be read');
      expect(await db.settingsDao.get('sync_cursor:null'), '12');
      await engine.dispose();
    });

    test('more changes than one page: every line is read, oldest first, and the cursor ends at the newest', () async {
      final cloud = _Cloud();
      final (p, tasks) = await syncedSite(cloud, SyncEngine.pullPageSize + 1);
      await setCursor(10);
      final hourAgo = DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String();
      cloud.rows['tasks'] = [for (final t in tasks) {...taskToSupabaseJson(t), 'progress': 50}];
      for (var i = 0; i < tasks.length; i++) {
        cloud.changes.add({'seq': 11 + i, 'table_name': 'tasks', 'row_id': tasks[i].id, 'op': 'u', 'changed_at': hourAgo});
      }
      final engine = engineFor(cloud);
      await engine.pullAll();
      final stale = [for (final t in await db.taskDao.forProject(p.id)) if (t.progress != 50) t.title];
      expect(stale, isEmpty, reason: 'changes never read');
      expect(await db.settingsDao.get('sync_cursor:null'), '${10 + tasks.length}');
      await engine.dispose();
    });

    test('a task deleted after it was edited is removed, not fetched back', () async {
      final cloud = _Cloud();
      final (p, tasks) = await syncedSite(cloud, 2);
      await setCursor(10);
      final hourAgo = DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String();
      cloud.rows['tasks']!.removeWhere((r) => r['id'] == tasks[0].id);
      cloud.changes.addAll([
        {'seq': 11, 'table_name': 'tasks', 'row_id': tasks[0].id, 'op': 'u', 'changed_at': hourAgo},
        {'seq': 12, 'table_name': 'tasks', 'row_id': tasks[0].id, 'op': 'd', 'changed_at': hourAgo},
      ]);
      final engine = engineFor(cloud);
      await engine.pullAll();
      expect([for (final t in await db.taskDao.forProject(p.id)) t.id], [tasks[1].id]);
      expect(await db.settingsDao.get('sync_cursor:null'), '12');
      await engine.dispose();
    });

    test('a cursor left by an older build is followed by one full pull', () async {
      final cloud = _Cloud();
      final (p, tasks) = await syncedSite(cloud, 2);
      // Lines that build skipped: the change is on the server, its line is
      // behind the cursor.
      await db.settingsDao.set('sync_cursor:null', '20');
      cloud.rows['tasks'] = [for (final t in tasks) {...taskToSupabaseJson(t), 'progress': 90}];
      cloud.changes.add({'seq': 20, 'table_name': 'tasks', 'row_id': tasks[0].id, 'op': 'u',
        'changed_at': DateTime.now().toUtc().toIso8601String()});
      final engine = engineFor(cloud);
      await engine.pullAll();
      expect([for (final t in await db.taskDao.forProject(p.id)) t.progress], [90, 90]);
      expect(await db.settingsDao.get('sync_cursor:null'), '20');
      expect(await db.settingsDao.get('sync_cursor_settled:null'), '20');
      await engine.dispose();
    });

    test('lines older than the settle time are not read again', () async {
      final cloud = _Cloud();
      final (_, tasks) = await syncedSite(cloud, 2);
      await setCursor(10);
      final now = DateTime.now().toUtc();
      cloud.changes.addAll([
        {'seq': 11, 'table_name': 'tasks', 'row_id': tasks[0].id, 'op': 'u',
          'changed_at': now.subtract(const Duration(hours: 1)).toIso8601String()},
        {'seq': 12, 'table_name': 'tasks', 'row_id': tasks[1].id, 'op': 'u', 'changed_at': now.toIso8601String()},
      ]);
      final engine = engineFor(cloud);
      await engine.pullAll();
      expect(await db.settingsDao.get('sync_cursor:null'), '12');
      expect(await db.settingsDao.get('sync_cursor_settled:null'), '11');
      await engine.dispose();
    });
  });
}
