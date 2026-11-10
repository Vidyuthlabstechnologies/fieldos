/// A phone newer than its backend (the server's migrations not applied
/// yet): writes must neither be lost nor parked. A column the server does
/// not have is left off the row; a table it does not have makes the write
/// wait, uncounted, while the rest goes through.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

/// PostgREST stand-in: [missingTables] answer PGRST205, a body with any of
/// [missingColumns] answers PGRST204. Records what it accepted.
class _OldServer {
  _OldServer({this.missingTables = const {}, this.missingColumns = const {}});
  final Set<String> missingTables;
  final Map<String, Set<String>> missingColumns;
  final accepted = <String, List<Map<String, dynamic>>>{};
  final hits = <String, int>{};

  Future<http.Response> handle(http.Request req) async {
    final table = req.url.pathSegments.last;
    hits[table] = (hits[table] ?? 0) + 1;
    if (req.url.pathSegments.contains('rpc')) {
      return http.Response(jsonEncode({'code': 'PGRST202', 'message': 'Could not find the function public.$table'}), 404,
          headers: {'content-type': 'application/json'}, request: req);
    }
    if (missingTables.contains(table)) {
      return http.Response(
          jsonEncode({'code': 'PGRST205', 'message': "Could not find the table 'public.$table' in the schema cache"}),
          404,
          headers: {'content-type': 'application/json'}, request: req);
    }
    if (req.method == 'POST') {
      final body = jsonDecode(req.body);
      final rows = [for (final r in (body is List ? body : [body])) Map<String, dynamic>.from(r as Map)];
      for (final r in rows) {
        for (final c in missingColumns[table] ?? const <String>{}) {
          if (r.containsKey(c)) {
            return http.Response(
                jsonEncode({'code': 'PGRST204', 'message': "Could not find the '$c' column of '$table' in the schema cache"}),
                400,
                headers: {'content-type': 'application/json'}, request: req);
          }
        }
      }
      (accepted[table] ??= []).addAll(rows);
      return http.Response('', 201, request: req);
    }
    final rows = req.url.queryParameters.containsKey('offset') && req.url.queryParameters['offset'] != '0'
        ? const []
        : accepted[table] ?? const [];
    return http.Response(jsonEncode(rows), 200, headers: {'content-type': 'application/json'}, request: req);
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  SyncEngine engineFor(_OldServer server) =>
      SyncEngine(db: db, client: SupabaseClient('http://old.test', 'anon', httpClient: MockClient(server.handle)));

  Future<Project> site() => db.projectDao.create(
      ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Tower A', status: const Value('active')));

  test('a column the server lacks is left off; the row still syncs', () async {
    final server = _OldServer(missingColumns: {
      'tasks': {'priority', 'start_date'}
    });
    final engine = engineFor(server);
    final p = await site();
    final t = await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Plinth beam'));

    final r = await engine.pushPending();
    expect(r.failed, 0);
    expect(await db.syncOutboxDao.pendingCount(), 0);
    expect(await db.syncOutboxDao.parkedCount(), 0);
    final row = server.accepted['tasks']!.single;
    expect(row['id'], t.id);
    expect(row['title'], 'Plinth beam');
    expect(row.containsKey('priority'), isFalse);
    expect(row.containsKey('start_date'), isFalse);
    await engine.dispose();
  });

  test('a table the server lacks: the write waits, is never parked, and the rest goes through', () async {
    final server = _OldServer(missingTables: {'tasks'});
    final engine = engineFor(server);
    final p = await site();
    await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Waiting'));

    for (var i = 0; i < 8; i++) {
      await engine.pushPending();
    }
    expect(server.accepted['projects'], hasLength(1));
    final waiting = await db.syncOutboxDao.pending();
    expect(waiting, hasLength(1));
    expect(waiting.single.targetTable, 'tasks');
    expect(waiting.single.retryCount, 0);
    expect(waiting.single.lastError, contains('Waiting for a server update'));
    expect(await db.syncOutboxDao.parkedCount(), 0);
    // Asked once, then left alone until the recheck time.
    expect(server.hits['tasks'], 1);
    await engine.dispose();
  });

  test('a pull from that server does not wipe what the phone kept back', () async {
    final server = _OldServer(missingColumns: {
      'site_attendance': {'distance_m', 'accuracy_m', 'photo_id'}
    });
    final engine = engineFor(server);
    final p = await site();
    final a = await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
        id: uuid.v4(),
        projectId: p.id,
        workerName: 'Ravi',
        recordedBy: 'me',
        punchIn: DateTime.utc(2026, 11, 10, 3, 30),
        distanceM: const Value(12.5),
        accuracyM: const Value(8)));
    expect((await engine.pushPending()).failed, 0);
    expect(server.accepted['site_attendance']!.single.containsKey('distance_m'), isFalse);

    await engine.pullAll();
    final mine = await (db.select(db.labourAttendance)..where((r) => r.id.equals(a.id))).getSingle();
    expect(mine.workerName, 'Ravi');
    expect(mine.distanceM, 12.5);
    expect(mine.accuracyM, 8);
    await engine.dispose();
  });

  test('missing column parsing', () {
    expect(
        missingColumnOf(const PostgrestException(
            message: "Could not find the 'distance_m' column of 'site_attendance' in the schema cache", code: 'PGRST204')),
        'distance_m');
    expect(missingColumnOf(const PostgrestException(message: 'column "photo_id" of relation "x" does not exist', code: '42703')),
        'photo_id');
    expect(missingColumnOf(const PostgrestException(message: 'dup', code: '23505')), isNull);
  });
}
