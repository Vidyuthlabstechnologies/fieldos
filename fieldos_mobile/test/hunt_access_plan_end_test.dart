/// Hunt (access): a company plan's last day is a day in India time (the
/// server's ist_today, docs/COMPANY_PLANS.md), whatever time zone the phone
/// is set to. Offline, the phone keeps the plan through the end of that
/// day in India and not a moment more or less.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';

void main() {
  late AppDatabase db;
  late CompanyPlanService service;

  setUp(() {
    db = AppDatabase.memory();
    service = CompanyPlanService(db: db, cloud: null, available: false);
  });
  tearDown(() => db.close());

  final plan = CompanyPlan.fromJson({
    'company_id': 'c1',
    'company_name': 'Builder One',
    'plan': 'site_pro',
    'site_limit': 3,
    'ends_on': '2027-01-12',
  });
  // Midnight starting 13 January in India is 18:30 UTC on 12 January.
  final indiaMidnight = DateTime.utc(2027, 1, 12, 18, 30);

  test('the plan covers through the end of its last day in India time', () async {
    await service.remember([plan], checkedAt: DateTime.utc(2027, 1, 10, 4));
    expect((await service.lastCoveredUntil())!.toUtc(), indiaMidnight);
  });

  test('offline, open until midnight in India, read-only from it', () async {
    await service.remember([plan], checkedAt: DateTime.utc(2027, 1, 10, 4));
    expect(await service.access(live: null, now: indiaMidnight.subtract(const Duration(minutes: 1))), Access.allowed);
    expect(await service.access(live: null, now: indiaMidnight), Access.readOnly);
    expect(await service.readOnlyReason(indiaMidnight), ReadOnlyReason.planEnded);
  });

  test('a plan whose last day has passed, offline, never opens fully', () async {
    final ended = CompanyPlan.fromJson({'company_id': 'c1', 'plan': 'pilot', 'ends_on': '2027-01-01'});
    await service.remember([ended], checkedAt: DateTime.utc(2027, 1, 5));
    expect(await service.access(live: null, now: DateTime.utc(2027, 1, 5, 1)), Access.readOnly);
    expect(await service.readOnlyReason(DateTime.utc(2027, 1, 5, 1)), ReadOnlyReason.planEnded);
  });

  test('the latest of several plans decides', () async {
    final later = CompanyPlan.fromJson({'company_id': null, 'plan': 'business', 'ends_on': '2027-02-28'});
    await service.remember([plan, later], checkedAt: DateTime.utc(2027, 1, 10));
    expect((await service.lastCoveredUntil())!.toUtc(), DateTime.utc(2027, 2, 28, 18, 30));
  });
}
