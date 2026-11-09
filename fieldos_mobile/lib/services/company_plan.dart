/// Company plans: FieldOS for builder firms, sold by the FieldOS team on a
/// GST invoice, outside the app stores. One plan covers everyone in the
/// company (no limit on people) up to a number of active sites. The team
/// switches it on in the backend once the invoice is paid (see
/// supabase/migrations/20261110000000_company_plans.sql); nothing in the
/// app can buy, extend or change one.
///
/// Store rules: the app never shows a company plan's price, and never links
/// or points to a way to buy one. People whose company already has a plan
/// just sign in to their company and get in (Apple 3.1.3(c), enterprise
/// services). The ₹999 per-person store subscription works as before.
library;

import 'dart:convert';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

/// One company plan that covers this person today.
class CompanyPlan {
  const CompanyPlan({
    required this.plan,
    required this.endsOn,
    this.companyId,
    this.companyName,
    this.siteLimit,
    this.activeSites = 0,
  });

  /// Null for a plan the team granted to this person's email before their
  /// company was on the cloud; it attaches to the company they register.
  final String? companyId;
  final String? companyName;

  /// pilot, site_pro, business or enterprise.
  final String plan;

  /// Null means no limit.
  final int? siteLimit;

  /// The last day covered.
  final DateTime endsOn;

  /// Sites not completed, as the server counted them.
  final int activeSites;

  factory CompanyPlan.fromJson(Map<String, dynamic> m) => CompanyPlan(
        companyId: m['company_id'] as String?,
        companyName: m['company_name'] as String?,
        plan: m['plan'] as String,
        siteLimit: (m['site_limit'] as num?)?.toInt(),
        endsOn: DateTime.parse(m['ends_on'] as String),
        activeSites: (m['active_sites'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'company_name': companyName,
        'plan': plan,
        'site_limit': siteLimit,
        'ends_on': endsOn.toIso8601String().substring(0, 10),
        'active_sites': activeSites,
      };

  String get name => switch (plan) {
        'pilot' => 'FieldOS Pilot',
        'site_pro' => 'FieldOS Site Pro',
        'business' => 'FieldOS Business',
        'enterprise' => 'FieldOS Enterprise',
        _ => 'FieldOS company plan',
      };

  /// "Up to 3 active sites", or "Unlimited sites".
  String get sitesLine => siteLimit == null
      ? 'Unlimited sites'
      : 'Up to $siteLimit active site${siteLimit == 1 ? '' : 's'}';

  /// What My subscription and Team & sync say about it.
  String describe() {
    final who = companyName == null ? 'your company' : companyName!;
    return 'Paid by $who until ${fmtDate(endsOn)}. Everyone in the company is included. $sitesLine.';
  }
}

List<CompanyPlan> parseCompanyPlans(Object? json) {
  if (json is! List) return const [];
  return [for (final m in json.whereType<Map>()) CompanyPlan.fromJson(Map<String, dynamic>.from(m))];
}

/// The plan that applies to [companyId]: its own, or one granted by email
/// that has not attached to a company yet (the owner's first company).
CompanyPlan? planForCompany(List<CompanyPlan> plans, String? companyId) {
  for (final p in plans) {
    if (companyId != null && p.companyId == companyId) return p;
  }
  for (final p in plans) {
    if (p.companyId == null) return p;
  }
  return null;
}

/// Why a new or reopened site can't go ahead under [plan], or null when it
/// can. [activeSites] counts this company's sites that are not completed,
/// before the change. No price and no way to buy more here (store rules):
/// the owner's FieldOS contact adds sites to the plan.
String? siteLimitMessage(CompanyPlan? plan, int activeSites) {
  final limit = plan?.siteLimit;
  if (limit == null || activeSites < limit) return null;
  return 'Your company plan covers $limit active site${limit == 1 ? '' : 's'}, and $activeSites are open. '
      'Mark a finished site Completed to start this one, or ask your company owner about adding sites to the plan.';
}

/// Whether a project status counts toward the site limit.
bool countsAsActiveSite(String status) => status != 'completed';

/// Asks the server which company plans cover this person, and remembers
/// the answer for offline use and for the site limit.
class CompanyPlanService {
  CompanyPlanService({required this.db, required this.cloud, this.available = true});

  final AppDatabase db;
  final CloudSyncService? cloud;

  /// False in builds without the cloud: there are no company plans then.
  final bool available;

  static const _plansKey = 'company_plans';
  static const _untilKey = 'company_plan_until';

  /// The server's answer, or null when it can't be asked right now
  /// (offline, or the saved sign-in can't be refreshed yet). An empty list
  /// means none: no cloud account, or no plan.
  Future<List<CompanyPlan>?> current() async {
    final service = cloud;
    if (!available || service == null) return const [];
    try {
      if (!service.isSignedIn) await service.restoreSession();
      if (!service.isSignedIn) {
        // Signed out for good: no plan. A saved session that only failed to
        // refresh (offline) is not an answer yet.
        final saved = await service.sessionStore?.read();
        if (saved != null && saved.isNotEmpty) return null;
        await remember(const []);
        return const [];
      }
      final plans = parseCompanyPlans(await service.client.rpc('my_company_plans'));
      await remember(plans);
      return plans;
    } catch (_) {
      return null;
    }
  }

  /// Keeps [plans] as the last answer (the server's, or a test's).
  Future<void> remember(List<CompanyPlan> plans) async {
    await db.settingsDao.set(_plansKey, jsonEncode([for (final p in plans) p.toJson()]));
    DateTime? until;
    for (final p in plans) {
      // Covered through the whole last day.
      final end = DateTime(p.endsOn.year, p.endsOn.month, p.endsOn.day).add(const Duration(days: 1));
      if (until == null || end.isAfter(until)) until = end;
    }
    await db.settingsDao.set(_untilKey, until?.toUtc().toIso8601String() ?? '');
  }

  /// The last answer, for offline.
  Future<List<CompanyPlan>> remembered() => rememberedCompanyPlans(db);

  Future<DateTime?> lastCoveredUntil() async {
    final raw = await db.settingsDao.get(_untilKey);
    return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  /// Whether a company plan lets this phone in, from [live] (null when the
  /// server couldn't be asked) and the last remembered answer.
  Future<Access> access({required List<CompanyPlan>? live, required DateTime now}) async => accessFor(
        billingSetUp: true,
        live: live == null ? null : SubscriptionState(active: live.isNotEmpty),
        lastPaidUntil: await lastCoveredUntil(),
        now: now,
      );

  Future<String?> checkNewActiveSite(String companyId, {String? reopening}) =>
      newActiveSiteBlocked(db, companyId, reopening: reopening);
}

/// The company plans this phone last heard of (kept by [CompanyPlanService]).
Future<List<CompanyPlan>> rememberedCompanyPlans(AppDatabase db) async {
  final raw = await db.settingsDao.get(CompanyPlanService._plansKey);
  if (raw == null || raw.isEmpty) return const [];
  try {
    return parseCompanyPlans(jsonDecode(raw));
  } catch (_) {
    return const [];
  }
}

/// Why [companyId] can't open one more active site under its company plan,
/// or null when it can (or has no plan). Works offline, from the last
/// answer and this phone's own projects. [reopening] is a site being moved
/// out of Completed, which is not counted twice.
Future<String?> newActiveSiteBlocked(AppDatabase db, String companyId, {String? reopening}) async {
  final plan = planForCompany(await rememberedCompanyPlans(db), companyId);
  if (plan?.siteLimit == null) return null;
  final open = (await db.projectDao.forCompany(companyId))
      .where((p) => p.id != reopening && countsAsActiveSite(p.status))
      .length;
  return siteLimitMessage(plan, open);
}

/// Thrown when a site would go past the company plan's site limit.
class SiteLimitReached implements Exception {
  SiteLimitReached(this.message);
  final String message;

  @override
  String toString() => message;
}
