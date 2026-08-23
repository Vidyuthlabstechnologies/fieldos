/// Same real-infrastructure discipline as test/sync_engine_test.dart and
/// test/sync_engine_more_entities_test.dart, covering the third wave of
/// wired entities: Equipment and Inspections. Deliberately does NOT cover
/// EquipmentLogs or InspectionItems (child/detail rows) -- see
/// lib/sync/sync_mappers.dart's docstring.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _serviceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

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

  test('Equipment and Inspection each push through the outbox and land in real Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-equip-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Equipment Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final equip = await db.equipmentDao.create(EquipmentCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      name: 'Tower Crane #1',
      equipmentType: const Value('crane'),
      dailyRate: const Value(8500.0),
    ));
    final inspection = await db.inspectionDao.create(InspectionsCompanion.insert(
      id: _uuid.v4(),
      projectId: projectId,
      title: 'Weekly safety walk',
      inspectionType: 'safety',
      scheduledDate: Value(DateTime(2026, 1, 5)),
    ));

    expect(await db.syncOutboxDao.pendingCount(), 2);

    final result = await engine.pushPending();
    expect(result.succeeded, 2);
    expect(result.failed, 0);
    expect(await db.syncOutboxDao.pending(), isEmpty);

    final remoteEquip = await adminClient.from('equipment').select().eq('id', equip.id);
    expect(remoteEquip.length, 1);
    expect(remoteEquip.first['name'], 'Tower Crane #1');
    expect((remoteEquip.first['daily_rate'] as num).toDouble(), 8500.0);

    final remoteInspection = await adminClient.from('inspections').select().eq('id', inspection.id);
    expect(remoteInspection.length, 1);
    expect(remoteInspection.first['inspection_type'], 'safety');
    expect(remoteInspection.first['scheduled_date'], '2026-01-05');

    // Now the update paths: mark equipment in_use, complete the inspection.
    await db.equipmentDao.updateStatus(equip.id, 'in_use');
    await db.inspectionDao.complete(inspection.id, 'pass');
    final updateResult = await engine.pushPending();
    expect(updateResult.succeeded, 2);

    final inUseRemote = await adminClient.from('equipment').select().eq('id', equip.id);
    expect(inUseRemote.first['status'], 'in_use');

    final completedRemote = await adminClient.from('inspections').select().eq('id', inspection.id);
    expect(completedRemote.first['status'], 'completed');
    expect(completedRemote.first['overall_result'], 'pass');
    expect(completedRemote.first['completed_date'], isNotNull);

    await userClient.dispose();
    await adminClient.dispose();
  });

  test('pullAll merges Equipment and Inspections created directly in Postgres', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-equip-pull-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final projectId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull Equipment Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('projects').insert({'id': projectId, 'company_id': companyId, 'name': 'P', 'status': 'active'});

    final equipId = _uuid.v4();
    final inspectionId = _uuid.v4();
    await adminClient.from('equipment').insert({
      'id': equipId,
      'project_id': projectId,
      'name': 'Remote-created Excavator',
      'equipment_type': 'excavator',
      'status': 'available',
    });
    await adminClient.from('inspections').insert({
      'id': inspectionId,
      'project_id': projectId,
      'title': 'Remote-created inspection',
      'inspection_type': 'quality',
    });

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);
    await engine.pullAll();

    final localEquipment = await db.equipmentDao.forProject(projectId);
    expect(localEquipment.any((e) => e.id == equipId && e.name == 'Remote-created Excavator'), isTrue);

    final localInspections = await db.inspectionDao.forProject(projectId);
    expect(localInspections.any((i) => i.id == inspectionId && i.title == 'Remote-created inspection'), isTrue);

    await userClient.dispose();
    await adminClient.dispose();
  });
}
