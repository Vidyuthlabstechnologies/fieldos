/// Stores, tools and salaries against the local Supabase stack (skips
/// itself when it is not running), on three phones. The owner buys cement
/// into the yard and sends it to a site; the site engineer's phone gets the
/// transfer, counts it in short, and the server stamps who received it.
/// The engineer cannot buy into a store, rewrite a move or edit the tools
/// register, but a damaged tool they take back goes for repair. Salaries
/// reach the project manager and never the engineer, and a paid salary is
/// kept as it was paid.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  test('a transfer from the yard is counted in at the site; salaries stay with the managers', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('wh-owner');
    final pm = await CloudPhone.signUp('wh-pm');
    final engineer = await CloudPhone.signUp('wh-engineer');
    addTearDown(() async {
      for (final p in [owner, pm, engineer]) {
        await p.close();
      }
    });

    final company = await owner.db.companyDao.create('Sai Constructions');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    await pm.service.joinCompany(cloud.joinCode!);
    await engineer.service.joinCompany(cloud.joinCode!);
    await adminClient()
        .from('company_members')
        .update({'role': 'project_manager'}).match({'company_id': company.id, 'user_id': pm.remoteUserId});

    final siteId = uuid.v4();
    await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: siteId, companyId: company.id, name: 'Narapally', status: const Value('active')));
    final w = owner.db.warehouseDao;
    final yard = await w.addStore(companyId: company.id, name: 'Main yard', by: owner.localUserId);
    await w.addMove(
        companyId: company.id, kind: 'inward', materialName: 'Cement', unit: 'bags', quantity: 100, rate: 390,
        toStoreId: yard.id, supplierName: 'Balaji Traders', by: owner.localUserId);
    final sent = await w.addMove(
        companyId: company.id, kind: 'transfer', materialName: 'Cement', unit: 'bags', quantity: 40,
        fromStoreId: yard.id, toProjectId: siteId, vehicle: 'TS09 AB 1234', by: owner.localUserId);
    final drill = await w.addTool(companyId: company.id, name: 'Drill machine', value: 6500, by: owner.localUserId);
    final issue = await w.issueTool(toolId: drill.id, issuedTo: 'Ravi', projectId: siteId, by: owner.localUserId);
    await pushAll(owner);

    final row = await adminClient().from('stock_moves').select('sent_by, status, rate').eq('id', sent.id).single();
    expect(row['sent_by'], owner.remoteUserId);
    expect(row['status'], 'in_transit');
    expect((row['rate'] as num).toDouble(), 390);

    // --- The engineer's phone counts it in ---------------------------------
    await engineer.engine.pullAll();
    final e = engineer.db.warehouseDao;
    final incoming = await e.movesForSite(siteId);
    expect(incoming.single.id, sent.id);
    expect(incoming.single.status, 'in_transit');
    await e.receive(sent.id, by: engineer.localUserId, arrived: 38, note: '2 bags torn');
    await pushAll(engineer);
    final got = await adminClient().from('stock_moves').select('status, received_by, received_qty').eq('id', sent.id).single();
    expect(got['status'], 'received');
    expect(got['received_by'], engineer.remoteUserId);
    expect((got['received_qty'] as num).toDouble(), 38);
    final stock = buildSiteStock(const [], const [], moves: await e.movesForSite(siteId), projectId: siteId);
    expect(stock.single.balance, 38);

    // Not theirs to do: buy into a store, rewrite a move, edit the register.
    await expectLater(
        engineer.client.from('stock_moves').insert({
          'id': uuid.v4(), 'company_id': company.id, 'kind': 'inward', 'to_store_id': yard.id,
          'material_name': 'Cement', 'quantity': 1000, 'sent_on': DateTime.now().toUtc().toIso8601String(),
        }),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        engineer.client.from('stock_moves').update({'quantity': 1}).eq('id', sent.id).select(),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        engineer.client.from('stores').insert({'id': uuid.v4(), 'company_id': company.id, 'name': 'Mine'}),
        throwsA(isA<PostgrestException>()));
    final edited = await engineer.client.from('tools').update({'value': 1}).eq('id', drill.id).select();
    expect(edited, isEmpty, reason: 'the register is not theirs to edit');

    // A tool they take back damaged goes for repair on the server.
    await e.returnTool(issue.id, condition: 'damaged', recoverAmount: 800);
    await pushAll(engineer);
    final tool = await adminClient().from('tools').select('condition, value').eq('id', drill.id).single();
    expect(tool['condition'], 'repair');
    expect((tool['value'] as num).toDouble(), 6500);

    // --- Salaries ----------------------------------------------------------
    final p = owner.db.payrollDao;
    final anil = await p.addStaff(
        companyId: company.id, name: 'Anil', basic: 18000, hra: 7000, otherAllowance: 3000, projectId: siteId);
    await p.giveAdvance(staffId: anil.id, amount: 2000, by: owner.localUserId);
    await p.makeMonth(company.id, '2026-11', by: owner.localUserId);
    final line = (await p.linesForMonth(company.id, '2026-11')).single;
    await p.markPaid(line.id, mode: 'bank', by: owner.localUserId);
    await pushAll(owner);

    await pm.engine.pullAll();
    await engineer.engine.pullAll();
    final pmLine = (await pm.db.payrollDao.linesForMonth(company.id, '2026-11')).single;
    expect(pmLine.net, 24000);
    expect(pmLine.status, 'paid');
    expect((await pm.db.payrollDao.staffFor(company.id)).single.name, 'Anil');
    expect(await engineer.db.payrollDao.staffFor(company.id), isEmpty);
    expect(await engineer.client.from('staff_members').select('id'), isEmpty);
    expect(await engineer.client.from('payroll_lines').select('id'), isEmpty);
    await expectLater(
        engineer.client.from('staff_members').insert({'id': uuid.v4(), 'company_id': company.id, 'name': 'X', 'basic': 1}),
        throwsA(isA<PostgrestException>()));

    // The salary expense reached the site's money book on the server.
    final expenses = await adminClient().from('site_expenses').select('amount, category').eq('project_id', siteId);
    expect(expenses.single['category'], 'Staff salary');
    expect((expenses.single['amount'] as num).toDouble(), 24000);

    // A paid salary is kept; deleting it does nothing.
    await expectLater(
        owner.client.from('payroll_lines').update({'net': 1, 'status': 'draft'}).eq('id', line.id).select(),
        throwsA(isA<PostgrestException>()));
    await owner.client.from('payroll_lines').delete().eq('id', line.id);
    expect(await adminClient().from('payroll_lines').select('id').eq('id', line.id), hasLength(1));
  });
}
