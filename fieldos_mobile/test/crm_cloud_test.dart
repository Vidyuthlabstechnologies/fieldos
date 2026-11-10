/// CRM against the local Supabase stack (skips itself when it is not
/// running), on three phones: the owner adds a lead offline, quotes it
/// and wins it; a project manager sees all of it on their phone; a site
/// engineer in the same company sees none of it and cannot write any.
/// The server keeps an accepted quote as agreed, stamps who made each row,
/// and gives a second phone's clashing quote number a suffix instead of
/// failing its sync.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  const lines = [
    BillLine(description: 'RCC framed structure, G+2', unit: 'sq.ft', rate: 1850, qty: 2400),
    BillLine(description: 'Compound wall', unit: 'rft', rate: 1200, qty: 180),
  ];

  test('owner and PM share the pipeline; a site engineer never sees it', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('crm-owner');
    final pm = await CloudPhone.signUp('crm-pm');
    final engineer = await CloudPhone.signUp('crm-engineer');
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

    // --- The owner, offline: an enquiry, a call, a quote -------------------
    final o = owner.db.crmDao;
    final lead = await o.addLead(
        companyId: company.id,
        name: 'Ramesh Reddy',
        by: owner.localUserId,
        phone: '9849012345',
        workType: 'G+2 house',
        location: 'Plot 42, Kompally',
        estimatedValue: 4500000,
        nextFollowUp: DateTime.now().add(const Duration(days: 2)));
    await o.logActivity(leadId: lead.id, kind: 'call', note: 'Wants to start before Sankranti', by: owner.localUserId);
    final quote = await o.saveQuote(leadId: lead.id, lines: lines, by: owner.localUserId, discount: 16000);
    await pushAll(owner);

    // Made by the owner, whatever the phone sent.
    final row = await adminClient().from('crm_leads').select('created_by, owner_id, stage').eq('id', lead.id).single();
    expect(row['created_by'], owner.remoteUserId);
    expect(row['owner_id'], owner.remoteUserId);
    expect(row['stage'], 'quoted');

    // --- The PM sees it all, the engineer nothing --------------------------
    await pm.engine.pullAll();
    await engineer.engine.pullAll();
    final pl = await pm.db.crmDao.leadsFor(company.id);
    expect(pl.single.name, 'Ramesh Reddy');
    expect(pl.single.ownerId, owner.remoteUserId);
    expect((await pm.db.crmDao.quotesForLead(lead.id)).single.total, quote.total);
    expect((await pm.db.crmDao.activitiesFor(lead.id)).map((a) => a.kind), containsAll(['call', 'stage']));
    expect(await engineer.db.crmDao.leadsFor(company.id), isEmpty);
    expect(await engineer.client.from('crm_leads').select('id'), isEmpty);
    expect(await engineer.client.from('crm_quotes').select('id'), isEmpty);
    await expectLater(
        engineer.client.from('crm_leads').insert({'id': uuid.v4(), 'company_id': company.id, 'name': 'Sneaky'}),
        throwsA(isA<PostgrestException>()));

    // --- Two phones offline pick the same next number ----------------------
    final pmQuote = await pm.db.crmDao.saveQuote(leadId: lead.id, lines: [lines.last], by: pm.localUserId);
    final ownerQuote = await o.saveQuote(leadId: lead.id, lines: [lines.first], by: owner.localUserId);
    expect(pmQuote.quoteNumber, ownerQuote.quoteNumber);
    await pushAll(pm);
    await pushAll(owner);
    final numbers = (await adminClient().from('crm_quotes').select('quote_number').eq('lead_id', lead.id) as List)
        .map((r) => r['quote_number'] as String)
        .toSet();
    expect(numbers.length, 3, reason: 'no two quotes share a number: $numbers');

    // --- Won: the site and its budget reach the PM --------------------------
    final site = await o.convertToSite(leadId: lead.id, siteName: 'Reddy residence', by: owner.localUserId, quoteId: quote.id);
    await pushAll(owner);
    await pm.engine.pullAll();
    expect((await pm.db.projectDao.byId(site.id))?.clientName, 'Ramesh Reddy');
    expect((await pm.db.commercialDao.costCodesFor(site.id)).length, 2);
    final won = await pm.db.crmDao.leadById(lead.id);
    expect((won!.stage, won.projectId), ('won', site.id));

    // The accepted quote is kept as agreed, even by the owner; a won lead stays.
    await expectLater(
        owner.client.from('crm_quotes').update({'total': 1}).eq('id', quote.id).select(),
        throwsA(isA<PostgrestException>()));
    await owner.client.from('crm_leads').delete().eq('id', lead.id);
    expect(await adminClient().from('crm_leads').select('id').eq('id', lead.id), hasLength(1));

    // --- A lost lead must say why -----------------------------------------
    await expectLater(
        owner.client.from('crm_leads').insert(
            {'id': uuid.v4(), 'company_id': company.id, 'name': 'No reason', 'stage': 'lost'}),
        throwsA(isA<PostgrestException>()));
  });
}
