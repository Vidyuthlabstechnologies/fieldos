/// Multi-site controls: site roles and approval limits, who may change a
/// site's team, members-only sites, a new site from a template, suppliers
/// pasted with opening balances, and the all-sites portfolio.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/portfolio/portfolio.dart';
import 'package:fieldos_mobile/features/procurement/supplier_import.dart';
import 'package:fieldos_mobile/features/project/site_template.dart';

late AppDatabase db;
late Company company;
late Project site;

ProjectMember _row(String role, {double? limit, String user = 'u1'}) => ProjectMember(
    id: 'm', projectId: 'p', userId: user, role: role, approvalLimit: limit, createdAt: DateTime(2026), updatedAt: DateTime(2026));

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    company = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(
        id: 'site-1', companyId: company.id, name: 'Kompally Villas', status: const Value('active'), geofenceRadiusM: const Value(150)));
  });
  tearDown(() => db.close());

  group('site roles and limits', () {
    test('the company owner approves anything; a company manager without a site row has no limit', () {
      expect(const SiteAccessFor(companyRole: Roles.owner).canApprove(1e9), isTrue);
      expect(const SiteAccessFor(companyRole: Roles.manager).canApprove(1e9), isTrue);
      expect(const SiteAccessFor(companyRole: Roles.member).canApprove(1), isFalse);
      expect(const SiteAccessFor(companyRole: Roles.member).managesSite, isFalse);
    });

    test('a site project manager approves up to their limit, and the site row decides for a company manager too', () {
      final pm = SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.projectManager, limit: 50000));
      expect(pm.managesSite, isTrue);
      expect(pm.canApprove(50000), isTrue);
      expect(pm.canApprove(-50000), isTrue, reason: 'a refund is checked by its size');
      expect(pm.canApprove(50001), isFalse);
      expect(pm.approvalLimit, 50000);

      final mgrWithLimit = SiteAccessFor(companyRole: Roles.manager, member: _row(SiteRole.projectManager, limit: 10000));
      expect(mgrWithLimit.canApprove(20000), isFalse);
      // Matches the server: the company owner is never limited.
      expect(SiteAccessFor(companyRole: Roles.owner, member: _row(SiteRole.projectManager, limit: 1)).canApprove(5), isTrue);
    });

    test('site viewers and company viewers change nothing; an engineer row writes but does not approve', () {
      final siteViewer = SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.viewer));
      expect(siteViewer.canWrite, isFalse);
      expect(siteViewer.siteRole, SiteRole.viewer);
      final companyViewer = SiteAccessFor(companyRole: Roles.viewer, member: _row(SiteRole.projectManager));
      expect(companyViewer.managesSite, isFalse);
      expect(companyViewer.canApprove(1), isFalse);
      final engineer = SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.siteEngineer));
      expect(engineer.canWrite, isTrue);
      expect(engineer.canApprove(1), isFalse);
    });

    test('team rules: a site manager adds others but not an owner, and leaves their own row and owners alone', () {
      final site = TeamRules(SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.projectManager)));
      expect(site.canManageTeam, isTrue);
      expect(site.canSetMembersOnly, isFalse);
      expect(site.rolesTheyCanGive, isNot(contains(SiteRole.owner)));
      expect(site.canChange(isSelf: true, role: SiteRole.projectManager), isFalse);
      expect(site.canChange(isSelf: false, role: SiteRole.owner), isFalse);
      expect(site.canRemove(isSelf: false, role: SiteRole.siteEngineer), isTrue);

      final company = TeamRules(const SiteAccessFor(companyRole: Roles.manager));
      expect(company.canSetMembersOnly, isTrue);
      expect(company.rolesTheyCanGive, contains(SiteRole.owner));
      expect(company.canChange(isSelf: true, role: SiteRole.owner), isTrue);

      expect(TeamRules(const SiteAccessFor(companyRole: Roles.member)).canManageTeam, isFalse);
    });

    test('the weekly close refuses an approval above the limit and approve-all skips it', () async {
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: 'e-small', projectId: site.id, category: 'Transport', amount: 4000, incurredOn: '2026-11-03', recordedBy: 'sup'));
      await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: 'e-big', projectId: site.id, category: 'Transport', amount: 90000, incurredOn: '2026-11-04', recordedBy: 'sup'));
      // Bills attached, so neither is flagged.
      for (final id in ['e-small', 'e-big']) {
        await db.expenseDao.attach(id, '/tmp/$id.jpg');
      }
      final w = await loadWeekClose(db, site, DateTime(2026, 11, 2), now: DateTime(2026, 11, 7, 19));
      final big = w.items.firstWhere((i) => i.id == 'e-big');
      final pm = CloseActions(db,
          userId: 'pm',
          role: Roles.member,
          site: SiteAccessFor(companyRole: Roles.member, member: _row(SiteRole.projectManager, limit: 50000, user: 'pm')));
      expect(pm.canDecide, isTrue);
      expect(pm.canApprove(big), isFalse);
      expect(() => pm.approve(w, big), throwsA(isA<CloseNotAllowed>()));
      expect(await pm.approveClean(w), 1);
      final after = await loadWeekClose(db, site, DateTime(2026, 11, 2), now: DateTime(2026, 11, 7, 19));
      expect(after.items.firstWhere((i) => i.id == 'e-small').state, ItemState.approved);
      expect(after.items.firstWhere((i) => i.id == 'e-big').state, ItemState.waiting);
      // The owner approves it.
      await CloseActions(db, userId: 'owner', role: Roles.owner).approve(after, after.items.firstWhere((i) => i.id == 'e-big'));
    });
  });

  group('site team on the phone', () {
    test('adding, changing and removing a person is one row per person, and every change is queued', () async {
      await db.siteTeamDao.setMember(projectId: site.id, userId: 'cloud-a', role: SiteRole.siteEngineer);
      final m = await db.siteTeamDao.setMember(
          projectId: site.id, userId: 'cloud-a', role: SiteRole.projectManager, approvalLimit: 25000);
      final rows = await db.siteTeamDao.membersFor(site.id);
      expect(rows, hasLength(1));
      expect(rows.single.role, SiteRole.projectManager);
      expect(rows.single.approvalLimit, 25000);
      expect(() => db.siteTeamDao.setMember(projectId: site.id, userId: 'x', role: 'boss'), throwsArgumentError);

      await db.siteTeamDao.removeMember(m.id);
      expect(await db.siteTeamDao.membersFor(site.id), isEmpty);
      final queued = (await db.syncOutboxDao.pending()).where((o) => o.targetTable == 'project_members').toList();
      expect(queued.map((o) => o.operation), ['insert', 'update', 'delete']);
      final payload = jsonDecode(queued[1].payload) as Map<String, dynamic>;
      expect(payload, containsPair('approval_limit', 25000));
      expect(payload, containsPair('role', 'project_manager'));
    });

    test('a pulled row for the same person replaces the one this phone made', () async {
      await db.siteTeamDao.setMember(projectId: site.id, userId: 'cloud-a', role: SiteRole.siteEngineer);
      await db.siteTeamDao.upsertMemberFromRemote(ProjectMembersCompanion.insert(
          id: 'server-row', projectId: site.id, userId: 'cloud-a', role: SiteRole.storekeeper));
      final rows = await db.siteTeamDao.membersFor(site.id);
      expect(rows.single.id, 'server-row');
      expect(rows.single.role, SiteRole.storekeeper);
    });

    test('members-only sites are hidden from people not on the team, never from the company managers', () async {
      final other = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-2', companyId: company.id, name: 'Head office'));
      await db.siteTeamDao.setMembersOnly(other.id, true);
      expect(await db.siteTeamDao.isMembersOnly(other.id), isTrue);
      expect((await db.syncOutboxDao.pending()).where((o) => o.targetTable == 'site_access'), hasLength(1));

      Future<Set<String>> sees(String role, {String? user, String? cloud}) =>
          visibleSiteIds(db, company.id, userId: user, companyRole: role, cloudUserId: cloud);
      expect(await sees(Roles.member, user: 'eng'), {site.id});
      expect(await sees(Roles.manager, user: 'mgr'), {site.id, other.id});
      expect(await sees(Roles.owner), {site.id, other.id});

      // On the team by their cloud account (added on another phone).
      await db.siteTeamDao.setMember(projectId: other.id, userId: 'cloud-eng', role: SiteRole.accounts);
      expect(await sees(Roles.member, user: 'eng', cloud: 'cloud-eng'), {site.id, other.id});
      final a = await siteAccessFor(db, other.id, userId: 'eng', companyRole: Roles.member, cloudUserId: 'cloud-eng');
      expect(a.siteRole, SiteRole.accounts);
    });
  });

  group('new site from a template', () {
    test('copies tasks, active workers, estimate rates, team and geofence size, and nothing that happened', () async {
      await db.taskDao.create(TasksCompanion.insert(
          id: 't1', projectId: site.id, title: 'Footings', progress: const Value(80), priority: const Value('high')));
      await db.workerDao.create(WorkersCompanion.insert(id: 'w1', projectId: site.id, name: 'Ramesh', dailyWage: const Value(900)));
      await db.workerDao.create(WorkersCompanion.insert(
          id: 'w2', projectId: site.id, name: 'Left', status: const Value('inactive')));
      final est = await db.estimationDao.create(
          EstimationsCompanion.insert(id: 'est1', projectId: site.id, name: 'Main estimate', createdBy: 'pm'));
      await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
          id: 'ch1', estimationId: est.id, name: 'Brick work', calculationType: 'volume', rawUnit: 'cft', billingUnit: 'cum',
          ratePerUnit: const Value(5200)));
      await db.dprDao.create(DprEntriesCompanion.insert(
          id: 'd1', projectId: site.id, createdBy: 'sup', entryDate: DateTime(2026, 11, 3), workSummary: 'Done'));
      await db.siteTeamDao.setMember(projectId: site.id, userId: 'cloud-pm', role: SiteRole.projectManager, approvalLimit: 40000);
      await db.siteTeamDao.setMembersOnly(site.id, true);

      final r = await newSiteFromTemplate(db, source: site, name: '  Kompally   Phase 2 ', createdBy: 'owner');
      final p = r.project;
      expect(p.name, 'Kompally Phase 2');
      expect(p.status, 'planning');
      expect(p.geofenceRadiusM, 150);
      expect(p.locationLat, isNull);
      expect((r.tasks, r.workers, r.costHeads, r.team), (1, 1, 1, 1));

      final task = (await db.taskDao.forProject(p.id)).single;
      expect(task.title, 'Footings');
      expect(task.progress, 0);
      expect(task.priority, 'high');
      expect((await db.workerDao.forProject(p.id)).single.dailyWage, 900);
      final newEst = (await db.estimationDao.forProject(p.id)).single;
      expect((await db.estimationDao.costHeadsFor(newEst.id)).single.ratePerUnit, 5200);
      expect((await db.siteTeamDao.membersFor(p.id)).single.approvalLimit, 40000);
      expect(await db.siteTeamDao.isMembersOnly(p.id), isTrue);
      expect(await db.dprDao.forProject(p.id), isEmpty);

      final queued = (await db.syncOutboxDao.pending()).map((o) => o.targetTable).toSet();
      expect(queued, containsAll(['projects', 'tasks', 'workers', 'estimations', 'cost_heads', 'project_members', 'site_access']));
    });

    test('parts can be left out', () async {
      await db.taskDao.create(TasksCompanion.insert(id: 't1', projectId: site.id, title: 'Footings'));
      final r = await newSiteFromTemplate(db,
          source: site, name: 'Bare', createdBy: 'owner', copy: const SiteTemplateParts(tasks: false, geofence: false));
      expect(r.tasks, 0);
      expect(r.project.geofenceRadiusM, isNull);
      expect(() => newSiteFromTemplate(db, source: site, name: '  ', createdBy: 'owner'), throwsArgumentError);
    });
  });

  group('suppliers pasted with opening balances', () {
    test('reads names, phones, GSTINs, Indian-grouped amounts and advances in any order', () {
      final rows = parseSupplierLines('''
1. Sri Balaji Cement, 9848012345, 36ABCDE1234F1Z5, 1,25,000
Raju Sand, 15000 advance
- Lakshmi Steel\t₹ 2,40,500 Cr\tSteel\tlakshmi@example.com
Ganesh Hardware; 98480 12345; Rs. 3,500/-
Tally Party, 12,000 Dr

''');
      expect(rows.map((r) => r.name), ['Sri Balaji Cement', 'Raju Sand', 'Lakshmi Steel', 'Ganesh Hardware', 'Tally Party']);
      expect(rows[0].phone, '9848012345');
      expect(rows[0].gstin, '36ABCDE1234F1Z5');
      expect(rows[0].openingBalance, 125000);
      expect(rows[1].openingBalance, -15000);
      expect(rows[2].openingBalance, 240500);
      expect(rows[2].category, 'Steel');
      expect(rows[2].email, 'lakshmi@example.com');
      expect(rows[3].phone, '98480 12345');
      expect(rows[3].openingBalance, 3500);
      expect(rows[4].openingBalance, -12000);
    });

    test('imports once: a name already on the list, or twice in the paste, is skipped', () async {
      await db.supplierDao.create(SuppliersCompanion.insert(id: 's0', companyId: company.id, name: 'Raju Sand'));
      final r = await importSuppliers(
          db, company.id, parseSupplierLines('raju  sand, 5000\nNew Bricks, 8000\nNEW BRICKS, 9000'));
      expect(r.added.map((s) => s.name), ['New Bricks']);
      expect(r.added.single.openingBalance, 8000);
      expect(r.skipped, ['raju sand', 'NEW BRICKS']);
      expect((await db.syncOutboxDao.pending()).where((o) => o.targetTable == 'vendors'), hasLength(2));
    });
  });

  group('all sites', () {
    final now = DateTime(2026, 11, 7, 19); // Saturday evening

    test('days without a report: Monday to yesterday, Sundays left out', () async {
      await db.dprDao.create(DprEntriesCompanion.insert(
          id: 'd', projectId: site.id, createdBy: 'x', entryDate: DateTime(2026, 11, 3, 18), workSummary: 's'));
      final reports = await db.dprDao.forProject(site.id);
      final missing = missingReportDays(reports, now);
      expect(missing.map((d) => d.day), [2, 4, 5, 6]);
      // On a Monday nothing is missing yet.
      expect(missingReportDays(const [], DateTime(2026, 11, 9, 10)), isEmpty);
    });

    test('client money: billed less received, retention kept back, never below zero', () async {
      await db.billDao.create(ClientBillsCompanion.insert(
          id: 'b1', projectId: site.id, kind: 'ra', billNumber: 'RA-1', billDate: DateTime(2026, 10, 1), clientName: 'Client',
          linesJson: '[]', gross: 100000, netPayable: 95000, retentionPct: const Value(5), recordedBy: 'pm'));
      await db.paymentDao.create(PaymentsReceivedCompanion.insert(
          id: 'p1', projectId: site.id, amount: 60000, receivedOn: DateTime(2026, 10, 10), fromParty: 'Client', mode: 'bank',
          recordedBy: 'pm'));
      final m = clientMoney(await db.billDao.forProject(site.id), await db.paymentDao.forProject(site.id));
      expect(m.receivable, 35000);
      expect(m.retention, 5000);
    });

    test('the portfolio puts the site that needs someone first and skips sites not running or hidden', () async {
      final quiet = await db.projectDao.create(
          ProjectsCompanion.insert(id: 'site-q', companyId: company.id, name: 'All well', status: const Value('active')));
      for (var d = 2; d <= 6; d++) {
        await db.dprDao.create(DprEntriesCompanion.insert(
            id: 'q$d', projectId: quiet.id, createdBy: 'x', entryDate: DateTime(2026, 11, d, 18), workSummary: 'ok'));
      }
      await db.projectDao.create(ProjectsCompanion.insert(id: 'site-done', companyId: company.id, name: 'Old', status: const Value('completed')));
      await db.approvalDao.create(ApprovalsCompanion.insert(
          id: 'a1', projectId: Value(site.id), entityType: 'expense', entityId: 'e1', requestedBy: 'sup',
          createdAt: Value(DateTime(2026, 11, 4))));

      final list = await buildPortfolio(db, company.id, now: now);
      expect(list.map((s) => s.project.name), ['Kompally Villas', 'All well']);
      final busy = list.first;
      expect(busy.missingReportDays, hasLength(5));
      expect(busy.overdueApprovals, 1);
      expect(list.last.allWell, isTrue);
      expect(PortfolioTotals(list).needingAttention, 1);

      final onlyQuiet = await buildPortfolio(db, company.id, visible: {quiet.id}, now: now);
      expect(onlyQuiet.single.project.id, quiet.id);
    });
  });
}
