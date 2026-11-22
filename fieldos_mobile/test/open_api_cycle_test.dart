/// The open API against the local Supabase stack (skips itself when the
/// stack is not running): the owner makes a key, the key reads only its own
/// company's sites, pages and the change feed work, a non-owner cannot make
/// or see keys, the hash never leaves the server, and a revoked key stops.
/// A write key adds and changes tasks and issues of its own company only,
/// phones pull them, and webhooks queue, retry and give up.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/settings/api_keys_screen.dart';
import 'package:fieldos_mobile/features/settings/webhooks_screen.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    expect(r.failed, 0);
  }

  test('a company key reads its own sites only, pages, follows changes, and stops when revoked', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('api-owner');
    final engineer = await CloudPhone.signUp('api-engineer');
    final other = await CloudPhone.signUp('api-other');
    final admin = adminClient();
    addTearDown(() async {
      await owner.close();
      await engineer.close();
      await other.close();
      await admin.dispose();
    });

    Future<Map<String, dynamic>> read(String key, String resource, {String? project, String? id, String? after, int limit = 100}) async =>
        Map<String, dynamic>.from(await admin.rpc('api_read', params: {
          'p_key': key, 'p_resource': resource, 'p_project': project, 'p_id': id, 'p_after': after, 'p_limit': limit,
        }) as Map);

    // Two companies, each with a site and tasks.
    final company = await owner.db.companyDao.create('Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final site = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    for (final t in ['Footing', 'Columns', 'Slab']) {
      await owner.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: site.id, title: t));
    }
    await pushAll(owner);
    final theirs = await other.db.companyDao.create('Rival Builders');
    await other.service.registerCompany(companyId: theirs.id, name: theirs.name);
    final theirSite = await other.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: theirs.id, name: 'Rival Towers', status: const Value('active')));
    final theirTask = await other.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: theirSite.id, title: 'Their secret task'));
    await pushAll(other);

    // A member who is not the owner cannot make a key or see one.
    await engineer.service.joinCompany(cloud.joinCode!);
    await expectLater(ApiKeysService(engineer.client).create(company.id, 'Mine'),
        throwsA(isA<PostgrestException>().having((e) => e.message, 'message', contains('Only the company owner'))));

    final keys = ApiKeysService(owner.client);
    final key = await keys.create(company.id, 'Accounts software');
    expect(key, matches(RegExp(r'^fos_[0-9a-f]{48}$')));
    final listed = (await keys.list(company.id)).single;
    expect(listed.prefix, key.substring(0, 12));
    expect(await ApiKeysService(engineer.client).list(company.id), isEmpty);
    await expectLater(owner.client.from('company_api_keys').select('key_hash'), throwsA(isA<PostgrestException>()));
    // Nobody signed in calls api_read directly; only the edge function does.
    await expectLater(owner.client.rpc('api_read', params: {'p_key': key, 'p_resource': 'tasks'}),
        throwsA(isA<PostgrestException>()));

    // Its own company only.
    final projects = await read(key, 'projects');
    expect([for (final p in projects['data'] as List) p['name']], ['Kompally Villas']);
    final tasks = await read(key, 'tasks');
    expect([for (final t in tasks['data'] as List) t['title']], unorderedEquals(['Footing', 'Columns', 'Slab']));
    expect(await read(key, 'tasks', project: theirSite.id), {'error': 'not_found'});
    expect(await read(key, 'tasks', id: theirTask.id), {'error': 'not_found'});
    expect(await read(key, 'company_api_keys'), {'error': 'unknown_resource'});
    expect(await read(key, 'changes', after: 'x'), {'error': 'bad_cursor'});
    final theirFeed = [for (final c in (await read(key, 'changes', limit: 500))['data'] as List) c['id']];
    expect(theirFeed, isNot(contains(theirSite.id)), reason: 'no other company in the change feed');

    // Pages by id.
    final page1 = await read(key, 'tasks', limit: 2);
    expect((page1['data'] as List).length, 2);
    final page2 = await read(key, 'tasks', limit: 2, after: page1['next'] as String);
    expect((page2['data'] as List).length, 1);
    expect(page2['next'], isNull);
    final one = await read(key, 'tasks', id: (page2['data'] as List).single['id'] as String);
    expect((one['data'] as List).single['project_id'], site.id);

    // The change feed: everything so far, then only what changed after.
    final feed = await read(key, 'changes', limit: 500);
    final seen = [for (final c in feed['data'] as List) c['resource']];
    expect(seen, containsAll(['projects', 'tasks']));
    expect(seen, isNot(contains(null)));
    final last = (feed['data'] as List).last['seq'].toString();
    await owner.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: site.id, title: 'Brickwork'));
    await pushAll(owner);
    final more = await read(key, 'changes', after: last);
    expect([for (final c in more['data'] as List) (c['resource'], c['op'])], [('tasks', 'changed')]);

    // 120 calls a minute, even when they arrive at once.
    final burst = await Future.wait([
      for (var i = 0; i < 130; i++) read(key, 'projects', limit: 1).then((_) => true, onError: (Object e) {
        expect(e, isA<PostgrestException>().having((x) => x.message, 'm', 'rate_limited'));
        return false;
      }),
    ]);
    expect(burst.where((ok) => ok).length, lessThanOrEqualTo(120));
    expect(burst.where((ok) => !ok), isNotEmpty);
    await admin.from('company_api_keys').update({'window_start': '2000-01-01T00:00:00Z'}).eq('id', listed.id);

    // A wrong or revoked key gets nothing.
    await expectLater(read('fos_${'0' * 48}', 'tasks'), throwsA(isA<PostgrestException>().having((e) => e.message, 'm', 'invalid_key')));
    await keys.revoke(listed.id);
    await expectLater(read(key, 'tasks'), throwsA(isA<PostgrestException>().having((e) => e.message, 'm', 'invalid_key')));
    expect((await keys.list(company.id)).single.revokedAt, isNotNull);
  });

  test('a write key adds and changes tasks and issues, phones get them, and webhooks queue them', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('api-writer');
    final other = await CloudPhone.signUp('api-writer-rival');
    final admin = adminClient();
    addTearDown(() async {
      await owner.close();
      await other.close();
      await admin.dispose();
    });

    Future<Map<String, dynamic>> write(String key, String resource, Map<String, dynamic> body, {String? id, String? idem}) async =>
        Map<String, dynamic>.from(await admin.rpc('api_write', params: {
          'p_key': key, 'p_resource': resource, 'p_id': id, 'p_body': body, 'p_idempotency_key': idem,
        }) as Map);

    final company = await owner.db.companyDao.create('Sai Constructions');
    await owner.service.registerCompany(companyId: company.id, name: company.name);
    final site = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    await pushAll(owner);
    final theirs = await other.db.companyDao.create('Rival Builders');
    await other.service.registerCompany(companyId: theirs.id, name: theirs.name);
    final theirSite = await other.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: theirs.id, name: 'Rival Towers', status: const Value('active')));
    final theirTask = await other.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: theirSite.id, title: 'Theirs'));
    await pushAll(other);

    final keys = ApiKeysService(owner.client);
    final readKey = await keys.create(company.id, 'BI');
    final writeKey = await keys.create(company.id, 'Zapier', write: true);
    expect([for (final k in await keys.list(company.id)) (k.name, k.canWrite)], unorderedEquals([('BI', false), ('Zapier', true)]));

    // A webhook made in the app, for tasks only. Its secret is never readable.
    final hooks = WebhooksService(owner.client);
    final secret = await hooks.create(company.id, url: 'https://hooks.zapier.com/hooks/catch/1/x', events: ['tasks'], description: 'Zapier');
    expect(secret, matches(RegExp(r'^whsec_[0-9a-f]{48}$')));
    await expectLater(owner.client.from('company_webhooks').select('secret'), throwsA(isA<PostgrestException>()));
    await expectLater(hooks.create(company.id, url: 'https://169.254.169.254/latest', events: ['*']), throwsA(isA<PostgrestException>()));
    final hook = (await hooks.list(company.id)).single;

    // Read keys cannot write; write keys cannot reach another company or other resources.
    expect((await write(readKey, 'tasks', {'project_id': site.id, 'title': 'x'}))['error'], 'forbidden');
    expect((await write(writeKey, 'tasks', {'project_id': theirSite.id, 'title': 'x'}))['error'], 'not_found');
    expect((await write(writeKey, 'tasks', {'status': 'done'}, id: theirTask.id))['error'], 'not_found');
    expect((await write(writeKey, 'approvals', {'project_id': site.id}))['error'], 'not_writable');
    expect((await write(writeKey, 'tasks', {'project_id': site.id, 'title': 'x', 'id': uuid.v4()}))['error'], 'bad_request');

    final made = await write(writeKey, 'tasks', {'project_id': site.id, 'title': 'Pour slab', 'due_date': '2026-12-05'}, idem: 'zap-1');
    final taskId = (made['data'] as Map)['id'] as String;
    final again = await write(writeKey, 'tasks', {'project_id': site.id, 'title': 'Pour slab', 'due_date': '2026-12-05'}, idem: 'zap-1');
    expect((again['data'] as Map)['id'], taskId, reason: 'a retried POST makes no second task');
    await write(writeKey, 'tasks', {'status': 'in_progress', 'progress': 40}, id: taskId);
    final issue = await write(writeKey, 'issues', {'project_id': site.id, 'description': 'Crack in column C4', 'severity': 'high'});
    expect((issue['data'] as Map)['status'], 'open');
    final theirRow = await admin.from('tasks').select('status').eq('id', theirTask.id).single();
    expect(theirRow['status'], 'todo', reason: 'the other company is untouched');

    // The owner's phone gets the API's task and issue on its next pull.
    await owner.engine.pullAll();
    final local = (await owner.db.taskDao.forProject(site.id)).singleWhere((t) => t.id == taskId);
    expect(local.title, 'Pour slab');
    expect(local.status, 'in_progress');
    expect(local.progress, 40);

    // Webhooks: the create and the change fold into one tasks delivery; the issue is not followed.
    await admin.rpc('webhook_enqueue', params: {'p_settle_seconds': 0});
    final queued = await admin.from('company_webhook_deliveries').select('event_type, payload, status').eq('webhook_id', hook.id);
    expect([for (final d in queued) d['event_type']], ['tasks.changed']);
    final payload = queued.single['payload'] as Map;
    expect((payload['data'] as Map)['id'], taskId);
    expect(((payload['data'] as Map)['object'] as Map)['progress'], 40);
    // A rival company's changes never reach this webhook.
    expect(queued.where((d) => '${d['payload']}'.contains(theirTask.id)), isEmpty);

    // Retries, then giving up after 8 tries.
    final id = (await admin.from('company_webhook_deliveries').select('id').eq('webhook_id', hook.id).single())['id'] as String;
    for (var i = 0; i < 8; i++) {
      await admin.from('company_webhook_deliveries').update({'next_attempt_at': '2000-01-01T00:00:00Z'}).eq('id', id);
      final claimed = await admin.rpc('webhook_claim', params: {'p_limit': 200}) as List;
      final mine = claimed.where((c) => c['id'] == id).toList();
      expect(mine, hasLength(1));
      expect(mine.single['secret'], secret);
      await admin.rpc('webhook_report', params: {'p_delivery_id': id, 'p_status': 500, 'p_error': 'HTTP 500'});
    }
    final gaveUp = await hooks.deliveries(hook.id);
    expect(gaveUp.single.status, 'failed');
    expect(gaveUp.single.attempts, 8);

    // The owner sees what each key changed; an engineer would see nothing (owner only).
    final changes = await keys.recentChanges(company.id);
    expect([for (final c in changes) (c.keyName, c.action, c.resource)],
        unorderedEquals([('Zapier', 'create', 'tasks'), ('Zapier', 'update', 'tasks'), ('Zapier', 'create', 'issues')]));

    // A test ping, switching off, a new secret, delete.
    await owner.client.rpc('send_company_webhook_test', params: {'p_webhook_id': hook.id});
    expect((await hooks.deliveries(hook.id)).first.eventType, 'ping');
    await hooks.setEnabled(hook.id, false);
    expect((await hooks.list(company.id)).single.enabled, isFalse);
    expect((await hooks.deliveries(hook.id)).where((d) => d.status == 'pending'), isEmpty);
    final rotated = await hooks.rotateSecret(hook.id);
    expect(rotated, isNot(secret));
    await expectLater(WebhooksService(other.client).delete(hook.id), throwsA(isA<PostgrestException>()));
    await hooks.delete(hook.id);
    expect(await hooks.list(company.id), isEmpty);
  });
}
