/// Incremental pull with deletes and loss of access (audit P1, 2026-11-10),
/// against the local Supabase stack (skips itself if it is not running).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('changes, remote deletes and a removed member reach the phone without a full pull', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final engineer = await CloudPhone.signUp('engineer');
    final company = await owner.db.companyDao.create('Delta Co');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Wing B', status: const Value('active')));
    final keepTask = await owner.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: project.id, title: 'Brickwork'));
    final goneTask = await owner.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: project.id, title: 'Scrapped'));
    expect((await owner.engine.pushPending()).failed, 0);

    await engineer.service.joinCompany(cloud.joinCode!);
    // What Team & sync does after joining (CloudLinks.link).
    await engineer.db.settingsDao.set('cloud_linked_companies', jsonEncode([company.id]));
    final cursorKey = 'sync_cursor:${engineer.remoteUserId}';
    await engineer.engine.pullAll();
    expect(await engineer.db.taskDao.forProject(project.id), hasLength(2));
    final firstCursor = int.parse((await engineer.db.settingsDao.get(cursorKey))!);

    // Another device edits one task; the other is removed on the server.
    await owner.client.from('tasks').update({'progress': 60}).eq('id', keepTask.id);
    await adminClient().from('tasks').delete().eq('id', goneTask.id);
    await engineer.engine.pullAll();
    final tasks = await engineer.db.taskDao.forProject(project.id);
    expect(tasks.map((t) => t.id), [keepTask.id], reason: 'the deleted task is gone from the phone');
    expect(tasks.single.progress, 60);
    expect(int.parse((await engineer.db.settingsDao.get(cursorKey))!), greaterThan(firstCursor));

    // A pull with nothing new keeps the cursor.
    await engineer.engine.pullAll();
    final cursor = await engineer.db.settingsDao.get(cursorKey);
    await engineer.engine.pullAll();
    expect(await engineer.db.settingsDao.get(cursorKey), cursor);

    // A row the engineer edited but hasn't sent is not dropped by a remote
    // delete; the edit's push then reports it as gone (not marked sent).
    await engineer.db.taskDao.setProgress(keepTask.id, 80);
    await adminClient().from('tasks').delete().eq('id', keepTask.id);
    await engineer.engine.pullAll();
    expect(await engineer.db.taskDao.forProject(project.id), hasLength(1), reason: 'unsent edit kept');
    expect((await engineer.engine.pushPending()).failed, 1);

    // The engineer's own unsent site stays when the company drops them;
    // the company's site goes with everything on it.
    final draftSite = await engineer.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Not sent yet', status: const Value('active')));
    await adminClient().from('company_members').delete().eq('company_id', company.id).eq('user_id', engineer.remoteUserId);
    await engineer.engine.pullAll();
    final sites = await engineer.db.projectDao.forCompany(company.id);
    expect(sites.map((p) => p.id), [draftSite.id]);
    expect(await engineer.db.taskDao.forProject(project.id), isEmpty, reason: "the dropped site's tasks went with it");

    await owner.close();
    await engineer.close();
  });

  test('a cursor older than the kept change log falls back to a full pull', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final reader = await CloudPhone.signUp('reader');
    final company = await owner.db.companyDao.create('Floor Co');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Old site', status: const Value('active')));
    final task = await owner.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: project.id, title: 'Footings'));
    expect((await owner.engine.pushPending()).failed, 0);
    await reader.service.joinCompany(cloud.joinCode!);

    // This phone last synced long ago (cursor 0) and the log has since been
    // pruned past it: following the log alone would miss the task.
    await adminClient().from('sync_changes').delete().gte('seq', 0);
    await reader.db.settingsDao.set('sync_cursor:${reader.remoteUserId}', '0');
    await reader.engine.pullAll();
    expect((await reader.db.taskDao.forProject(project.id)).map((t) => t.id), [task.id]);
    final cursor = int.parse((await reader.db.settingsDao.get('sync_cursor:${reader.remoteUserId}'))!);
    expect(cursor, greaterThan(0));

    await owner.close();
    await reader.close();
  });
}
