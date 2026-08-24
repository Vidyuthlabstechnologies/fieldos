/// Same real-infrastructure discipline as test/sync_engine_equipment_inspections_test.dart,
/// covering the fourth wave of wired entities: Subcontractors, WorkOrders,
/// and Approvals. See lib/sync/sync_mappers.dart's docstring for what's
/// deliberately still not wired (Documents, LabourAttendance, MaterialReceipts).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _serviceRoleKey = localServiceRoleKey;

final _uuid = Uuid();

Future<bool> _localStackReachable() async {
  try {
    final res = await http.get(Uri.parse('${SyncConfig.local.url}/rest/v1/')).timeout(const Duration(seconds: 2));
    return res.statusCode < 500;
  } catch (_) {
    return false;
  }
}

void main() {
  late bool stackUp;

  setUpAll(() async {
    stackUp = await _localStackReachable();
  });

  test('Subcontractor, WorkOrder, and Approval each push through the outbox and land in real Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-subco-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Subco Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final subco = await db.subcontractorDao.create(SubcontractorsCompanion.insert(
      id: _uuid.v4(),
      companyId: companyId,
      name: 'ACME Electrical',
      trade: const Value('electrical'),
    ));
    final workOrder = await db.workOrderDao.createWorkOrder(WorkOrdersCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      subcontractorId: subco.id,
      description: 'Wire the third floor',
      agreedAmount: const Value(150000.0),
    ));
    final approval = await db.approvalDao.create(ApprovalsCompanion.insert(
      id: _uuid.v4(),
      entityType: 'work_order',
      entityId: workOrder.id,
      requestedBy: userId,
      projectId: Value(projectId),
    ));

    expect(await db.syncOutboxDao.pendingCount(), 3);

    final result = await engine.pushPending();
    expect(result.succeeded, 3);
    expect(result.failed, 0);
    expect(await db.syncOutboxDao.pending(), isEmpty);

    final remoteSubco = await adminClient.from('subcontractors').select().eq('id', subco.id);
    expect(remoteSubco.length, 1);
    expect(remoteSubco.first['name'], 'ACME Electrical');

    final remoteWorkOrder = await adminClient.from('work_orders').select().eq('id', workOrder.id);
    expect(remoteWorkOrder.length, 1);
    expect((remoteWorkOrder.first['agreed_amount'] as num).toDouble(), 150000.0);

    final remoteApproval = await adminClient.from('approvals').select().eq('id', approval.id);
    expect(remoteApproval.length, 1);
    expect(remoteApproval.first['status'], 'pending');

    // Update paths: bill the work order, decide the approval.
    await db.workOrderDao.billWorkOrder(workOrder.id, 25000.0);
    await db.approvalDao.decide(approval.id, true, userId, 'Looks good');
    final updateResult = await engine.pushPending();
    expect(updateResult.succeeded, 2);

    final billedRemote = await adminClient.from('work_orders').select().eq('id', workOrder.id);
    expect((billedRemote.first['billed_amount'] as num).toDouble(), 25000.0);

    final decidedRemote = await adminClient.from('approvals').select().eq('id', approval.id);
    expect(decidedRemote.first['status'], 'approved');
    expect(decidedRemote.first['decision_note'], 'Looks good');
    expect(decidedRemote.first['decided_at'], isNotNull);

    await userClient.dispose();
    await adminClient.dispose();
  });

  test('pullAll merges Subcontractors, WorkOrders, and Approvals created directly in Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-subco-pull-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull Subco Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final subcoId = _uuid.v4();
    final workOrderId = _uuid.v4();
    final approvalId = _uuid.v4();
    await adminClient.from('subcontractors').insert({
      'id': subcoId,
      'company_id': companyId,
      'name': 'Remote-created Subco',
      'trade': 'plumbing',
    });
    await adminClient.from('work_orders').insert({
      'id': workOrderId,
      'project_id': projectId,
      'subcontractor_id': subcoId,
      'description': 'Remote-created work order',
    });
    await adminClient.from('approvals').insert({
      'id': approvalId,
      'project_id': projectId,
      'entity_type': 'work_order',
      'entity_id': workOrderId,
      'requested_by': userId,
    });

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);
    await engine.pullAll();

    final localSubcos = await db.subcontractorDao.forCompany(companyId);
    expect(localSubcos.any((s) => s.id == subcoId && s.name == 'Remote-created Subco'), isTrue);

    final localWorkOrders = await db.workOrderDao.workOrdersFor(projectId);
    expect(localWorkOrders.any((w) => w.id == workOrderId && w.description == 'Remote-created work order'), isTrue);

    final localApprovals = await db.approvalDao.pendingFor(projectId);
    expect(localApprovals.any((a) => a.id == approvalId), isTrue);

    await userClient.dispose();
    await adminClient.dispose();
  });
}
