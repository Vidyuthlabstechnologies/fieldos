/// Submittals on two phones against the local Supabase stack (skips itself
/// when the stack is not running): the engineer sends one for review with
/// the task it holds up, the PM sends it back, the engineer resubmits, the
/// PM approves and the task stops waiting on both phones; and the server
/// refuses a review by a non-manager, a skipped step and a rewritten
/// history.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  Matcher refused(String words) => throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains(words)));

  test('a submittal goes round twice between phones and the server keeps its steps', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final pm = await CloudPhone.signUp('sub-pm');
    final engineer = await CloudPhone.signUp('sub-engineer');
    addTearDown(() async {
      await pm.close();
      await engineer.close();
    });

    final company = await pm.db.companyDao.create('Sai Constructions');
    final cloud = await pm.service.registerCompany(companyId: company.id, name: company.name);
    final site = await pm.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final tiling = await pm.db.taskDao.create(TasksCompanion.insert(id: uuid.v4(), projectId: site.id, title: 'Floor tiling'));
    await pushAll(pm);

    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();
    final e = engineer.db.siteExecutionDao;
    final sub = await e.raiseSubmittal(
        projectId: site.id, title: 'Floor tiles 600 x 600', kind: 'sample', reviewer: 'Architect', taskId: tiling.id,
        by: engineer.localUserId);
    await pushAll(engineer);

    // Not a manager: the engineer cannot record the review, even as themselves.
    final now = DateTime.now().toUtc().toIso8601String();
    await expectLater(
        engineer.client
            .from('site_submittals')
            .update({'status': 'approved', 'decided_by': engineer.remoteUserId, 'decided_at': now})
            .eq('id', sub.id)
            .select(),
        refused('Only the owner or a project manager'));
    // Nor go round again before a review.
    await expectLater(
        engineer.client.from('site_submittals').update({'round': 2, 'history': 'x'}).eq('id', sub.id).select(),
        refused('not a step'));
    // Nor raise one as someone else, or already approved.
    await expectLater(
        engineer.client.from('site_submittals').insert(
            {'id': uuid.v4(), 'project_id': site.id, 'title': 'x', 'raised_by': pm.remoteUserId}),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        engineer.client.from('site_submittals').insert(
            {'id': uuid.v4(), 'project_id': site.id, 'title': 'x', 'raised_by': engineer.remoteUserId, 'status': 'approved'}),
        throwsA(isA<PostgrestException>()));

    await pm.engine.pullAll();
    var d = await loadExecutionData(pm.db, site.id);
    expect(d.openConstraintsOf(tiling.id).single.linkId, sub.id, reason: 'the task waits on the PM phone too');
    await pm.db.siteExecutionDao
        .decideSubmittal(sub.id, status: 'revise_resubmit', note: 'Show the skirting detail', by: pm.localUserId);
    await pushAll(pm);
    // A review is recorded once.
    await expectLater(
        pm.client.from('site_submittals').update({'decision_note': 'Changed my mind'}).eq('id', sub.id).select(),
        refused('recorded once'));

    await engineer.engine.pullAll();
    final back = (await e.submittalById(sub.id))!;
    expect(back.status, 'revise_resubmit');
    expect(back.decisionNote, 'Show the skirting detail');
    await e.resubmitSubmittal(sub.id, by: engineer.localUserId);
    await pushAll(engineer);
    // The history only grows.
    await expectLater(
        engineer.client.from('site_submittals').update({'history': 'rewritten'}).eq('id', sub.id).select(),
        refused('never rewritten'));

    await pm.engine.pullAll();
    final again = (await pm.db.siteExecutionDao.submittalById(sub.id))!;
    expect(again.round, 2);
    expect(again.status, 'submitted');
    expect(again.history, contains('Show the skirting detail'));
    await pm.db.siteExecutionDao.decideSubmittal(sub.id, status: 'approved', by: pm.localUserId);
    await pushAll(pm);

    await engineer.engine.pullAll();
    d = await loadExecutionData(engineer.db, site.id);
    expect(d.submittals.single.status, 'approved');
    expect(d.openConstraintsOf(tiling.id), isEmpty, reason: 'approval clears the wait on the engineer phone');
  });
}
