/// The speed work for cheap phones on weak networks (test/perf has the
/// benchmark): new rows go up in batches, a pull reads several tables at
/// once and writes in transactions, the database is in WAL mode with
/// lookup indexes, and Home's brief reads only the day's punches. Each
/// must keep the old behaviour: nothing lost, refused rows still handled
/// one by one, alerts still fired.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _uuid = Uuid();

/// PostgREST stand-in. [duplicates] are ids the server already has: an
/// insert carrying one is refused whole with 23505, like Postgres does.
class _Server {
  _Server({this.duplicates = const {}, this.delay = Duration.zero});
  final Set<String> duplicates;
  final Duration delay;
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  final posts = <String, List<int>>{};
  var inFlight = 0;
  var maxInFlight = 0;

  http.Response _json(Object body, int status, http.Request req) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'}, request: req);

  Future<http.Response> handle(http.Request req) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return _answer(req);
    } finally {
      inFlight--;
    }
  }

  http.Response _answer(http.Request req) {
    final table = req.url.pathSegments.last;
    if (req.url.pathSegments.contains('rpc')) {
      return _json({'code': 'PGRST202', 'message': 'Could not find the function public.$table'}, 404, req);
    }
    final store = rows[table] ??= {};
    if (req.method == 'POST') {
      final body = jsonDecode(req.body);
      final list = [for (final r in (body is List ? body : [body])) Map<String, dynamic>.from(r as Map)];
      if (list.any((r) => duplicates.contains(r['id']) || store.containsKey(r['id']))) {
        return _json({'code': '23505', 'message': 'duplicate key value violates unique constraint'}, 409, req);
      }
      (posts[table] ??= []).add(list.length);
      for (final r in list) {
        store[r['id'] as String] = r;
      }
      return http.Response('', 201, request: req);
    }
    final q = req.url.queryParameters;
    var list = store.values.toList()..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final id = q['id'];
    if (id != null && id.startsWith('gt.')) list = [for (final r in list) if ((r['id'] as String).compareTo(id.substring(3)) > 0) r];
    if (id != null && id.startsWith('eq.')) {
      final want = id.substring(3);
      list = [for (final r in list) if (r['id'] == want) r];
      if (list.isEmpty && duplicates.contains(want)) list = [{'id': want}];
    }
    final limit = int.tryParse(q['limit'] ?? '');
    if (limit != null && list.length > limit) list = list.sublist(0, limit);
    if (q['select'] == 'id') list = [for (final r in list) {'id': r['id']}];
    return _json(list, 200, req);
  }
}

SyncEngine _engine(AppDatabase db, _Server server) =>
    SyncEngine(db: db, client: SupabaseClient('http://speed.test', 'anon', httpClient: MockClient(server.handle)));

Future<Project> _site(AppDatabase db) =>
    db.projectDao.create(ProjectsCompanion.insert(id: _uuid.v4(), companyId: _uuid.v4(), name: 'Tower A', status: const Value('active')));

Future<void> _punch(AppDatabase db, Project p, String id, DateTime at) => db.attendanceDao.punchIn(
    LabourAttendanceCompanion.insert(id: id, projectId: p.id, workerName: 'W $id', recordedBy: 'me', punchIn: at));

void main() {
  group('push', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    test('new rows of one table go up together, in batches of at most pushBatchSize', () async {
      final server = _Server();
      final engine = _engine(db, server);
      final p = await _site(db);
      final n = SyncEngine.pushBatchSize + 10;
      for (var i = 0; i < n; i++) {
        await _punch(db, p, _uuid.v4(), DateTime(2026, 11, 20, 8));
      }
      final r = await engine.pushPending();
      expect(r.failed, 0);
      expect(await db.syncOutboxDao.pendingCount(), 0);
      expect(server.posts['site_attendance'], [SyncEngine.pushBatchSize, 10]);
      expect(server.rows['site_attendance'], hasLength(n));
      await engine.dispose();
    });

    test('a refused batch is sent row by row: a row already on the server counts as sent, the rest go up', () async {
      final already = _uuid.v4();
      final server = _Server(duplicates: {already});
      final engine = _engine(db, server);
      final p = await _site(db);
      final ids = [_uuid.v4(), already, _uuid.v4(), _uuid.v4()];
      for (final id in ids) {
        await _punch(db, p, id, DateTime(2026, 11, 20, 8));
      }
      final r = await engine.pushPending();
      expect(r.failed, 0);
      expect(await db.syncOutboxDao.pendingCount(), 0);
      expect(await db.syncOutboxDao.parkedCount(), 0);
      // The batch was refused, then each went alone (never as a batch again).
      expect(server.posts['site_attendance'], [1, 1, 1]);
      expect(server.rows['site_attendance']!.keys.toSet(), {ids[0], ids[2], ids[3]});
      await engine.dispose();
    });

    test('a batch is one table only: the site goes first, then its tasks together', () async {
      final server = _Server();
      final engine = _engine(db, server);
      final p = await _site(db);
      final t = await db.taskDao.create(TasksCompanion.insert(id: _uuid.v4(), projectId: p.id, title: 'Plinth'));
      await db.taskDao.create(TasksCompanion.insert(id: _uuid.v4(), projectId: p.id, title: 'Column'));
      final entries = await db.syncOutboxDao.pending();
      expect(entries.map((e) => e.targetTable), ['projects', 'tasks', 'tasks']);
      final r = await engine.pushPending();
      expect(r.failed, 0);
      expect(server.posts['tasks'], [2]);
      expect(server.rows['tasks']!.containsKey(t.id), isTrue);
      await engine.dispose();
    });

    test('pending and parked are counted without loading the rows', () async {
      final p = await _site(db);
      await _punch(db, p, _uuid.v4(), DateTime(2026, 11, 20, 8));
      expect(await db.syncOutboxDao.pendingCount(), 2);
      final first = (await db.syncOutboxDao.pending()).first;
      await db.syncOutboxDao.park(first.id, 'no');
      expect(await db.syncOutboxDao.pendingCount(), 1);
      expect(await db.syncOutboxDao.parkedCount(), 1);
    });
  });

  group('pull', () {
    test('a first pull reads several tables at once and still writes every row, with alerts for new ones', () async {
      final source = AppDatabase.memory();
      final server = _Server(delay: const Duration(milliseconds: 20));
      final p = await _site(source);
      for (var i = 0; i < 450; i++) {
        await _punch(source, p, _uuid.v4(), DateTime(2026, 11, 1).add(Duration(hours: i)));
      }
      for (var i = 0; i < 5; i++) {
        await source.messageDao.send(projectId: p.id, senderId: 'ravi', senderName: 'Ravi', body: 'Hello $i');
      }
      final seed = _engine(source, server);
      await seed.pushPending();
      await seed.dispose();
      await source.close();

      final phone = AppDatabase.memory();
      final engine = _engine(phone, server);
      final alerts = <String>[];
      engine.onRemoteRowCreated = (table, row) => alerts.add(table);
      await engine.pullAll();
      expect(server.maxInFlight, greaterThan(1));
      expect(server.maxInFlight, lessThanOrEqualTo(SyncEngine.pullParallelism));
      expect(await phone.attendanceDao.forProject(p.id), hasLength(450));
      expect(await phone.messageDao.forProject(p.id), hasLength(5));
      expect(alerts.where((t) => t == 'project_messages'), hasLength(5));

      // A second pull changes nothing and alerts nobody.
      alerts.clear();
      await engine.pullAll();
      expect(alerts, isEmpty);
      expect(await phone.attendanceDao.forProject(p.id), hasLength(450));
      await engine.dispose();
      await phone.close();
    });
  });

  group('database', () {
    test('opened like on the phone: WAL, and lookups use an index', () async {
      final dir = Directory.systemTemp.createTempSync('fieldos-speed');
      final db = AppDatabase(AppDatabase.openFile(File('${dir.path}/f.sqlite')));
      try {
        final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
        expect(mode.data.values.first, 'wal');
        final plan = await db
            .customSelect("EXPLAIN QUERY PLAN SELECT * FROM labour_attendance WHERE project_id = 'x'")
            .get();
        expect(plan.map((r) => r.data['detail']).join(' '), contains('idx_labour_attendance_project_id'));
        final indexes = await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'").get();
        expect(indexes.length, greaterThan(60));
      } finally {
        await db.close();
        dir.deleteSync(recursive: true);
      }
    });

    test("a day's punches: only the days around it are read, the day itself complete", () async {
      final db = AppDatabase.memory();
      final p = await _site(db);
      for (var d = 1; d <= 30; d++) {
        await _punch(db, p, _uuid.v4(), DateTime(2026, 11, d, 8));
        await _punch(db, p, _uuid.v4(), DateTime(2026, 11, d, 23, 50));
      }
      final rows = await db.attendanceDao.aroundDay(p.id, DateTime(2026, 11, 15));
      final days = rows.map((r) => r.punchIn.day).toSet();
      expect(days, {14, 15, 16});
      expect(rows.where((r) => r.punchIn.day == 15), hasLength(2));
      await db.close();
    });
  });
}
