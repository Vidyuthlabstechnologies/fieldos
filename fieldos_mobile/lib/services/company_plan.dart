/// Company plans: FieldOS for builder firms, sold by the FieldOS team on a
/// GST invoice, outside the app stores. One plan covers everyone in the
/// company (no limit on people) up to a number of active sites. The team
/// switches it on in the backend once the invoice is paid (see
/// supabase/migrations/20261111130000_company_plans.sql); nothing in the
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
    return 'Paid by $who until ${fmtDate(endsOn, english: true)}. Everyone in the company is included. $sitesLine.';
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
  return siteLimitMessageFor(limit, activeSites);
}

/// The site-limit message for [limit] sites with [activeSites] open: on the
/// phone's own check, and when the server refuses a site the phone sent
/// (it counts every site of the company, including ones this phone has not
/// pulled yet).
String siteLimitMessageFor(int limit, int activeSites) {
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

  /// When the server last answered my_company_plans (phone time, UTC).
  static const _checkedKey = 'company_plan_checked_at';

  /// The latest time this phone has seen since that answer, so a clock
  /// moved back later is noticed too.
  static const _seenKey = 'company_plan_seen_at';

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
      await remember(plans, checkedAt: DateTime.now());
      return plans;
    } catch (_) {
      return null;
    }
  }

  /// Keeps [plans] as the last answer (the server's, or a test's), given
  /// at [checkedAt] (now when not given): the start of the 7 days offline.
  Future<void> remember(List<CompanyPlan> plans, {DateTime? checkedAt}) async {
    final at = (checkedAt ?? DateTime.now()).toUtc().toIso8601String();
    await db.settingsDao.set(_plansKey, jsonEncode([for (final p in plans) p.toJson()]));
    await db.settingsDao.set(_checkedKey, at);
    await db.settingsDao.set(_seenKey, at);
    DateTime? until;
    for (final p in plans) {
      // Covered through the whole last day, in India time like the
      // server's ist_today, whatever zone the phone is set to.
      final end = DateTime.utc(p.endsOn.year, p.endsOn.month, p.endsOn.day + 1).subtract(planDayUtcOffset);
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

  Future<DateTime?> _time(String key) async {
    final raw = await db.settingsDao.get(key);
    return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  /// Whether a company plan lets this phone in, from [live] (null when the
  /// server couldn't be asked) and the last remembered answer. Offline, see
  /// [offlineCompanyAccess]: fully usable for 7 days after the last answer
  /// (never past the plan's last day), then read-only until the server is
  /// reached again.
  Future<Access> access({required List<CompanyPlan>? live, required DateTime now}) async {
    if (live != null) return live.isNotEmpty ? Access.allowed : Access.blocked;
    final until = await lastCoveredUntil();
    var checked = await _time(_checkedKey);
    if (checked == null && until != null) {
      // A phone that remembered a plan before this rule (no time kept):
      // the 7 days start now, once.
      checked = now;
      await db.settingsDao.set(_checkedKey, now.toUtc().toIso8601String());
    }
    final seen = await _time(_seenKey);
    if (seen == null || now.isAfter(seen)) await db.settingsDao.set(_seenKey, now.toUtc().toIso8601String());
    return offlineCompanyAccess(coveredUntil: until, lastChecked: checked, latestSeen: seen, now: now);
  }

  /// Why the phone is read-only now, for the banner (call after [access]
  /// said [Access.readOnly]).
  Future<ReadOnlyReason> readOnlyReason(DateTime now) async {
    final until = await lastCoveredUntil();
    return until != null && !now.isBefore(until) ? ReadOnlyReason.planEnded : ReadOnlyReason.offlineTooLong;
  }

  Future<String?> checkNewActiveSite(String companyId, {String? reopening}) =>
      newActiveSiteBlocked(db, companyId, reopening: reopening);
}

/// A plan's days are India days (the server's ist_today, Asia/Kolkata,
/// UTC+5:30 with no daylight saving): ends_on is the last India date covered.
const planDayUtcOffset = Duration(hours: 5, minutes: 30);

/// How long a phone on a company plan stays fully usable with no answer
/// from the server. After that it is read-only until it reaches the server.
const companyPlanOfflineDays = Duration(days: 7);

/// Small clock corrections (the network setting the time) are not a clock
/// moved back.
const clockSkewAllowance = Duration(minutes: 10);

/// A company plan's access with no answer from the server.
/// [coveredUntil]: the end of the remembered plan's last day (null: no plan
/// last time, so blocked). [lastChecked]: when the server last answered.
/// [latestSeen]: the latest time this phone has seen since then.
///
/// Fully usable while now is within 7 days of [lastChecked] and before
/// [coveredUntil]; read-only otherwise, until the server answers again. A
/// clock set back (now before [lastChecked], or before [latestSeen]) counts
/// as expired: read-only. A clock set forward just ends the 7 days early.
Access offlineCompanyAccess({
  required DateTime? coveredUntil,
  required DateTime? lastChecked,
  DateTime? latestSeen,
  required DateTime now,
}) {
  if (coveredUntil == null) return Access.blocked;
  if (lastChecked == null) return Access.readOnly;
  final earliestOk = now.add(clockSkewAllowance);
  if (earliestOk.isBefore(lastChecked)) return Access.readOnly;
  if (latestSeen != null && earliestOk.isBefore(latestSeen)) return Access.readOnly;
  final fullUntil = lastChecked.add(companyPlanOfflineDays);
  if (now.isBefore(fullUntil) && now.isBefore(coveredUntil)) return Access.allowed;
  return Access.readOnly;
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
