/// Multi-level approvals by amount: which levels an item needs, when its
/// chain is complete, who signs, and the weekly close holding an expense
/// until the owner has approved it.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';

late AppDatabase db;
late Company company;
late Project site;

ProjectMember _row(String role, {double? limit, String user = 'pm'}) => ProjectMember(
    id: 'm-$user', projectId: 'site-1', userId: user, role: role, approvalLimit: limit, createdAt: DateTime(2026), updatedAt: DateTime(2026));

ApprovalStep _step(String level, {String decision = 'approved', String by = 'x'}) => ApprovalStep(
    id: '$level-$by', projectId: 'p', kind: ApprovalKind.expense, itemId: 'e', level: level, decision: decision, decidedBy: by,
    createdAt: DateTime(2026, 11, 5));

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    company = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(
        id: 'site-1', companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
  });
  tearDown(() => db.close());

  Future<List<ApprovalRule>> rules() => db.approvalChainDao.rulesFor(company.id);

  test('the owner sets one amount per kind and level; blank removes it, and every change is queued for sync', () async {
    final dao = db.approvalChainDao;
    await dao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.projectManager, above: 10000, by: 'owner');
    await dao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 100000, by: 'owner');
    await dao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.projectManager, above: 25000, by: 'owner');
    var r = await rules();
    expect([for (final x in r) (x.role, x.aboveAmount)], [(ApprovalLevel.projectManager, 25000), (ApprovalLevel.owner, 100000)]);
    await dao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: null, by: 'owner');
    r = await rules();
    expect(r.single.role, ApprovalLevel.projectManager);
    final queued = await db.select(db.syncOutbox).get();
    expect(queued.where((q) => q.targetTable == 'site_approval_rules').length, 4, reason: 'two inserts, two updates');
    expect(() => dao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: -1, by: 'owner'),
        throwsArgumentError);
  });

  test('levels are the amounts crossed, lowest first, and only for items recorded after the rule', () async {
    await db.approvalChainDao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 100000, by: 'o');
    await db.approvalChainDao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.projectManager, above: 10000, by: 'o');
    final r = await rules();
    final later = DateTime.now().add(const Duration(minutes: 1));
    expect(requiredLevels(r, ApprovalKind.expense, 10000, createdAt: later), isEmpty);
    expect(requiredLevels(r, ApprovalKind.expense, 10001, createdAt: later), [ApprovalLevel.projectManager]);
    expect(requiredLevels(r, ApprovalKind.expense, 250000, createdAt: later), [ApprovalLevel.projectManager, ApprovalLevel.owner]);
    expect(requiredLevels(r, ApprovalKind.expense, -250000, createdAt: later), hasLength(2), reason: 'a refund by its size');
    expect(requiredLevels(r, ApprovalKind.purchaseOrder, 250000, createdAt: later), isEmpty, reason: 'another kind');
    expect(requiredLevels(r, ApprovalKind.expense, 250000, createdAt: DateTime(2020)), isEmpty, reason: 'recorded before');
  });

  test('a chain is complete when each level has an approval at or above it; one rejection stops it', () {
    const both = [ApprovalLevel.projectManager, ApprovalLevel.owner];
    expect(chainStatus(const [], const []).complete, isTrue);
    var c = chainStatus(both, const []);
    expect((c.complete, c.next), (false, ApprovalLevel.projectManager));
    c = chainStatus(both, [_step(ApprovalLevel.projectManager)]);
    expect((c.complete, c.next), (false, ApprovalLevel.owner));
    expect(chainStatus(both, [_step(ApprovalLevel.projectManager), _step(ApprovalLevel.owner)]).complete, isTrue);
    expect(chainStatus(both, [_step(ApprovalLevel.owner)]).complete, isTrue, reason: "the owner's covers the PM's");
    c = chainStatus(both, [_step(ApprovalLevel.projectManager, decision: 'rejected'), _step(ApprovalLevel.owner)]);
    expect((c.rejected, c.complete, c.next), (true, false, null));
  });

  test('who signs: the owner as owner; a project manager the PM level within their limit; others not', () {
    const both = [ApprovalLevel.projectManager, ApprovalLevel.owner];
    final fresh = chainStatus(both, const []);
    final pmDone = chainStatus(both, [_step(ApprovalLevel.projectManager)]);
    const owner = SiteAccessFor(companyRole: Roles.owner);
    final sitePm = SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.projectManager, limit: 50000));
    final engineer = SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.siteEngineer));
    expect(signingLevel(fresh, owner, 200000), ApprovalLevel.owner);
    expect(signingLevel(fresh, sitePm, 40000), ApprovalLevel.projectManager);
    expect(signingLevel(fresh, sitePm, 60000), isNull, reason: 'above their limit');
    expect(signingLevel(pmDone, sitePm, 40000), isNull, reason: 'the owner is next');
    expect(signingLevel(fresh, engineer, 100), isNull);
    expect(signingLevel(fresh, const SiteAccessFor(companyRole: Roles.manager), 1e7), ApprovalLevel.projectManager);
  });

  test('the weekly close holds a big expense until the owner signs; approve-all leaves it waiting', () async {
    await db.approvalChainDao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.projectManager, above: 10000, by: 'o');
    await db.approvalChainDao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 100000, by: 'o');
    for (final (id, amount) in [('e-small', 4000.0), ('e-mid', 40000.0), ('e-big', 180000.0)]) {
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: id, projectId: site.id, category: 'Material', amount: amount, incurredOn: '2026-11-03', recordedBy: 'sup'));
      await db.expenseDao.attach(id, '/tmp/$id.jpg');
    }
    Future<WeekClose> week() => loadWeekClose(db, site, DateTime(2026, 11, 2), now: DateTime(2026, 11, 7, 19));
    final pm = CloseActions(db,
        userId: 'pm', role: Roles.member, site: SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.projectManager)));
    var w = await week();
    expect(await pm.approveClean(w), 2, reason: 'the small one, and the mid one signed by the PM completes its chain');
    w = await week();
    final big = w.items.firstWhere((i) => i.id == 'e-big');
    expect(big.state, ItemState.waiting);
    final steps = await db.approvalChainDao.stepsForItem(ApprovalKind.expense, 'e-big');
    expect([for (final s in steps) (s.level, s.decidedBy)], [(ApprovalLevel.projectManager, 'pm')]);
    // Signing again does nothing new, and says it waits for the owner.
    await expectLater(pm.approve(w, big), throwsA(isA<CloseNotAllowed>()));

    final owner = CloseActions(db, userId: 'owner', role: Roles.owner);
    expect(await owner.approve(w, big), isNotNull);
    w = await week();
    expect(w.items.firstWhere((i) => i.id == 'e-big').state, ItemState.approved);
    expect((await db.approvalChainDao.stepsForItem(ApprovalKind.expense, 'e-big')).map((s) => s.level),
        [ApprovalLevel.projectManager, ApprovalLevel.owner]);
    final queued = await db.select(db.syncOutbox).get();
    final order = [for (final q in queued) q.targetTable];
    expect(order.lastIndexOf('site_approval_steps'), lessThan(order.lastIndexOf('site_close_reviews')),
        reason: 'the signature reaches the server before the approval that needs it');
  });

  test('a rejected expense cannot be approved in the weekly close', () async {
    await db.approvalChainDao.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 1000, by: 'o');
    await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e1', projectId: site.id, category: 'Material', amount: 5000, incurredOn: '2026-11-03', recordedBy: 'sup'));
    await db.approvalChainDao.sign(
        projectId: site.id, kind: ApprovalKind.expense, itemId: 'e1', level: ApprovalLevel.owner, approve: false, by: 'owner', note: 'not ours');
    final w = await loadWeekClose(db, site, DateTime(2026, 11, 2), now: DateTime(2026, 11, 7, 19));
    await expectLater(CloseActions(db, userId: 'owner', role: Roles.owner).approve(w, w.items.firstWhere((i) => i.id == 'e1')),
        throwsA(isA<CloseNotAllowed>()));
  });
}
