/// CRM: an enquiry from a plot owner is followed up, quoted twice (the
/// second with a discount), won, and becomes a site whose budget lines are
/// the accepted quote's items; another enquiry is lost to price. The
/// pipeline, the working order and the reminders follow every step, and
/// every change waits in the outbox for the server.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/crm/quote_pdf.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

void main() {
  late AppDatabase db;
  late CrmDao dao;
  late Company company;
  const owner = 'owner-1';

  setUp(() async {
    db = AppDatabase.memory();
    dao = db.crmDao;
    company = await db.companyDao.create('Sai Constructions');
  });
  tearDown(() => db.close());

  const lines = [
    BillLine(description: 'RCC framed structure, G+2', unit: 'sq.ft', rate: 1850, qty: 2400),
    BillLine(description: 'Compound wall', unit: 'rft', rate: 1200, qty: 180),
  ];

  group('quote totals', () {
    test('discount comes off before GST, which splits CGST and SGST inside the state', () {
      final t = quoteTotals(lines, discount: 16000, gstRate: 18);
      expect(t.subtotal, 4656000);
      expect(t.discount, 16000);
      expect(t.taxable, 4640000);
      expect(t.cgst, 417600);
      expect(t.sgst, 417600);
      expect(t.igst, 0);
      expect(t.total, 5475200);
    });

    test('across states it is all IGST, and a discount never goes below zero', () {
      final t = quoteTotals([lines.first], discount: 9e9, gstRate: 18, interState: true);
      expect(t.discount, t.subtotal);
      expect(t.taxable, 0);
      expect(t.igst, 0);
      expect(t.total, 0);
      final u = quoteTotals([lines.first], gstRate: 12, interState: true);
      expect(u.igst, 532800);
      expect(u.cgst + u.sgst, 0);
    });

    test('quote numbers run across the company by month', () {
      final nov = DateTime(2026, 11, 10);
      expect(nextQuoteNumber(const [], nov), 'Q-2611-001');
      expect(nextQuoteNumber(const ['Q-2610-004', 'Q-2611-002', 'RA-09', 'Q-2611-002-ab12cd'], nov), 'Q-2611-005');
    });

    test('a won quote gives one budget line per priced item', () {
      final b = budgetLinesFromQuote([...lines, const BillLine(description: ' ', unit: '', rate: 5, qty: 1)]);
      expect(b.map((x) => x.code), ['Q-01', 'Q-02']);
      expect(b.first.name, 'RCC framed structure, G+2 (sq.ft)');
      expect(b.first.budget, 4440000);
    });
  });

  test('an enquiry from first call to a site with its budget', () async {
    final now = DateTime(2026, 11, 10, 11);
    final lead = await dao.addLead(
      companyId: company.id,
      name: 'Ramesh Reddy',
      by: owner,
      phone: '98490 12345',
      location: 'Plot 42, Kompally',
      source: 'referral',
      workType: 'G+2 house',
      estimatedValue: 4500000,
      nextFollowUp: DateTime(2026, 11, 9),
    );
    expect(lead.stage, 'new');
    expect(lead.ownerId, owner);

    // Yesterday's follow-up is late, and it is first in the working order.
    var all = await dao.leadsFor(company.id);
    expect(isFollowUpOverdue(all.single, now), isTrue);
    var p = pipeline(all, const [], now: now);
    expect(p.overdue, 1);
    expect(p.openValue, 4500000);

    // A call moves it to contacted and sets the visit for Thursday.
    await dao.logActivity(
        leadId: lead.id, kind: 'call', note: 'Wants to start before Sankranti', by: owner, nextFollowUp: DateTime(2026, 11, 12), now: DateTime(2026, 11, 1));
    var l = (await dao.leadById(lead.id))!;
    expect(l.stage, 'contacted');
    expect(l.nextFollowUp, DateTime(2026, 11, 12));
    expect(isFollowUpDue(l, now), isFalse);

    // The first quote moves it to quoted; a revised one with a discount follows.
    final q1 = await dao.saveQuote(leadId: lead.id, lines: lines, by: owner, quoteDate: DateTime(2026, 11, 12));
    expect(q1.quoteNumber, 'Q-2611-001');
    expect(q1.total, 5494080);
    expect((await dao.leadById(lead.id))!.stage, 'quoted');
    await dao.setQuoteStatus(q1.id, 'rejected', by: owner);
    final q2 = await dao.saveQuote(
        leadId: lead.id, lines: lines, by: owner, discount: 16000, quoteDate: DateTime(2026, 11, 14));
    expect(q2.quoteNumber, 'Q-2611-002');
    expect(q2.total, 5475200);

    // The lead is now worth its latest live quote, not the old estimate.
    final quotes = await dao.quotesForLead(lead.id);
    expect(leadValue((await dao.leadById(lead.id))!, quotes), 5475200);

    // Won: the site appears with the client, and the quote's items are its budget.
    final site = await dao.convertToSite(leadId: lead.id, siteName: 'Reddy residence, Kompally', by: owner, quoteId: q2.id);
    expect(site.clientName, 'Ramesh Reddy');
    expect(site.status, 'planning');
    final budget = await db.commercialDao.costCodesFor(site.id);
    expect(budget.map((c) => (c.code, c.originalBudget)), [('Q-01', 4440000.0), ('Q-02', 216000.0)]);
    l = (await dao.leadById(lead.id))!;
    expect(l.stage, 'won');
    expect(l.projectId, site.id);
    expect(l.nextFollowUp, isNull);
    expect((await dao.quoteById(q2.id))!.status, 'accepted');

    // Converting again returns the same site rather than a second one.
    final again = await dao.convertToSite(leadId: lead.id, siteName: 'x', by: owner, quoteId: q2.id);
    expect(again.id, site.id);
    expect((await db.projectDao.forCompany(company.id)).length, 1);

    // The accepted quote and the won lead are kept as they are.
    expect(() => dao.saveQuote(id: q2.id, leadId: lead.id, lines: lines, by: owner), throwsArgumentError);
    expect(() => dao.deleteQuote(q2.id), throwsArgumentError);
    expect(() => dao.deleteLead(lead.id), throwsArgumentError);

    // The history reads in order, newest first.
    final history = await dao.activitiesFor(lead.id);
    expect(history.map((a) => a.kind), containsAllInOrder(['stage', 'stage', 'stage', 'call']));
    expect(history.first.note, 'Quoted -> Won: Reddy residence, Kompally');

    // Every change waits for the server, the site and its budget included.
    final queued = (await db.syncOutboxDao.pending()).map((e) => e.targetTable).toSet();
    expect(queued, containsAll(['crm_leads', 'crm_activities', 'crm_quotes', 'projects', 'cost_codes']));
  });

  test('a lost lead needs its reason, and the pipeline shows what loses jobs', () async {
    final now = DateTime(2026, 11, 20);
    final a = await dao.addLead(companyId: company.id, name: 'Sunita Sharma', by: owner, estimatedValue: 800000);
    final b = await dao.addLead(companyId: company.id, name: 'Green Valley Society', by: owner, estimatedValue: 2200000);
    final c = await dao.addLead(companyId: company.id, name: 'K. Prasad', by: owner);
    expect(() => dao.setStage(a.id, 'lost', by: owner), throwsArgumentError);
    await dao.setStage(a.id, 'lost', by: owner, lostReason: 'Price too high', now: now);
    await dao.setStage(b.id, 'lost', by: owner, lostReason: 'Price too high', now: now);
    await dao.setStage(c.id, 'lost', by: owner, lostReason: 'No response', now: now);
    final won = await dao.addLead(companyId: company.id, name: 'Anil Kumar', by: owner, estimatedValue: 1500000);
    await dao.convertToSite(leadId: won.id, siteName: '', by: owner, now: now);

    final p = pipeline(await dao.leadsFor(company.id), await dao.quotesFor(company.id),
        now: now, since: DateTime(2026, 11));
    expect(p.lostCount, 3);
    expect(p.wonCount, 1);
    expect(p.winRate, 0.25);
    expect(p.wonValue, 1500000);
    expect(p.lostReasons.first, ('Price too high', 2));
    expect(p.openValue, 0);

    // Decided last month: not in this month's figures.
    final dec = pipeline(await dao.leadsFor(company.id), const [], now: now, since: DateTime(2026, 12));
    expect(dec.lostCount + dec.wonCount, 0);

    // Reopening a lost lead clears the reason.
    final back = await dao.setStage(c.id, 'contacted', by: owner);
    expect(back.lostReason, isNull);
    // A site made without a name uses the client's.
    final site = await db.projectDao.byId((await dao.leadById(won.id))!.projectId!);
    expect(site!.name, 'Anil Kumar');
  });

  test('working order: late first, then today, then upcoming, then no next step', () async {
    final now = DateTime(2026, 11, 10, 9);
    Future<CrmLead> add(String n, DateTime? f) => dao.addLead(companyId: company.id, name: n, by: owner, nextFollowUp: f);
    await add('Upcoming', DateTime(2026, 11, 13));
    await add('No step', null);
    await add('Today', DateTime(2026, 11, 10, 18));
    await add('Late', DateTime(2026, 11, 8));
    final order = workingOrder(await dao.leadsFor(company.id), now).map((l) => l.name);
    expect(order, ['Late', 'Today', 'Upcoming', 'No step']);
    final p = pipeline(await dao.leadsFor(company.id), const [], now: now);
    expect(p.dueToday, 2);
    expect(p.overdue, 1);
    expect(p.noNextStep, 1);
  });

  test('morning reminder lists the leads to call, late ones folded into today', () {
    final now = DateTime(2026, 11, 10, 7);
    final plan = planReminders(
      now: now,
      settings: const ReminderSettings(reportOn: false, tasksOn: false, briefOn: false),
      runningSites: 0,
      reportedToday: false,
      openTasks: const [],
      followUps: [
        (name: 'Ramesh Reddy', at: DateTime(2026, 11, 8)),
        (name: 'Green Valley Society', at: DateTime(2026, 11, 10, 17)),
        (name: 'Sunita Sharma', at: DateTime(2026, 11, 12)),
      ],
    );
    expect(plan.length, 2);
    expect(plan.first.at, DateTime(2026, 11, 10, 9, 30));
    expect(plan.first.title, '2 leads to follow up today');
    expect(plan.first.body, 'Green Valley Society, Ramesh Reddy');
    expect(plan.last.title, '1 lead to follow up today');
  });

  test('server rows map both ways, lines as JSON either way', () async {
    final lead = await dao.addLead(companyId: company.id, name: 'Ramesh', by: owner, nextFollowUp: DateTime(2026, 11, 12));
    final q = await dao.saveQuote(leadId: lead.id, lines: lines, by: owner, discount: 100);
    final json = crmQuoteToSupabaseJson(q);
    expect(json['lines'], isA<List>());
    expect(json['total'], q.total);
    final back = crmQuoteFromSupabaseJson({...json, 'created_by': owner});
    expect(back.linesJson.value, q.linesJson);
    final asString = crmQuoteFromSupabaseJson({...json, 'lines': jsonEncode(json['lines']), 'created_by': owner});
    expect(decodeQuoteLines(asString.linesJson.value).length, 2);
    final lj = crmLeadToSupabaseJson(lead);
    expect(lj['company_id'], company.id);
    expect(crmLeadFromSupabaseJson({...lj, 'created_by': owner}).nextFollowUp.value, DateTime(2026, 11, 12));
  });

  test('the quotation PDF builds with the company, the client and the total in words', () async {
    final lead = await dao.addLead(
        companyId: company.id, name: 'Ramesh Reddy', by: owner, workType: 'G+2 house', location: 'Kompally');
    final q = await dao.saveQuote(leadId: lead.id, lines: lines, by: owner, discount: 16000);
    final bytes = await buildQuotePdf(quote: q, lead: lead, companyName: company.name);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(quoteShareText(q, lead, company.name), contains('Q-2611-001'.substring(0, 2)));
    expect(quoteShareText(q, lead, company.name), contains('G+2 house'));
  });
}
