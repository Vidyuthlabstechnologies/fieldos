/// Multi-level approvals on the server, with three phones against the
/// local Supabase stack (skips itself when the stack is not running).
/// The owner's rules reach every phone, and change later by the change log.
/// The server enforces these:
/// - only the owner signs the owner's level;
/// - a site PM signs within their limit, even when the phone sends a
///   smaller amount;
/// - the weekly close can't approve an expense, and a PO can't be raised
///   from a request, until the chain is complete.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  test('approval rules sync, and the server holds each level to who may sign it', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final sitePm = await CloudPhone.signUp('sitepm');
    final engineer = await CloudPhone.signUp('engineer');
    final company = await owner.db.companyDao.create('Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final villas = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final vendor = await owner.db.supplierDao.create(SuppliersCompanion.insert(id: uuid.v4(), companyId: company.id, name: 'Sri Balaji'));
    expect((await owner.engine.pushPending()).failed, 0);
    await sitePm.service.joinCompany(cloud.joinCode!);
    await engineer.service.joinCompany(cloud.joinCode!);
    await owner.db.siteTeamDao
        .setMember(projectId: villas.id, userId: sitePm.remoteUserId, role: SiteRole.projectManager, approvalLimit: 50000);

    // The owner's rules: expenses above 10,000 need a PM, above 1 lakh the
    // owner too; purchase requests above 20,000 a PM, above 50,000 the owner.
    final rules = owner.db.approvalChainDao;
    await rules.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.projectManager, above: 10000, by: owner.localUserId);
    await rules.setRule(company.id, kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 100000, by: owner.localUserId);
    await rules.setRule(company.id, kind: ApprovalKind.purchaseRequest, role: ApprovalLevel.projectManager, above: 20000, by: owner.localUserId);
    await rules.setRule(company.id, kind: ApprovalKind.purchaseRequest, role: ApprovalLevel.owner, above: 50000, by: owner.localUserId);
    var push = await owner.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await owner.db.select(owner.db.syncOutbox).get()) "${e.targetTable} ${e.operation} ${e.lastError}"]}');
    await expectLater(
        sitePm.client.from('site_approval_rules').insert({
          'id': uuid.v4(), 'company_id': company.id, 'kind': 'expense', 'role': 'owner', 'above_amount': 1,
          'created_by': sitePm.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()), reason: 'only the owner sets rules');

    // The engineer's phone gets the rules, and later a change to one.
    await engineer.engine.pullAll();
    expect((await engineer.db.approvalChainDao.rulesFor(company.id)).length, 4);
    await rules.setRule(company.id, kind: ApprovalKind.purchaseRequest, role: ApprovalLevel.projectManager, above: 25000, by: owner.localUserId);
    expect((await owner.engine.pushPending()).failed, 0);
    await engineer.engine.pullAll();
    expect(
        (await engineer.db.approvalChainDao.rulesFor(company.id))
            .firstWhere((r) => r.kind == ApprovalKind.purchaseRequest && r.role == ApprovalLevel.projectManager)
            .aboveAmount,
        25000,
        reason: 'company-wide rows come through the change log too');

    // The engineer books two expenses and asks for cement.
    final today = DateTime.now().toIso8601String().substring(0, 10);
    Future<SiteExpense> expense(double amount) => engineer.db.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: villas.id, category: 'Material', amount: amount, incurredOn: today, recordedBy: engineer.localUserId));
    final mid = await expense(40000);
    final big = await expense(150000);
    final request = await engineer.db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
        id: uuid.v4(), projectId: villas.id, raisedBy: engineer.localUserId, materialName: 'Cement OPC 53',
        quantity: const Value(200), unit: const Value('bag'), estimatedAmount: const Value(80000)));
    push = await engineer.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await engineer.db.select(engineer.db.syncOutbox).get()) "${e.targetTable} ${e.lastError}"]}');

    Map<String, dynamic> step(CloudPhone by, String kind, String itemId, String level, {double amount = 1}) => {
          'id': uuid.v4(), 'project_id': villas.id, 'kind': kind, 'item_id': itemId, 'level': level,
          'decision': 'approved', 'amount': amount, 'decided_by': by.remoteUserId,
        };
    await expectLater(engineer.client.from('site_approval_steps').insert(step(engineer, 'expense', mid.id, 'project_manager')),
        throwsA(isA<PostgrestException>()), reason: 'an engineer signs nothing');
    await expectLater(sitePm.client.from('site_approval_steps').insert(step(sitePm, 'expense', big.id, 'owner')),
        throwsA(isA<PostgrestException>()), reason: "only the owner signs the owner's level");
    await expectLater(sitePm.client.from('site_approval_steps').insert(step(sitePm, 'expense', big.id, 'project_manager')),
        throwsA(isA<PostgrestException>()), reason: 'above their limit, whatever amount the phone sends');

    // The site PM approves the 40,000 expense in the weekly close: it signs
    // and completes. The big one can't be approved by a bare review.
    await sitePm.engine.pullAll();
    final pmAccess = await siteAccessFor(sitePm.db, villas.id, userId: sitePm.localUserId, companyRole: Roles.member);
    final pmWeek = await loadWeekClose(sitePm.db, villas, DateTime.now());
    final pmActions = CloseActions(sitePm.db, userId: sitePm.localUserId, role: Roles.member, site: pmAccess);
    expect(await pmActions.approve(pmWeek, pmWeek.items.firstWhere((i) => i.id == mid.id)), isNotNull);
    push = await sitePm.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await sitePm.db.select(sitePm.db.syncOutbox).get()) e.lastError]}');
    await expectLater(
        owner.client.from('site_close_reviews').insert({
          'id': uuid.v4(), 'project_id': villas.id, 'week_start': pmWeek.weekKey, 'item_kind': 'expense', 'item_id': big.id,
          'decision': 'approved', 'decided_by': owner.remoteUserId, 'amount': 150000,
        }),
        throwsA(isA<PostgrestException>()), reason: 'the chain is not complete');

    // A PO from the request is refused until the owner approves it.
    await expectLater(
        owner.client.from('purchase_orders').insert({
          'id': uuid.v4(), 'project_id': villas.id, 'vendor_id': vendor.id, 'requisition_id': request.id,
          'created_by': owner.remoteUserId, 'total_amount': 80000, 'status': 'issued',
        }),
        throwsA(isA<PostgrestException>()));

    // The owner's phone: approving the big expense signs and records it;
    // signing the request lets the PO through.
    await owner.engine.pullAll();
    final ownerWeek = await loadWeekClose(owner.db, villas, DateTime.now());
    expect(await CloseActions(owner.db, userId: owner.localUserId, role: Roles.owner)
        .approve(ownerWeek, ownerWeek.items.firstWhere((i) => i.id == big.id)), isNotNull);
    await owner.db.approvalChainDao.sign(
        projectId: villas.id, kind: ApprovalKind.purchaseRequest, itemId: request.id, level: ApprovalLevel.owner, approve: true,
        amount: 80000, by: owner.localUserId);
    await owner.db.purchaseDao.orderFromRequest(request.id, PurchaseOrdersCompanion.insert(
        id: uuid.v4(), projectId: villas.id, supplierId: vendor.id, raisedBy: owner.localUserId, totalAmount: const Value(80000)));
    push = await owner.engine.pushPending();
    expect(push.failed, 0, reason: '${[for (final e in await owner.db.select(owner.db.syncOutbox).get()) "${e.targetTable} ${e.operation} ${e.lastError}"]}');
    final steps = await owner.client.from('site_approval_steps').select('item_id, level, amount').eq('project_id', villas.id);
    expect({for (final s in steps) '${s['item_id']}|${s['level']}': (s['amount'] as num).toDouble()}, {
      '${mid.id}|project_manager': 40000,
      '${big.id}|owner': 150000,
      '${request.id}|owner': 80000,
    });

    // Everyone's phone sees the signatures.
    await engineer.engine.pullAll();
    expect((await engineer.db.approvalChainDao.stepsFor(villas.id)).length, 3);

    await owner.close();
    await sitePm.close();
    await engineer.close();
  });
}
