/// Site attendance, expenses, material and money-in sync, against the local
/// Supabase stack (skips itself if it is not running).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

final _uuid = Uuid();

Future<bool> _localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

class _MemoryStore implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? sessionJson) async => value = sessionJson;
}

/// One phone: its own local database, local account, Supabase client.
class _Phone {
  _Phone._(this.db, this.client, this.engine, this.service, this.localUserId, this.store);

  final AppDatabase db;
  final SupabaseClient client;
  final SyncEngine engine;
  final CloudSyncService service;
  final String localUserId;
  final _MemoryStore store;

  static Future<_Phone> signUp(String label) async {
    final db = AppDatabase.memory();
    final client = SyncConfig.local.createClient();
    final engine = SyncEngine(db: db, client: client);
    final store = _MemoryStore();
    final service = CloudSyncService(client: client, engine: engine, sessionStore: store);
    final localUserId = _uuid.v4(); // the phone's own pbkdf2 account id
    engine.localUserId = localUserId;
    final result = await service.enableSync(email: '$label-${_uuid.v4()}@test.local', password: 'test-password-123!');
    expect(result.outcome, CloudSyncOutcome.signedUp);
    return _Phone._(db, client, engine, service, localUserId, store);
  }

  String get remoteUserId => client.auth.currentUser!.id;

  Future<void> close() async {
    await service.dispose();
    await engine.dispose();
    await client.dispose();
    await db.close();
  }
}

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await _localStackReachable());

  test('site attendance, money and material reach the owner; money-in stays with owners and PMs', () async {
    if (!stackUp) {
      markTestSkipped('local Supabase stack not running');
      return;
    }
    final owner = await _Phone.signUp('owner');
    final engineer = await _Phone.signUp('engineer');
    final company = await owner.db.companyDao.create('Site Records Co');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(), companyId: company.id, name: 'Block C', status: const Value('active')));
    expect((await owner.engine.pushPending()).failed, 0);
    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();

    // Engineer on site, writing offline under the phone's local id.
    final e = engineer.db;
    final worker = await e.workerDao.create(WorkersCompanion.insert(
        projectId: project.id, name: 'Ramesh', id: _uuid.v4(), dailyWage: const Value(800)));
    final punch = await e.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: _uuid.v4(), projectId: project.id, workerName: 'Ramesh', workerId: Value(worker.id),
      recordedBy: engineer.localUserId, punchIn: DateTime.utc(2026, 11, 5, 3, 30), lat: const Value(17.4), lng: const Value(78.5)));
    await e.attendanceDao.punchOut(punch.id);
    await e.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(), projectId: project.id, category: 'Labour', amount: 500, incurredOn: '2026-11-05',
      recordedBy: engineer.localUserId, note: const Value('Advance'), workerId: Value(worker.id)));
    await e.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
      id: _uuid.v4(), projectId: project.id, materialName: 'Cement', quantity: 50, unit: const Value('bags'),
      amount: 19000, receivedBy: engineer.localUserId, receivedOn: DateTime.utc(2026, 11, 5)));
    await e.materialDao.recordUsage(MaterialUsageCompanion.insert(
      id: _uuid.v4(), projectId: project.id, materialName: 'Cement', quantity: 12, unit: const Value('bags'),
      recordedBy: engineer.localUserId, usedOn: DateTime.utc(2026, 11, 5)));
    final push = await engineer.engine.pushPending();
    expect(push.failed, 0, reason: 'worker, punch in, punch out, expense, receipt, usage');
    expect(push.succeeded, 6);

    // A site engineer can't record money received (owner/PM only).
    await e.paymentDao.create(PaymentsReceivedCompanion.insert(
      id: _uuid.v4(), projectId: project.id, amount: 100000, receivedOn: DateTime.utc(2026, 11, 5),
      fromParty: 'Client', mode: 'bank', recordedBy: engineer.localUserId));
    expect((await engineer.engine.pushPending()).failed, 1);

    // Owner sees it all from the office.
    await owner.db.paymentDao.create(PaymentsReceivedCompanion.insert(
      id: _uuid.v4(), projectId: project.id, amount: 250000, receivedOn: DateTime.utc(2026, 11, 4),
      fromParty: 'Mr Rao (client)', mode: 'upi', recordedBy: owner.localUserId));
    expect((await owner.engine.pushPending()).failed, 0);
    await owner.engine.pullAll();
    final punches = await owner.db.attendanceDao.forProject(project.id);
    expect(punches.single.punchOut, isNotNull, reason: 'the punch-out update synced too');
    expect(punches.single.recordedBy, engineer.remoteUserId);
    final expenses = await owner.db.expenseDao.forProject(project.id);
    expect(expenses.single.workerId, worker.id);
    expect((await owner.db.materialDao.forProject(project.id)).single.quantity, 50);
    expect((await owner.db.materialDao.usageForProject(project.id)).single.quantity, 12);
    expect((await owner.db.paymentDao.forProject(project.id)).single.amount, 250000);

    // ...and the engineer never receives the company's money-in.
    final engineerSees = await engineer.client.from('site_payments_received').select().eq('project_id', project.id);
    expect(engineerSees, isEmpty);

    // Nobody records an expense in a colleague's name.
    await expectLater(
      engineer.client.from('site_expenses').insert({
        'id': _uuid.v4(), 'project_id': project.id, 'category': 'Other', 'amount': 1, 'incurred_on': '2026-11-05',
        'recorded_by': owner.remoteUserId,
      }),
      throwsA(isA<PostgrestException>()),
    );

    await owner.close();
    await engineer.close();
  });
}
