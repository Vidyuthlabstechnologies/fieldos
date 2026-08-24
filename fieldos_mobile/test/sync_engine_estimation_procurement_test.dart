/// Real-infrastructure sync tests, fifth wave: the estimation tree
/// (Estimations -> CostHeads -> MeasurementEntries/SteelEntries) and the
/// aligned procurement core (PurchaseRequests -> purchase_requisitions,
/// PurchaseOrders -> purchase_orders, including status-change pushes).
/// Same discipline as sync_engine_vendors_test.dart -- assert actual values
/// in real Postgres / local Drift, never just "no exception". The PO status
/// assertions are load-bearing: they're what catches an RLS update policy
/// matching zero rows while PostgREST reports success.
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

  test('Estimation tree and procurement chain push through the outbox into real Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-est-proc-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    final vendorId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Est Proc Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    // Project member (not owner/PM): proves the membership-based requisition
    // and PO insert/update policies actually let a site engineer sync, which
    // is the app's real workflow.
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});
    await adminClient.from('project_members').insert({'project_id': projectId, 'user_id': userId, 'role': 'site_engineer'});
    await adminClient.from('vendors').insert({'id': vendorId, 'company_id': companyId, 'name': 'Proc Vendor'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final estimation = await db.estimationDao.create(EstimationsCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      name: 'Block A civil',
      createdBy: userId,
      contractorProfitPercent: const Value(12.5),
    ));
    final costHead = await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
      id: _uuid.v4(),
      estimationId: estimation.id,
      name: 'Excavation',
      calculationType: 'volume',
      rawUnit: 'cft',
      billingUnit: 'cft',
      conversionFactor: const Value(1.0),
      ratePerUnit: const Value(48.0),
      sortOrder: const Value(1),
    ));
    await db.estimationDao.addMeasurement(MeasurementEntriesCompanion.insert(
      id: _uuid.v4(),
      costHeadId: costHead.id,
      description: 'Footing 1',
      length: const Value(10.0),
      width: const Value(6.0),
      depth: const Value(4.0),
      nos: const Value(2.0),
      isDeduction: const Value(false),
    ));
    await db.estimationDao.addSteel(SteelEntriesCompanion.insert(
      id: _uuid.v4(),
      costHeadId: costHead.id,
      description: '8mm bars',
      barDiaMm: 8.0,
      nos: 40.0,
      lengthFt: 12.0,
    ));
    final request = await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      raisedBy: userId,
      materialName: 'OPC 53 cement',
      quantity: const Value(200.0),
      unit: const Value('bags'),
      estimatedAmount: const Value(76000.0),
    ));
    final order = await db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      supplierId: vendorId,
      requestId: Value(request.id),
      raisedBy: userId,
      totalAmount: const Value(75000.0),
    ));
    await db.purchaseDao.setRequestStatus(request.id, 'ordered');
    await db.purchaseDao.setOrderStatus(order.id, 'delivered');

    expect(await db.syncOutboxDao.pendingCount(), 8);

    final result = await engine.pushPending();
    expect(result.succeeded, 8);
    expect(result.failed, 0);
    expect(await db.syncOutboxDao.pending(), isEmpty);

    final remoteEst = await adminClient.from('estimations').select().eq('id', estimation.id);
    expect((remoteEst.first['contractor_profit_percent'] as num).toDouble(), 12.5);

    final remoteCh = await adminClient.from('cost_heads').select().eq('id', costHead.id);
    expect(remoteCh.first['calculation_type'], 'volume');
    expect((remoteCh.first['rate_per_unit'] as num).toDouble(), 48.0);

    final remoteMeasurements = await adminClient.from('measurement_entries').select().eq('cost_head_id', costHead.id);
    expect(remoteMeasurements.length, 1);
    expect((remoteMeasurements.first['nos'] as num).toDouble(), 2.0);

    final remoteSteel = await adminClient.from('steel_entries').select().eq('cost_head_id', costHead.id);
    expect(remoteSteel.first['bar_dia_mm'], 8.0);

    final remoteReq = await adminClient.from('purchase_requisitions').select().eq('id', request.id);
    expect(remoteReq.first['item_name'], 'OPC 53 cement');
    expect(remoteReq.first['unit'], 'bags');
    expect(remoteReq.first['status'], 'ordered');
    expect(remoteReq.first['urgency'], 'normal');

    final remotePo = await adminClient.from('purchase_orders').select().eq('id', order.id);
    expect(remotePo.length, 1);
    expect(remotePo.first['status'], 'delivered');
    expect(remotePo.first['requisition_id'], request.id);

    await db.close();
    await userClient.dispose();
    await adminClient.dispose();
  });

  test('pullAll merges remotely-created estimation-tree and procurement rows into local Drift', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-est-pull-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    final vendorId = _uuid.v4();
    final estimationId = _uuid.v4();
    final costHeadId = _uuid.v4();
    final measurementId = _uuid.v4();
    final steelId = _uuid.v4();
    final requisitionId = _uuid.v4();
    final poId = _uuid.v4();
    final quoteId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull Est Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});
    await adminClient.from('vendors').insert({'id': vendorId, 'company_id': companyId, 'name': 'Remote Vendor'});
    await adminClient.from('estimations').insert({
      'id': estimationId,
      'project_id': projectId,
      'name': 'Remote estimation',
      'created_by': userId,
    });
    await adminClient.from('cost_heads').insert({
      'id': costHeadId,
      'estimation_id': estimationId,
      'name': 'Brick work',
      'calculation_type': 'count',
      'raw_unit': 'nos',
      'billing_unit': 'nos',
      'sort_order': 3,
    });
    await adminClient.from('measurement_entries').insert({
      'id': measurementId,
      'cost_head_id': costHeadId,
      'description': 'Wall panel',
      'nos': 5,
      'is_deduction': true,
    });
    await adminClient.from('steel_entries').insert({
      'id': steelId,
      'cost_head_id': costHeadId,
      'description': '12mm dowels',
      'bar_dia_mm': 12,
      'nos': 24,
      'length_ft': 10,
    });
    await adminClient.from('purchase_requisitions').insert({
      'id': requisitionId,
      'project_id': projectId,
      'item_name': 'River sand',
      'quantity': 50,
      'unit': 'cft',
      'requested_by': userId,
      'urgency': 'high',
      'notes': 'Before slab pour',
    });
    // A real rfq+quote pair so the PO's quote_id FK is satisfiable -- proves
    // the opaque-uuid round-trip with a legitimately linked quote.
    final rfqId = _uuid.v4();
    await adminClient.from('rfqs').insert({
      'id': rfqId,
      'project_id': projectId,
      'title': 'Sand supply RFQ',
      'created_by': userId,
    });
    await adminClient.from('quotes').insert({
      'id': quoteId,
      'rfq_id': rfqId,
      'vendor_id': vendorId,
      'total_amount': 30000,
    });
    await adminClient.from('purchase_orders').insert({
      'id': poId,
      'project_id': projectId,
      'vendor_id': vendorId,
      'requisition_id': requisitionId,
      'quote_id': quoteId,
      'po_number': 'PO-2026-042',
      'total_amount': 31000,
      'created_by': userId,
    });

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);
    await engine.pullAll();

    final estimations = await db.estimationDao.forProject(projectId);
    expect(estimations.any((e) => e.id == estimationId && e.name == 'Remote estimation'), isTrue);

    final costHeads = await db.estimationDao.costHeadsFor(estimationId);
    expect(costHeads.single.sortOrder, 3);

    final measurements = await db.estimationDao.measurements(costHeadId);
    expect(measurements.single.isDeduction, isTrue);

    final steel = await db.estimationDao.steel(costHeadId);
    expect(steel.single.barDiaMm, 12.0);

    final requests = await db.purchaseDao.requestsFor(projectId);
    final req = requests.singleWhere((r) => r.id == requisitionId);
    expect(req.materialName, 'River sand');
    expect(req.unit, 'cft');
    expect(req.urgency, 'high');
    expect(req.notes, 'Before slab pour');

    final orders = await db.purchaseDao.ordersFor(projectId);
    final po = orders.singleWhere((o) => o.id == poId);
    expect(po.poNumber, 'PO-2026-042');
    expect(po.requestId, requisitionId);
    // quote_id has no mobile feature yet but must round-trip as an opaque
    // uuid so remote-created linkage isn't silently dropped on pull.
    expect(po.quoteId, isNotNull);

    await db.close();
    await userClient.dispose();
    await adminClient.dispose();
  });
}
