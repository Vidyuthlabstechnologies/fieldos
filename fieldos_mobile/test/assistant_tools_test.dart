/// The assistant's actions on the phone: they read the right data, save
/// through the same DAO calls as the screens (so the change is queued for
/// team sync), and refuse bad or foreign input with a message the model can
/// act on instead of throwing.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  late AppDatabase db;
  late AssistantTools tools;
  final now = DateTime(2026, 11, 9, 10, 30);

  setUp(() async {
    db = AppDatabase.memory();
    tools = AssistantTools(db: db, companyId: 'c1', userId: 'u1', clock: () => now);
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: 'c1', name: 'Narapally Villa', status: const Value('active')));
    await db.projectDao.create(ProjectsCompanion.insert(id: 'other', companyId: 'c2', name: 'Not ours'));
    await db.workerDao.create(WorkersCompanion.insert(id: 'w1', projectId: 'p1', name: 'Ramesh', role: const Value('Mason')));
    await db.workerDao.create(WorkersCompanion.insert(id: 'w2', projectId: 'p1', name: 'Suresh'));
  });
  tearDown(() => db.close());

  Future<dynamic> read(String name, [Map<String, dynamic> input = const {}]) async {
    final out = await tools.run(name, input);
    expect(out.isError, isFalse, reason: out.result);
    return jsonDecode(out.result);
  }

  test('list_projects shows only this company', () async {
    final list = await read('list_projects') as List;
    expect(list.map((p) => p['name']), ['Narapally Villa']);
  });

  test('another company\'s project is refused, not read', () async {
    final out = await tools.run('project_overview', {'project_id': 'other'});
    expect(out.isError, isTrue);
    expect(out.result, contains('list_projects'));
  });

  test('add_expense saves like the Money screen and is queued for sync', () async {
    final before = (await db.syncOutboxDao.pending()).length;
    final out = await tools.run('add_expense', {'project_id': 'p1', 'amount': 4500, 'category': 'material', 'note': 'Cement 10 bags'});
    expect(out.isError, isFalse, reason: out.result);
    expect(out.changedProjectId, 'p1');
    final rows = await db.expenseDao.forProject('p1');
    expect(rows.single.amount, 4500);
    expect(rows.single.category, 'Material');
    expect(rows.single.incurredOn, '2026-11-09');
    expect(rows.single.recordedBy, 'u1');
    expect(rows.single.note, 'Cement 10 bags');
    expect((await db.syncOutboxDao.pending()).length, before + 1);
  });

  test('a bad amount goes back to the model as an error', () async {
    for (final amount in [0, -5, 'abc', null]) {
      final out = await tools.run('add_expense', {'project_id': 'p1', 'amount': amount, 'category': 'Fuel'});
      expect(out.isError, isTrue);
    }
    expect(await db.expenseDao.forProject('p1'), isEmpty);
  });

  test('mark_attendance matches names, adds walk-ins and skips who is already in', () async {
    final first = jsonDecode((await tools.run('mark_attendance', {
      'project_id': 'p1',
      'worker_names': ['ramesh', 'Lakshmi'],
    }))
        .result);
    expect(first['marked_present'], ['Ramesh']);
    expect(first['walk_in_workers'], ['Lakshmi']);
    final again = jsonDecode((await tools.run('mark_attendance', {
      'project_id': 'p1',
      'worker_names': ['Ramesh', 'Suresh'],
    }))
        .result);
    expect(again['already_present'], ['Ramesh']);
    expect(again['marked_present'], ['Suresh']);
    final rows = await db.attendanceDao.forProject('p1');
    expect(rows, hasLength(3));
    expect(rows.firstWhere((r) => r.workerName == 'Ramesh').workerId, 'w1');

    final workers = await read('list_workers', {'project_id': 'p1'}) as List;
    expect(workers.every((w) => w['present_today'] == true), isTrue);
  });

  test('project_overview adds up the day and the money', () async {
    await tools.run('add_expense', {'project_id': 'p1', 'amount': 1000, 'category': 'Fuel'});
    await tools.run('record_payment_received', {'project_id': 'p1', 'amount': 50000, 'from_party': 'Client', 'mode': 'upi'});
    await tools.run('add_task', {'project_id': 'p1', 'title': 'Shuttering', 'due_date': '2026-11-01'});
    await tools.run('mark_attendance', {'project_id': 'p1', 'worker_names': ['Ramesh']});
    await tools.run('add_daily_report', {'project_id': 'p1', 'work_summary': 'Slab shuttering', 'manpower_count': 9});
    final o = await read('project_overview', {'project_id': 'p1'}) as Map;
    expect(o['present_today'], 1);
    expect(o['open_tasks'], 1);
    expect(o['late_tasks'], 1);
    expect(o['spent_total'], 1000);
    expect(o['received_from_client'], 50000);
    expect(o['daily_report_done_today'], isTrue);
  });

  test('update_task marks done, or sets progress', () async {
    await tools.run('add_task', {'project_id': 'p1', 'title': 'Plaster'});
    final tasks = await read('list_tasks', {'only_open': true}) as List;
    final id = tasks.single['id'] as String;
    await tools.run('update_task', {'task_id': id, 'progress': 40});
    expect((await db.taskDao.forProject('p1')).single.progress, 40);
    await tools.run('update_task', {'task_id': id, 'done': true});
    expect((await db.taskDao.forProject('p1')).single.status, 'done');
    expect(await read('list_tasks', {'only_open': true}), isEmpty);
    expect((await tools.run('update_task', {'task_id': 'nope', 'done': true})).isError, isTrue);
  });

  test('stock_summary nets material received against used', () async {
    await tools.run('record_material_received', {'project_id': 'p1', 'material': 'Cement', 'quantity': 100, 'unit': 'bags'});
    await tools.run('record_material_used', {'project_id': 'p1', 'material': 'cement', 'quantity': 35, 'unit': 'bags'});
    final stock = await read('stock_summary', {'project_id': 'p1'}) as List;
    expect(stock.single['left'], 65);
  });

  test('create_project starts an active site for this company', () async {
    final out = await tools.run('create_project', {'name': 'Kompally Tower', 'client_name': 'Mr Rao'});
    expect(out.changedProjects, isTrue);
    final ps = await db.projectDao.forCompany('c1');
    expect(ps.map((p) => p.name), containsAll(['Narapally Villa', 'Kompally Tower']));
  });

  test('describe gives the confirm card a plain line, and refuses what cannot be saved', () async {
    final line = await tools.describe('add_expense', {'project_id': 'p1', 'amount': 125000, 'category': 'Labour'});
    expect(line, 'Expense ₹1,25,000 for Labour at Narapally Villa');
    expect(await tools.describe('mark_attendance', {'project_id': 'p1', 'worker_names': ['A', 'B']}),
        'Mark present at Narapally Villa: A, B');
    expect(() => tools.describe('add_expense', {'project_id': 'other', 'amount': 1, 'category': 'Fuel'}),
        throwsA(isA<ToolInputError>()));
  });

  test('open_screen hands back a button; project screens need a real project', () async {
    final out = await tools.run('open_screen', {'screen': 'money', 'project_id': 'p1'});
    expect(out.link?.screen, 'money');
    expect(out.link?.projectId, 'p1');
    expect((await tools.run('open_screen', {'screen': 'money'})).isError, isTrue);
    expect((await tools.run('open_screen', {'screen': 'dashboard'})).link?.screen, 'dashboard');
  });

  test('the phone runs exactly the tools the server offers', () async {
    final src = File('../supabase/functions/ai-assistant/tools.ts').readAsStringSync();
    final offered = {for (final m in RegExp(r'name: "(\w+)"').allMatches(src)) m.group(1)!};
    final serverWrites = RegExp(r'WRITE_TOOLS = new Set\(\[([^\]]*)\]').firstMatch(src)!.group(1)!;
    expect({for (final m in RegExp(r'"(\w+)"').allMatches(serverWrites)) m.group(1)!}, writeTools);
    for (final name in offered) {
      final out = await tools.run(name, {});
      expect(out.result, isNot(contains('Unknown action')), reason: name);
    }
  });
}
