/// The real-app path onto the cloud, end to end against the local Supabase
/// stack: no service_role seeding of companies or memberships (every older
/// sync test did that, which is how it went unnoticed that the app itself
/// never could). Owner signs up -> registers the phone's local company ->
/// pushes work written under the LOCAL user id -> a colleague joins with
/// the code -> both see each other's data and chat. Plus the pull-safety
/// rules: unpushed edits survive a pull, and pulls page past 1,000 rows.
/// Skips itself if the stack isn't running (see sync_engine_test.dart).
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

  setUpAll(() async {
    stackUp = await _localStackReachable();
  });

  test('owner registers the local company, colleague joins by code, both share work and chat', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('owner');
    final engineer = await _Phone.signUp('engineer');

    // Owner's phone: a company created offline, then put on the cloud.
    final company = await owner.db.companyDao.create('Sri Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    expect(cloud.role, 'owner');
    expect(cloud.joinCode, isNotNull);
    expect(cloud.joinCode!.length, 10);

    // Work written offline under the phone's LOCAL user id.
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: company.id,
      name: 'Narapally Block A',
      status: const Value('active'),
    ));
    final dpr = await owner.db.dprDao.create(DprEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      createdBy: owner.localUserId,
      entryDate: DateTime.utc(2026, 11, 5),
      workSummary: 'Slab shuttering, 2nd floor',
    ));
    final push = await owner.engine.pushPending();
    expect(push.failed, 0, reason: 'project + DPR must be accepted by RLS and the auth.users FK');
    expect(push.succeeded, 2);

    final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
    final remoteDpr = await admin.from('dpr_entries').select().eq('id', dpr.id).single();
    expect(remoteDpr['created_by'], owner.remoteUserId, reason: 'local user id rewritten to the Supabase user id');

    // Colleague joins with the code (spaces / lowercase tolerated).
    final code = cloud.joinCode!;
    final joined = await engineer.service.joinCompany(' ${code.substring(0, 5).toLowerCase()} ${code.substring(5)} ');
    expect(joined.companyId, company.id);
    expect(joined.role, 'site_engineer');
    expect(joined.name, 'Sri Sai Constructions');

    // ...and a site engineer sees the company's projects without any
    // per-project assignment, but still cannot create one.
    await engineer.engine.pullAll();
    expect((await engineer.db.projectDao.byId(project.id))?.name, 'Narapally Block A');
    final pulledDpr = await engineer.db.dprDao.byId(dpr.id);
    expect(pulledDpr?.createdBy, owner.remoteUserId, reason: "a colleague's id passes through unmapped");

    await expectLater(
      engineer.client.from('projects').insert({'id': _uuid.v4(), 'company_id': company.id, 'name': 'Not allowed'}),
      throwsA(isA<PostgrestException>()),
    );

    // Engineer chats from site; owner pulls it.
    await engineer.db.messageDao.send(
      projectId: project.id,
      senderId: engineer.localUserId,
      senderName: 'Ravi (site)',
      body: 'Concrete truck delayed 2 hours',
    );
    expect((await engineer.engine.pushPending()).failed, 0);

    final alerts = <String>[];
    owner.engine.onRemoteRowCreated = (table, row) => alerts.add('$table:${row['body']}');
    await owner.engine.pullAll();
    final ownerMessages = await owner.db.messageDao.forProject(project.id);
    expect(ownerMessages.single.body, 'Concrete truck delayed 2 hours');
    expect(ownerMessages.single.senderId, engineer.remoteUserId);
    expect(alerts, ['project_messages:Concrete truck delayed 2 hours']);

    // The owner's own DPR comes back mapped to the owner's local id.
    expect((await owner.db.dprDao.byId(dpr.id))?.createdBy, owner.localUserId);

    // Nobody can post a message as someone else.
    await expectLater(
      engineer.client.from('project_messages').insert({
        'project_id': project.id,
        'sender_id': owner.remoteUserId,
        'sender_name': 'Fake owner',
        'body': 'Approve everything',
      }),
      throwsA(isA<PostgrestException>()),
    );

    // Team screen data + owner-only controls.
    final roster = await owner.service.roster(company.id);
    expect(roster.map((m) => m.role), containsAll(['owner', 'site_engineer']));
    await owner.service.setMemberRole(companyId: company.id, userId: engineer.remoteUserId, role: 'project_manager');
    final promoted = await engineer.service.registerCompany(companyId: company.id, name: company.name);
    expect(promoted.role, 'project_manager');
    expect(promoted.joinCode, code, reason: 'managers can share the code too');
    await expectLater(
      engineer.service.setMemberRole(companyId: company.id, userId: owner.remoteUserId, role: 'site_engineer'),
      throwsA(isA<PostgrestException>()),
    );
    final newCode = await owner.service.regenerateJoinCode(company.id);
    expect(newCode, isNot(code));

    await admin.dispose();
    await owner.close();
    await engineer.close();
  });

  test('a stranger cannot take over a registered company or join with a bad code', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('owner');
    final stranger = await _Phone.signUp('stranger');
    final company = await owner.db.companyDao.create('Owner Co');
    await owner.service.registerCompany(companyId: company.id, name: company.name);

    await expectLater(
      stranger.service.registerCompany(companyId: company.id, name: 'Hijack'),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(stranger.service.joinCompany('0000000000'), throwsA(isA<PostgrestException>()));
    await stranger.engine.pullAll();
    expect(await stranger.db.projectDao.forCompany(company.id), isEmpty);

    await owner.close();
    await stranger.close();
  });

  test('a site location set on one phone reaches the others (projects update policy)', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('owner');
    final company = await owner.db.companyDao.create('Geo Co');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: company.id,
      name: 'Site with a fence',
    ));
    await owner.db.geofenceDao.set(project.id, 17.4321, 78.5432, 150);
    expect((await owner.engine.pushPending()).failed, 0);

    final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
    final remote = await admin.from('projects').select().eq('id', project.id).single();
    expect(remote['location_lat'], 17.4321);
    expect(remote['geofence_radius_m'], 150);

    final fence = await owner.db.geofenceDao.effectiveFor(project.id);
    expect(fence?.radiusMeters, 150);

    await admin.dispose();
    await owner.close();
  });

  test('pull never overwrites an edit that has not been pushed yet', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('owner');
    final company = await owner.db.companyDao.create('Offline Co');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: company.id,
      name: 'Original name',
    ));
    expect((await owner.engine.pushPending()).failed, 0);

    // Another device renames it on the server...
    final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
    await admin.from('projects').update({'name': 'Server rename'}).eq('id', project.id);

    // ...while this phone, offline, changes the site location (queued).
    await owner.db.projectDao.setLocation(project.id, lat: 12.9, lng: 77.6, radiusM: 80);
    expect(await owner.db.syncOutboxDao.pendingCount(), 1);

    await owner.engine.pullAll();
    final local = await owner.db.projectDao.byId(project.id);
    expect(local?.locationLat, 12.9, reason: 'the unpushed local edit must survive the pull');

    // Once pushed, the next pull merges normally again.
    expect((await owner.engine.pushPending()).failed, 0);
    await owner.engine.pullAll();
    expect((await owner.db.projectDao.byId(project.id))?.locationLat, 12.9);

    await admin.dispose();
    await owner.close();
  });

  test('pull pages past the 1,000-row PostgREST cap', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('owner');
    final company = await owner.db.companyDao.create('Big Co');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: company.id,
      name: 'Large site',
    ));
    expect((await owner.engine.pushPending()).failed, 0);

    final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
    const total = 1203;
    final rows = [
      for (var i = 0; i < total; i++) {'id': _uuid.v4(), 'project_id': project.id, 'title': 'Task $i'},
    ];
    for (var i = 0; i < rows.length; i += 400) {
      await admin.from('tasks').insert(rows.sublist(i, i + 400 > rows.length ? rows.length : i + 400));
    }

    await owner.engine.pullAll();
    expect((await owner.db.taskDao.forProject(project.id)).length, total);

    await admin.dispose();
    await owner.close();
  });

  test('a saved session resumes after an app restart without the password', () async {
    if (!stackUp) return;
    final first = await _Phone.signUp('restart');
    final saved = first.store.value;
    expect(saved, isNotNull, reason: 'sign-up must persist the session');
    final userId = first.remoteUserId;
    await first.close();

    // "Restart": brand-new client and service, same persisted store.
    final client = SyncConfig.local.createClient();
    final db = AppDatabase.memory();
    final engine = SyncEngine(db: db, client: client);
    final store = _MemoryStore()..value = saved;
    final service = CloudSyncService(client: client, engine: engine, sessionStore: store);
    expect(service.isSignedIn, isFalse);
    expect(await service.restoreSession(), isTrue);
    expect(client.auth.currentUser?.id, userId);

    // A garbage saved session is dropped, not retried forever.
    final badStore = _MemoryStore()..value = '{"not":"a session"}';
    final client2 = SyncConfig.local.createClient();
    final service2 = CloudSyncService(client: client2, engine: SyncEngine(db: db, client: client2), sessionStore: badStore);
    expect(await service2.restoreSession(), isFalse);

    await service.dispose();
    await service2.dispose();
    await client.dispose();
    await client2.dispose();
    await db.close();
  });

  test('deleting an account removes a solo company and the login', () async {
    if (!stackUp) return;
    final solo = await _Phone.signUp('solo');
    final email = solo.service.email!;
    final company = await solo.db.companyDao.create('One-man Builders');
    await solo.service.registerCompany(companyId: company.id, name: company.name);
    final project = await solo.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: company.id,
      name: 'Solo site',
      status: const Value('active'),
    ));
    await solo.db.dprDao.create(DprEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      createdBy: solo.localUserId,
      entryDate: DateTime.utc(2026, 11, 5),
      workSummary: 'Footing excavation',
    ));
    expect((await solo.engine.pushPending()).failed, 0);

    final result = await solo.service.deleteAccount();
    expect(result.companiesDeleted, 1);
    expect(result.companiesLeft, 0);
    expect(solo.service.isSignedIn, isFalse);
    expect(solo.store.value, isNull);

    final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
    expect(await admin.from('companies').select().eq('id', company.id), isEmpty);
    expect(await admin.from('projects').select().eq('id', project.id), isEmpty);
    await expectLater(
      solo.client.auth.signInWithPassword(email: email, password: 'test-password-123!'),
      throwsA(isA<AuthException>()),
    );
    await admin.dispose();
    await solo.close();
  });

  test('deleting an owner account in a shared company hands over ownership and keeps the records', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('leaving-owner');
    final engineer = await _Phone.signUp('staying');
    final email = owner.service.email!;
    final company = await owner.db.companyDao.create('Shared Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    await engineer.service.joinCompany(cloud.joinCode!);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: company.id,
      name: 'Shared site',
      status: const Value('active'),
    ));
    final dpr = await owner.db.dprDao.create(DprEntriesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      createdBy: owner.localUserId,
      entryDate: DateTime.utc(2026, 11, 5),
      workSummary: 'Brickwork, ground floor',
    ));
    await owner.db.messageDao.send(
      projectId: project.id,
      senderId: owner.localUserId,
      senderName: 'Owner Name',
      body: 'Handing over',
    );
    expect((await owner.engine.pushPending()).failed, 0);

    final result = await owner.service.deleteAccount();
    expect(result.companiesDeleted, 0);
    expect(result.companiesLeft, 1);

    final roster = await engineer.service.roster(company.id);
    expect(roster.single.userId, engineer.remoteUserId);
    expect(roster.single.role, 'owner', reason: 'the team is never left without an owner');

    await engineer.engine.pullAll();
    expect((await engineer.db.dprDao.byId(dpr.id))?.workSummary, 'Brickwork, ground floor');
    final messages = await engineer.db.messageDao.forProject(project.id);
    expect(messages.single.senderName, 'Former member');

    await expectLater(
      owner.client.auth.signInWithPassword(email: email, password: 'test-password-123!'),
      throwsA(isA<AuthException>()),
    );
    await owner.close();
    await engineer.close();
  });

  test('free plan caps the team at 3 people; only the server can switch a company to Team', () async {
    if (!stackUp) return;
    final owner = await _Phone.signUp('plan-owner');
    final company = await owner.db.companyDao.create('Capped Builders');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);

    final joiners = [for (var i = 0; i < 3; i++) await _Phone.signUp('joiner$i')];
    await joiners[0].service.joinCompany(cloud.joinCode!);
    await joiners[1].service.joinCompany(cloud.joinCode!);
    var plan = await owner.service.companyPlan(company.id);
    expect(plan.isPaid, isFalse);
    expect(plan.members, 3);
    expect(plan.isFull, isTrue);

    await expectLater(
      joiners[2].service.joinCompany(cloud.joinCode!),
      throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('free plan limit'))),
    );
    // Already a member: re-joining is not blocked by the cap.
    await joiners[0].service.joinCompany(cloud.joinCode!);

    // The owner cannot grant themselves Team: no update policy, and the
    // guard trigger strips the plan from a client-side insert.
    await owner.client.from('companies').update({'plan': 'team'}).eq('id', company.id);
    expect((await owner.service.companyPlan(company.id)).isPaid, isFalse);
    final sneaky = _uuid.v4();
    await owner.client.from('companies').insert({'id': sneaky, 'name': 'Sneaky', 'plan': 'team'});
    final admin = SupabaseClient(SyncConfig.local.url, localServiceRoleKey);
    expect((await admin.from('companies').select('plan').eq('id', sneaky).single())['plan'], 'free');

    // What the RevenueCat webhook does with the service role.
    final until = DateTime.now().toUtc().add(const Duration(days: 30));
    await admin.from('companies').update({'plan': 'team', 'plan_expires_at': until.toIso8601String()}).eq('id', company.id);
    plan = await owner.service.companyPlan(company.id);
    expect(plan.isPaid, isTrue);
    expect(plan.memberLimit, isNull);
    await joiners[2].service.joinCompany(cloud.joinCode!);
    expect((await owner.service.companyPlan(company.id)).members, 4);

    // A lapsed subscription counts as free again.
    await admin.from('companies').update({
      'plan_expires_at': DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
    }).eq('id', company.id);
    expect((await owner.service.companyPlan(company.id)).isPaid, isFalse);

    await admin.dispose();
    for (final p in [owner, ...joiners]) {
      await p.close();
    }
  });
}
