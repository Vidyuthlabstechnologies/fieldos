/// Speed check for cheap phones on weak networks: how long a first sync
/// takes to pull a busy company onto a new phone, how long a day of
/// offline work takes to send, and how long the screens' everyday reads
/// take once months of records are on the phone.
///
/// Skipped in normal runs (it takes a minute or two). Run it with
///   PERF_BENCH=1 PERF_LABEL=after flutter test test/perf/low_end_bench_test.dart
/// and compare build/perf/<label>.json between two checkouts. The network
/// is a stand-in PostgREST that waits [rtt] per request, like a 3G link;
/// the database is a real file, so commits pay for the disk.
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
import 'package:fieldos_mobile/features/brief/owner_brief.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _uuid = Uuid();
final _enabled = Platform.environment['PERF_BENCH'] == '1';
final _label = Platform.environment['PERF_LABEL'] ?? 'run';

/// One round trip on a typical Indian 3G site connection.
const rtt = Duration(milliseconds: 250);

/// Rows a busy company has after a few months: [sites] sites, each with
/// this many of every kind.
const sites = 6;
const perSite = (tasks: 150, expenses: 900, punches: 1500, messages: 600, workers: 40);

/// PostgREST stand-in holding every row pushed to it. Answers the paged
/// reads the full pull makes (id > after, ordered by id, limit), and
/// "no such function" for RPCs, so the pull takes the full-pull path.
class _Server {
  Duration delay = Duration.zero;
  final rows = <String, Map<String, Map<String, dynamic>>>{};
  var requests = 0;
  var inFlight = 0;
  var maxInFlight = 0;

  Future<http.Response> handle(http.Request req) async {
    requests++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      return _answer(req);
    } finally {
      inFlight--;
    }
  }

  http.Response _json(Object body, int status, http.Request req) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'}, request: req);

  http.Response _answer(http.Request req) {
    final table = req.url.pathSegments.last;
    if (req.url.pathSegments.contains('rpc')) {
      return _json({'code': 'PGRST202', 'message': 'Could not find the function public.$table'}, 404, req);
    }
    final store = rows[table] ??= {};
    if (req.method == 'POST') {
      final body = jsonDecode(req.body);
      for (final r in (body is List ? body : [body])) {
        final m = Map<String, dynamic>.from(r as Map);
        store[m['id'] as String] = m;
      }
      return http.Response('', 201, request: req);
    }
    if (req.method == 'PATCH' || req.method == 'DELETE') return _json(const [], 200, req);
    final q = req.url.queryParameters;
    var list = store.values.toList()..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final id = q['id'];
    if (id != null && id.startsWith('gt.')) list = [for (final r in list) if ((r['id'] as String).compareTo(id.substring(3)) > 0) r];
    if (id != null && id.startsWith('eq.')) list = [for (final r in list) if (r['id'] == id.substring(3)) r];
    if (id != null && id.startsWith('in.(')) {
      final ids = id.substring(4, id.length - 1).split(',').toSet();
      list = [for (final r in list) if (ids.contains(r['id'])) r];
    }
    final limit = int.tryParse(q['limit'] ?? '');
    if (limit != null && list.length > limit) list = list.sublist(0, limit);
    if (q['select'] == 'id') list = [for (final r in list) {'id': r['id']}];
    return _json(list, 200, req);
  }
}

AppDatabase _fileDb(File file) => AppDatabase(AppDatabase.openFile(file));

Future<String> _seed(AppDatabase db) async {
  final company = _uuid.v4();
  final me = _uuid.v4();
  final day0 = DateTime(2026, 6, 1);
  for (var s = 0; s < sites; s++) {
    final p = await db.projectDao.create(
        ProjectsCompanion.insert(id: _uuid.v4(), companyId: company, name: 'Tower $s', status: const Value('active')));
    for (var i = 0; i < perSite.workers; i++) {
      await db.workerDao.create(WorkersCompanion.insert(id: _uuid.v4(), projectId: p.id, name: 'Worker $i'));
    }
    for (var i = 0; i < perSite.tasks; i++) {
      await db.taskDao.create(TasksCompanion.insert(id: _uuid.v4(), projectId: p.id, title: 'Task $i'));
    }
    for (var i = 0; i < perSite.expenses; i++) {
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          category: 'material',
          amount: 100.0 + i,
          incurredOn: day0.add(Duration(days: i % 150)).toIso8601String().substring(0, 10),
          recordedBy: me));
    }
    for (var i = 0; i < perSite.punches; i++) {
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: _uuid.v4(),
          projectId: p.id,
          workerName: 'Worker ${i % perSite.workers}',
          recordedBy: me,
          punchIn: day0.add(Duration(days: i ~/ perSite.workers, hours: 8))));
    }
    for (var i = 0; i < perSite.messages; i++) {
      await db.messageDao.send(projectId: p.id, senderId: me, senderName: 'Ravi', body: 'Message $i');
    }
  }
  return company;
}

Future<T> _time<T>(Map<String, Object> out, String name, Future<T> Function() body) async {
  final sw = Stopwatch()..start();
  final r = await body();
  out[name] = sw.elapsedMilliseconds;
  // ignore: avoid_print
  print('$name: ${sw.elapsedMilliseconds} ms');
  return r;
}

void main() {
  test('low-end phone benchmark', skip: _enabled ? false : 'set PERF_BENCH=1 to run', timeout: const Timeout(Duration(minutes: 20)),
      () async {
    final out = <String, Object>{'label': _label, 'rtt_ms': rtt.inMilliseconds};
    final tmp = Directory.systemTemp.createTempSync('fieldos-bench');
    final server = _Server();

    // A company's history, sent to the server once (no delay: setup only).
    final source = AppDatabase.memory();
    final company = await _seed(source);
    final seedEngine = SyncEngine(db: source, client: SupabaseClient('http://bench.test', 'anon', httpClient: MockClient(server.handle)));
    await seedEngine.pushPending();
    await seedEngine.dispose();
    await source.close();
    out['rows_on_server'] = server.rows.values.fold<int>(0, (n, t) => n + t.length);

    // 1. First sync on a new phone over 3G.
    server
      ..delay = rtt
      ..requests = 0
      ..maxInFlight = 0;
    final phone = _fileDb(File('${tmp.path}/phone.sqlite'));
    final engine = SyncEngine(db: phone, client: SupabaseClient('http://bench.test', 'anon', httpClient: MockClient(server.handle)));
    await _time(out, 'first_sync_pull_ms', engine.pullAll);
    out['first_sync_requests'] = server.requests;
    out['first_sync_max_parallel'] = server.maxInFlight;

    // 2. The same pull with an instant network: what the phone's own work costs.
    server.delay = Duration.zero;
    await _time(out, 'repeat_pull_no_network_ms', engine.pullAll);

    // 3. A day of offline work sent over 3G: 120 punches, 40 messages, 30 expenses.
    final site = (await phone.projectDao.forCompany(company)).first;
    for (var i = 0; i < 120; i++) {
      await phone.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: _uuid.v4(), projectId: site.id, workerName: 'New $i', recordedBy: 'me', punchIn: DateTime(2026, 11, 20, 8)));
    }
    for (var i = 0; i < 40; i++) {
      await phone.messageDao.send(projectId: site.id, senderId: 'me', senderName: 'Ravi', body: 'Offline $i');
    }
    for (var i = 0; i < 30; i++) {
      await phone.expenseDao.create(SiteExpensesCompanion.insert(
          id: _uuid.v4(), projectId: site.id, category: 'tea', amount: 50, incurredOn: '2026-11-20', recordedBy: 'me'));
    }
    server
      ..delay = rtt
      ..requests = 0;
    final pushed = await _time(out, 'day_offline_push_ms', engine.pushPending);
    out['day_offline_push_requests'] = server.requests;
    out['day_offline_push_failed'] = pushed.failed;
    expect(pushed.failed, 0);
    expect(await phone.syncOutboxDao.pendingCount(), 0);

    // 4. Everyday reads, 20 times each, on the last site.
    Future<void> reads(String name, Future<Object?> Function() q) => _time(out, name, () async {
          for (var i = 0; i < 20; i++) {
            await q();
          }
        });
    await reads('read_expenses_x20_ms', () => phone.expenseDao.forProject(site.id));
    await reads('read_attendance_x20_ms', () => phone.attendanceDao.forProject(site.id));
    await reads('read_messages_x20_ms', () => phone.messageDao.forProject(site.id));
    await reads('read_tasks_x20_ms', () => phone.taskDao.forProject(site.id));
    await reads('read_workers_x20_ms', () => phone.workerDao.forProject(site.id));
    await reads('read_pending_count_x20_ms', () => phone.syncOutboxDao.pendingCount());

    // 5. What Home works out on every open: the owner's brief of every site.
    await reads('home_brief_x20_ms', () => buildOwnerBrief(phone, company, day: DateTime(2026, 7, 10)));

    await engine.dispose();
    await phone.close();

    // 6. Opening the app: the database opened from cold, through the first read.
    final reopened = _fileDb(File('${tmp.path}/phone.sqlite'));
    await _time(out, 'cold_open_first_read_ms', () => reopened.projectDao.forCompany(company));
    // The one-time cost on the first launch after the update that adds the
    // indexes, with this much data on the phone.
    if (Platform.environment['PERF_LABEL'] != 'before') {
      final names = await reopened.customSelect("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'").get();
      for (final n in names) {
        await reopened.customStatement('DROP INDEX "${n.read<String>('name')}"');
      }
      await _time(out, 'one_time_index_build_ms', reopened.ensureLookupIndexes);
    }
    await reopened.close();
    tmp.deleteSync(recursive: true);
    Directory('build/perf').createSync(recursive: true);
    File('build/perf/$_label.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(out));
  });
}
