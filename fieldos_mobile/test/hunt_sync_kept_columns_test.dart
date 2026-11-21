/// A pull from a backend that lacks some of the phone's columns keeps the
/// phone's own values for them (SyncEngine._keepLocalOnlyColumns), for
/// every column type: dates and yes/no values, not only numbers and text.
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

/// Serves [rows] for full pulls; no change log, no RPCs.
class _Cloud {
  final rows = <String, List<Map<String, dynamic>>>{};

  Future<http.Response> handle(http.Request req) async {
    final seg = req.url.pathSegments;
    if (seg.contains('rpc')) {
      return _json(req, {'code': 'PGRST202', 'message': 'Could not find the function public.${seg.last}'}, 404);
    }
    if (req.method != 'GET') return http.Response('', 201, request: req);
    final after = req.url.queryParameters['id'];
    if (after != null && after.startsWith('gt.')) return _json(req, const []);
    return _json(req, rows[seg.last] ?? const []);
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('a start date and priority the server lacks survive a pull', () async {
    final p = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Tower A', status: const Value('active')));
    final start = DateTime(2026, 11, 3);
    final t = await db.taskDao.create(TasksCompanion.insert(
        id: uuid.v4(), projectId: p.id, title: 'Plinth beam', startDate: Value(start), priority: const Value('high')));
    await db.delete(db.syncOutbox).go();

    final cloud = _Cloud();
    cloud.rows['projects'] = [projectToSupabaseJson(p)];
    cloud.rows['tasks'] = [
      {...taskToSupabaseJson(t)}
        ..remove('start_date')
        ..remove('priority')
        ..['progress'] = 30,
    ];
    final engine = SyncEngine(db: db, client: SupabaseClient('http://old.test', 'anon', httpClient: MockClient(cloud.handle)));
    await engine.pullAll();

    final mine = await (db.select(db.tasks)..where((r) => r.id.equals(t.id))).getSingle();
    expect(mine.progress, 30, reason: 'the server row is applied');
    expect(mine.priority, 'high');
    expect(mine.startDate, start);
    await engine.dispose();
  });

  test('a ticked handover check and when it was ticked survive a pull from a server without them', () async {
    final p = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: uuid.v4(), name: 'Tower B', status: const Value('active')));
    final doneAt = DateTime(2026, 11, 4, 16, 45);
    final id = uuid.v4();
    await db.into(db.handoverChecks).insert(HandoverChecksCompanion.insert(
        id: id, projectId: p.id, unitId: 'u1', item: 'Taps fixed', done: const Value(true), doneAt: Value(doneAt)));
    final local = await (db.select(db.handoverChecks)..where((r) => r.id.equals(id))).getSingle();

    final cloud = _Cloud();
    cloud.rows['projects'] = [projectToSupabaseJson(p)];
    cloud.rows['site_handover_checks'] = [
      {
        'id': id,
        'project_id': p.id,
        'unit_id': 'u1',
        'item': 'Taps fixed, both bathrooms',
        'done_by': null,
        'sort_order': 0,
        'created_at': local.createdAt.toUtc().toIso8601String(),
        'updated_at': local.updatedAt.toUtc().toIso8601String(),
        'synced_at': local.updatedAt.toUtc().toIso8601String(),
      },
    ];
    final engine = SyncEngine(db: db, client: SupabaseClient('http://old.test', 'anon', httpClient: MockClient(cloud.handle)));
    await engine.pullAll();

    final mine = await (db.select(db.handoverChecks)..where((r) => r.id.equals(id))).getSingle();
    expect(mine.item, 'Taps fixed, both bathrooms', reason: 'the server row is applied');
    expect(mine.done, isTrue);
    expect(mine.doneAt, doneAt);
    await engine.dispose();
  });
}
