/// Site teams on the server, with three phones against the local Supabase
/// stack (skips itself when the stack is not running): a members-only site
/// is hidden from the rest of the company; a site project manager approves
/// up to their limit and no further, even by lying about the amount; and
/// the roster rules hold (no handing out "owner", no raising your own
/// limit, no members-only switch for a site manager).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';

import 'support/cloud_phone.dart';

Matcher get _refused => throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501'));

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('members-only sites, site approval limits and roster rules hold on the server', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final sitePm = await CloudPhone.signUp('sitepm');
    final engineer = await CloudPhone.signUp('engineer');
    final company = await owner.db.companyDao.create('Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final villas = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final office = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Head office fit-out', status: const Value('active')));
    expect((await owner.engine.pushPending()).failed, 0);
    await sitePm.service.joinCompany(cloud.joinCode!);
    await engineer.service.joinCompany(cloud.joinCode!);

    // The owner hides the office site and makes the site PM manager of the
    // villas with a ₹50,000 limit.
    await owner.db.siteTeamDao.setMembersOnly(office.id, true);
    await owner.db.siteTeamDao
        .setMember(projectId: villas.id, userId: sitePm.remoteUserId, role: SiteRole.projectManager, approvalLimit: 50000);
    var push = await owner.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await owner.db.select(owner.db.syncOutbox).get()) e.lastError]}');

    // The engineer's phone gets the villas only, by sync and by asking the
    // server directly.
    await engineer.engine.pullAll();
    expect((await engineer.db.projectDao.forCompany(company.id)).map((p) => p.id), [villas.id]);
    final seen = await engineer.client.from('projects').select('id').eq('company_id', company.id);
    expect(seen.map((r) => r['id']), [villas.id]);
    expect(await engineer.client.from('site_expenses').select().eq('project_id', office.id), isEmpty);

    // The site PM sees their role and limit after a pull.
    await sitePm.engine.pullAll();
    final access = await siteAccessFor(sitePm.db, villas.id, userId: sitePm.localUserId, companyRole: Roles.member);
    expect(access.managesSite, isTrue);
    expect(access.approvalLimit, 50000);

    // The engineer books two expenses on the villas.
    Future<SiteExpense> expense(String id, double amount) => engineer.db.expenseDao.create(SiteExpensesCompanion.insert(
        id: id, projectId: villas.id, category: 'Transport', amount: amount,
        incurredOn: DateTime.now().toIso8601String().substring(0, 10), recordedBy: engineer.localUserId));
    final small = await expense(uuid.v4(), 12000);
    final big = await expense(uuid.v4(), 90000);
    expect((await engineer.engine.pushPending()).failed, 0);
    await sitePm.engine.pullAll();

    // The site PM approves the small one; the big one is refused on the
    // phone, and on the server even when the phone claims a smaller amount.
    final week = await loadWeekClose(sitePm.db, villas, DateTime.now());
    final pmActions = CloseActions(sitePm.db, userId: sitePm.localUserId, role: Roles.member, site: access);
    await pmActions.approve(week, week.items.firstWhere((i) => i.id == small.id));
    expect(() => pmActions.approve(week, week.items.firstWhere((i) => i.id == big.id)), throwsA(isA<CloseNotAllowed>()));
    push = await sitePm.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await sitePm.db.select(sitePm.db.syncOutbox).get()) e.lastError]}');
    Map<String, dynamic> review(String itemId, double amount) => {
          'id': uuid.v4(),
          'project_id': villas.id,
          'week_start': week.weekKey,
          'item_kind': 'expense',
          'item_id': itemId,
          'decision': 'approved',
          'decided_by': sitePm.remoteUserId,
          'amount': amount,
        };
    await expectLater(sitePm.client.from('site_close_reviews').insert(review(big.id, 90000)), _refused);
    await expectLater(sitePm.client.from('site_close_reviews').insert(review(big.id, 100)), _refused,
        reason: 'the server checks the amount on record, not the one sent');
    // The engineer approves nothing; the owner approves the big one.
    await expectLater(
        engineer.client.from('site_close_reviews').insert(review(small.id, 12000)..['decided_by'] = engineer.remoteUserId),
        _refused);
    await owner.engine.pullAll();
    final ownerWeek = await loadWeekClose(owner.db, villas, DateTime.now());
    await CloseActions(owner.db, userId: owner.localUserId, role: Roles.owner)
        .approve(ownerWeek, ownerWeek.items.firstWhere((i) => i.id == big.id));
    expect((await owner.engine.pushPending()).failed, 0);
    final approved = await owner.client
        .from('site_close_reviews')
        .select('item_id, decision')
        .eq('project_id', villas.id)
        .eq('decision', 'approved');
    expect(approved.map((r) => r['item_id']).toSet(), {small.id, big.id});

    // Roster rules for the site PM: may add the engineer, may not hand out
    // "owner", raise their own limit, or hide the site.
    await sitePm.db.siteTeamDao.setMember(projectId: villas.id, userId: engineer.remoteUserId, role: SiteRole.storekeeper);
    expect((await sitePm.engine.pushPending()).failed, 0);
    await expectLater(
        sitePm.client.from('project_members').insert(
            {'id': uuid.v4(), 'project_id': villas.id, 'user_id': engineer.remoteUserId, 'role': 'owner'}),
        throwsA(isA<PostgrestException>()));
    final raised = await sitePm.client
        .from('project_members')
        .update({'approval_limit': 10000000})
        .eq('project_id', villas.id)
        .eq('user_id', sitePm.remoteUserId)
        .select();
    expect(raised, isEmpty, reason: 'their own row is not theirs to change');
    await expectLater(
        sitePm.client.from('site_access').insert({'id': villas.id, 'project_id': villas.id, 'members_only': true}),
        _refused);
    await expectLater(
        sitePm.client
            .from('project_members')
            .update({'role': 'owner'})
            .eq('project_id', villas.id)
            .eq('user_id', engineer.remoteUserId)
            .select(),
        throwsA(isA<PostgrestException>()));

    // The engineer's phone learns the new site role.
    await engineer.engine.pullAll();
    final mine = await siteAccessFor(engineer.db, villas.id, userId: engineer.localUserId, companyRole: Roles.member);
    expect(mine.siteRole, SiteRole.storekeeper);
    expect(mine.managesSite, isFalse);

    // The owner puts the engineer on the office team: now they see it.
    await owner.db.siteTeamDao.setMember(projectId: office.id, userId: engineer.remoteUserId, role: SiteRole.siteEngineer);
    expect((await owner.engine.pushPending()).failed, 0);
    final nowSeen = await engineer.client.from('projects').select('id').eq('company_id', company.id);
    expect(nowSeen.map((r) => r['id']).toSet(), {villas.id, office.id});

    await owner.close();
    await sitePm.close();
    await engineer.close();
  });
}
