/// Work saved on the phone while a pull is running (a periodic sync takes a
/// while on a weak signal) is not taken off the phone by that same pull's
/// clean-up of rows the server does not have.
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

/// Serves [rows] for full pulls (no change log, no RPCs) and runs
/// [onGet] as each table is read.
class _Cloud {
  final rows = <String, List<Map<String, dynamic>>>{};
  Future<void> Function(String table)? onGet;

  Future<http.Response> handle(http.Request req) async {
    final seg = req.url.pathSegments;
    if (seg.contains('rpc')) {
      return _json(req, {'code': 'PGRST202', 'message': 'Could not find the function public.${seg.last}'}, 404);
    }
    if (req.method != 'GET') return http.Response('', 201, request: req);
    final after = req.url.queryParameters['id'];
    if (after != null && after.startsWith('gt.')) return _json(req, const []);
    await onGet?.call(seg.last);
    return _json(req, rows[seg.last] ?? const []);
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  Future<(Project, _Cloud, SyncEngine)> syncedSite() async {
    final company = uuid.v4();
    await db.settingsDao.set('cloud_linked_companies', jsonEncode([company]));
    final p = await db.projectDao.create(
        ProjectsCompanion.insert(id: uuid.v4(), companyId: company, name: 'Tower A', status: const Value('active')));
    await db.delete(db.syncOutbox).go();
    final cloud = _Cloud()..rows['projects'] = [projectToSupabaseJson(p)];
    final engine = SyncEngine(db: db, client: SupabaseClient('http://cloud.test', 'anon', httpClient: MockClient(cloud.handle)));
    return (p, cloud, engine);
  }

  test('a task added while the pull runs stays on the phone', () async {
    final (p, cloud, engine) = await syncedSite();
    String? added;
    cloud.onGet = (table) async {
      // The tasks were read; the person adds one before the pull ends.
      if (table == 'issues' && added == null) {
        added = (await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Shuttering'))).id;
      }
    };
    await engine.pullAll();

    expect([for (final t in await db.taskDao.forProject(p.id)) t.id], [added]);
    expect(await db.syncOutboxDao.pendingCount(), 1);
    await engine.dispose();
  });

  test('a site added while the pull runs stays on the phone', () async {
    final (p, cloud, engine) = await syncedSite();
    String? added;
    cloud.onGet = (table) async {
      if (table == 'tasks' && added == null) {
        added = (await db.projectDao.create(ProjectsCompanion.insert(
                id: uuid.v4(), companyId: p.companyId, name: 'Tower B', status: const Value('active'))))
            .id;
      }
    };
    await engine.pullAll();

    expect({for (final s in await db.projectDao.forCompany(p.companyId)) s.id}, {p.id, added});
    await engine.dispose();
  });

  test('a site no longer shared is kept while it has unsent work in it', () async {
    final (p, cloud, engine) = await syncedSite();
    final task = await db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: p.id, title: 'Shuttering'));
    // The person was taken off the site before the task went up.
    cloud.rows['projects'] = [];
    await engine.pullAll();

    expect([for (final s in await db.projectDao.forCompany(p.companyId)) s.id], [p.id]);
    expect([for (final t in await db.taskDao.forProject(p.id)) t.id], [task.id]);
    await engine.dispose();
  });

  test('a site with unsent photos in a report is kept too', () async {
    final (p, cloud, engine) = await syncedSite();
    final dpr = await db.dprDao.create(DprEntriesCompanion.insert(
        id: uuid.v4(), projectId: p.id, createdBy: 'me', entryDate: DateTime(2026, 11, 20), workSummary: 'Slab cast'));
    cloud.rows['dpr_entries'] = [dprEntryToSupabaseJson(dpr)];
    await db.delete(db.syncOutbox).go();
    // Only the photo is waiting: its report and the site are on the server.
    await db.syncOutboxDao.enqueue(
        targetTable: 'dpr_photos',
        recordId: uuid.v4(),
        operation: 'insert',
        payloadJson: jsonEncode({'id': 'x', 'dpr_entry_id': dpr.id, 'photo_path': '${p.id}/dpr-photos/x.jpg'}));
    cloud.rows['projects'] = [];
    await engine.pullAll();

    expect([for (final s in await db.projectDao.forCompany(p.companyId)) s.id], [p.id]);
    expect(await db.dprDao.byId(dpr.id), isNotNull);
    await engine.dispose();
  });

  test('a site no longer shared, with nothing unsent, is removed', () async {
    final (p, cloud, engine) = await syncedSite();
    cloud.rows['projects'] = [];
    await engine.pullAll();
    expect(await db.projectDao.forCompany(p.companyId), isEmpty);
    await engine.dispose();
  });
}
