/// Real-infrastructure sync tests for the procurement chain's first wired
/// table: Supplier (-> Postgres `vendors`). Same discipline as
/// test/sync_engine_subcontractors_test.dart -- a real service_role admin
/// client seeds company/project, a real user client signs in, and every
/// assertion checks the actual synced value in real Postgres / local Drift,
/// not just "no exception".
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

  test('Supplier push through the outbox lands every field in real Postgres vendors', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-vendor-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Vendor Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);

    final supplier = await db.supplierDao.create(SuppliersCompanion.insert(
      id: _uuid.v4(),
      companyId: companyId,
      name: 'Bharat Cement Traders',
      contactPerson: const Value('Ravi Kumar'),
      contactPhone: const Value('+91 98765 43210'),
      email: const Value('ravi@bharatcement.example'),
      address: const Value('Plot 14, Industrial Area'),
      gstNumber: const Value('36ABCDE1234F1Z5'),
      category: const Value('cement'),
      notes: const Value('Net 30 days credit'),
    ));

    expect(await db.syncOutboxDao.pendingCount(), 1);

    final result = await engine.pushPending();
    expect(result.succeeded, 1);
    expect(result.failed, 0);
    expect(await db.syncOutboxDao.pending(), isEmpty);

    // Assert the actual remote row, not just that the push didn't throw --
    // under RLS an unauthorized update can "succeed" while matching zero
    // rows (the work_orders lesson).
    final remote = await adminClient.from('vendors').select().eq('id', supplier.id);
    expect(remote.length, 1);
    final vendor = remote.first;
    expect(vendor['company_id'], companyId);
    expect(vendor['name'], 'Bharat Cement Traders');
    expect(vendor['contact_person'], 'Ravi Kumar');
    expect(vendor['phone'], '+91 98765 43210');
    expect(vendor['email'], 'ravi@bharatcement.example');
    expect(vendor['address'], 'Plot 14, Industrial Area');
    expect(vendor['gst_number'], '36ABCDE1234F1Z5');
    expect(vendor['category'], 'cement');
    expect(vendor['notes'], 'Net 30 days credit');

    await db.close();
    await userClient.dispose();
    await adminClient.dispose();
  });

  test('pullAll merges a remotely-created vendor (all fields) into local Drift', () async {
    if (!stackUp) return;

    final adminClient = SupabaseClient(SyncConfig.local.url, _serviceRoleKey);
    final email = 'sync-vendor-pull-${_uuid.v4()}@test.local';
    final password = 'test-password-123!';
    final signUp = await adminClient.auth.admin.createUser(
      AdminUserAttributes(email: email, password: password, emailConfirm: true),
    );
    final userId = signUp.user!.id;

    final companyId = _uuid.v4();
    final vendorId = _uuid.v4();
    await adminClient.from('companies').insert({'id': companyId, 'name': 'Pull Vendor Co'});
    await adminClient.from('company_members').insert({'company_id': companyId, 'user_id': userId, 'role': 'owner'});
    await adminClient.from('vendors').insert({
      'id': vendorId,
      'company_id': companyId,
      'name': 'Steel Syndicate',
      'contact_person': 'Meena Iyer',
      'phone': '+91 91234 56780',
      'email': 'meena@steelsyndicate.example',
      'address': 'Godown 7, Steel Market',
      'gst_number': '36AAACP0000A1Z2',
      'category': 'steel',
      'notes': 'Prefers UPI',
    });

    final userClient = SupabaseClient(SyncConfig.local.url, SyncConfig.local.anonKey);
    await userClient.auth.signInWithPassword(email: email, password: password);

    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: userClient);
    await engine.pullAll();

    final localSuppliers = await db.supplierDao.forCompany(companyId);
    final pulled = localSuppliers.where((s) => s.id == vendorId).toList();
    expect(pulled.length, 1);
    // Every Postgres business column must survive the round trip into local
    // Drift -- dropping any of these silently is what this wiring exists to
    // prevent.
    expect(pulled.single.name, 'Steel Syndicate');
    expect(pulled.single.contactPerson, 'Meena Iyer');
    expect(pulled.single.contactPhone, '+91 91234 56780');
    expect(pulled.single.email, 'meena@steelsyndicate.example');
    expect(pulled.single.address, 'Godown 7, Steel Market');
    expect(pulled.single.gstNumber, '36AAACP0000A1Z2');
    expect(pulled.single.category, 'steel');
    expect(pulled.single.notes, 'Prefers UPI');

    await db.close();
    await userClient.dispose();
    await adminClient.dispose();
  });
}
