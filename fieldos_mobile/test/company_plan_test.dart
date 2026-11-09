/// Company plans (sold by invoice, switched on by the FieldOS team): who
/// they let in, offline too, and the active-site limit on every way a site
/// is opened (new project, reopening a completed one, the assistant).
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';

void main() {
  late AppDatabase db;
  late CompanyPlanService service;

  CompanyPlan sitePro({String? companyId = 'c1', int? limit = 3, DateTime? endsOn}) => CompanyPlan(
        companyId: companyId,
        companyName: companyId == null ? null : 'Builder One',
        plan: 'site_pro',
        siteLimit: limit,
        endsOn: endsOn ?? DateTime(2027, 3, 31),
      );

  setUp(() {
    db = AppDatabase.memory();
    service = CompanyPlanService(db: db, cloud: null, available: false);
  });
  tearDown(() => db.close());

  Future<void> addSite(String id, String status, {String company = 'c1'}) =>
      db.projectDao.create(ProjectsCompanion.insert(id: id, companyId: company, name: 'Site $id', status: Value(status)));

  test('parses the server answer and ignores junk', () {
    final plans = parseCompanyPlans(jsonDecode('''[
      {"company_id": "c1", "company_name": "Builder One", "plan": "business", "site_limit": 10,
       "ends_on": "2027-03-31", "active_sites": 4},
      {"company_id": null, "company_name": null, "plan": "enterprise", "site_limit": null,
       "ends_on": "2027-12-31", "active_sites": 0},
      "junk"
    ]'''));
    expect(plans, hasLength(2));
    expect(plans[0].name, 'FieldOS Business');
    expect(plans[0].sitesLine, 'Up to 10 active sites');
    expect(plans[0].activeSites, 4);
    expect(plans[1].siteLimit, isNull);
    expect(plans[1].sitesLine, 'Unlimited sites');
    expect(parseCompanyPlans(null), isEmpty);
    expect(parseCompanyPlans({'error': 'x'}), isEmpty);
  });

  test('never shows a price', () {
    for (final p in ['pilot', 'site_pro', 'business', 'enterprise']) {
      final plan = CompanyPlan(plan: p, endsOn: DateTime(2027, 1, 1), siteLimit: 3, companyName: 'X');
      expect('${plan.name} ${plan.describe()}', isNot(contains('₹')));
      expect(siteLimitMessage(plan, 3)!, isNot(contains('₹')));
    }
  });

  test('a plan for this company wins over one granted by email', () {
    final byEmail = sitePro(companyId: null, limit: 1);
    final own = sitePro(limit: 10);
    expect(planForCompany([byEmail, own], 'c1'), same(own));
    expect(planForCompany([byEmail, own], 'c2'), same(byEmail));
    expect(planForCompany([own], 'c2'), isNull);
  });

  test('lets people in while covered, and for 3 days offline after the last day', () async {
    final now = DateTime(2027, 3, 31, 18);
    expect(await service.access(live: const [], now: now), Access.blocked);
    expect(await service.access(live: [sitePro()], now: now), Access.allowed);

    await service.remember([sitePro()]);
    // Offline: the last answer counts through the last day, plus the grace.
    expect(await service.access(live: null, now: now), Access.allowed);
    expect(await service.access(live: null, now: DateTime(2027, 4, 3, 12)), Access.allowed);
    expect(await service.access(live: null, now: DateTime(2027, 4, 5)), Access.blocked);

    // The server saying "none" ends it at once.
    await service.remember(const []);
    expect(await service.access(live: null, now: now), Access.blocked);
  });

  test('completed sites do not count; on hold and planning do', () async {
    await service.remember([sitePro()]);
    await addSite('a', 'active');
    await addSite('b', 'on_hold');
    expect(await newActiveSiteBlocked(db, 'c1'), isNull);
    await addSite('c', 'planning');
    final blocked = await newActiveSiteBlocked(db, 'c1');
    expect(blocked, contains('covers 3 active sites'));
    expect(blocked, contains('Mark a finished site Completed'));

    await db.projectDao.setStatus('b', 'completed');
    expect(await newActiveSiteBlocked(db, 'c1'), isNull);
    // Reopening a completed site is not counted twice.
    await addSite('d', 'active');
    expect(await newActiveSiteBlocked(db, 'c1', reopening: 'b'), isNotNull);
    await db.projectDao.setStatus('a', 'completed');
    expect(await newActiveSiteBlocked(db, 'c1', reopening: 'a'), isNull);
  });

  test('no plan, or an unlimited one, never limits sites', () async {
    for (var i = 0; i < 12; i++) {
      await addSite('s$i', 'active');
    }
    expect(await newActiveSiteBlocked(db, 'c1'), isNull);
    await service.remember([sitePro(limit: null)]);
    expect(await newActiveSiteBlocked(db, 'c1'), isNull);
    // Another company's plan doesn't apply here.
    await service.remember([sitePro(companyId: 'c2', limit: 1)]);
    expect(await newActiveSiteBlocked(db, 'c1'), isNull);
  });

  test('the assistant cannot open a site past the limit', () async {
    await service.remember([sitePro(limit: 1)]);
    await addSite('a', 'active');
    final tools = AssistantTools(db: db, companyId: 'c1', userId: 'u1', role: 'owner');
    final out = await tools.run('create_project', {'name': 'Tower C'});
    expect(out.isError, isTrue);
    expect(out.result, contains('covers 1 active site'));
    expect((await db.projectDao.forCompany('c1')).length, 1);
  });

  test('a build without the cloud has no company plans', () async {
    expect(await service.current(), isEmpty);
  });
}
