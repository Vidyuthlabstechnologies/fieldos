/// Whether this phone may use FieldOS right now, and the plans in plain
/// words. Pure logic, kept apart from the store SDK so it can be tested.
///
/// Pricing: everyone pays. Each person starts with the store's 3-day free
/// trial (set up on the subscription in Play Console / App Store Connect,
/// so Google and Apple decide who is eligible and charge when it ends),
/// then the subscription renews until cancelled.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class SubscriptionState {
  const SubscriptionState({
    required this.active,
    this.inTrial = false,
    this.expiresAt,
    this.willRenew = false,
    this.billingIssue = false,
    this.complimentary = false,
  });

  static const none = SubscriptionState(active: false);

  final bool active;
  final bool inTrial;
  final DateTime? expiresAt;
  final bool willRenew;

  /// The store could not take the last payment (card expired, UPI mandate
  /// cancelled). The person keeps access during the store's grace period.
  final bool billingIssue;

  /// Given free by the FieldOS team (an access code, or free time granted
  /// in RevenueCat), not bought: there is nothing to manage or cancel in
  /// the store.
  final bool complimentary;

  String describe() {
    if (!active) return tr('No active subscription');
    final date = expiresAt == null ? null : fmtDate(expiresAt!);
    final d = {'date': date ?? ''};
    if (complimentary) {
      return date == null ? tr('Free access from the FieldOS team') : trf('Free access from the FieldOS team until {date}', d);
    }
    if (billingIssue) {
      return date == null
          ? tr('Payment problem: update your payment method in the store')
          : trf('Payment problem: update your payment method in the store before {date}', d);
    }
    if (inTrial) {
      if (date == null) return willRenew ? tr('Free trial, then paid') : tr('Free trial (will not renew)');
      return willRenew ? trf('Free trial until {date}, then paid', d) : trf('Free trial until {date} (will not renew)', d);
    }
    if (date == null) return tr('Subscribed');
    return willRenew ? trf('Subscribed, renews on {date}', d) : trf('Subscribed until {date} (cancelled)', d);
  }
}

/// How long a phone that was subscribed keeps working with no internet
/// after its paid-up date, since the store can't be asked offline.
const offlineGrace = Duration(days: 3);

enum Access { allowed, blocked }

/// [billingSetUp] is false in builds without store keys (development, or a
/// release before payments are configured): nothing is locked then.
/// [live] is the store's answer, or null when it couldn't be reached.
/// [lastPaidUntil] is the expiry remembered from the last good answer.
Access accessFor({
  required bool billingSetUp,
  required SubscriptionState? live,
  required DateTime? lastPaidUntil,
  required DateTime now,
}) {
  if (!billingSetUp) return Access.allowed;
  if (live != null) return live.active ? Access.allowed : Access.blocked;
  if (lastPaidUntil != null && now.isBefore(lastPaidUntil.add(offlineGrace))) return Access.allowed;
  return Access.blocked;
}

enum PlanPeriod { week, month, threeMonths, sixMonths, year }

enum TrialUnit { day, week, month, year }

/// A free trial's length, as the store set it up.
class FreeTrial {
  const FreeTrial(this.count, this.unit);

  final int count;
  final TrialUnit unit;

  /// "3 days", "1 week".
  String get length => switch (unit) {
        TrialUnit.day => count == 1 ? tr('1 day') : trf('{n} days', {'n': count}),
        TrialUnit.week => count == 1 ? tr('1 week') : trf('{n} weeks', {'n': count}),
        TrialUnit.month => count == 1 ? tr('1 month') : trf('{n} months', {'n': count}),
        TrialUnit.year => count == 1 ? tr('1 year') : trf('{n} years', {'n': count}),
      };

  /// "3-day", for "3-day free trial".
  String get adjective => currentLanguage == AppLanguage.en ? '$count-${unit.name}' : length;

  @override
  bool operator ==(Object other) => other is FreeTrial && other.count == count && other.unit == unit;

  @override
  int get hashCode => Object.hash(count, unit);
}

/// One plan as the paywall shows it.
class PlanOffer {
  const PlanOffer({
    required this.id,
    required this.period,
    required this.price,
    this.pricePerMonth,
    this.trial,
  });

  /// The store package this plan buys.
  final String id;
  final PlanPeriod period;

  /// The renewing price with its currency, as the store formats it: "₹499.00".
  final String price;

  /// For plans longer than a month, what that works out to each month.
  final String? pricePerMonth;

  /// Set only when this person can still start a free trial on this plan
  /// (Google and Apple give it once per account).
  final FreeTrial? trial;

  String get title => switch (period) {
        PlanPeriod.week => tr('Weekly'),
        PlanPeriod.month => tr('Monthly'),
        PlanPeriod.threeMonths => tr('Every 3 months'),
        PlanPeriod.sixMonths => tr('Every 6 months'),
        PlanPeriod.year => tr('Yearly'),
      };

  /// "₹499.00 a month", "₹1,299.00 every 3 months".
  String get priceLine => switch (period) {
        PlanPeriod.week => trf('{price} a week', {'price': price}),
        PlanPeriod.month => trf('{price} a month', {'price': price}),
        PlanPeriod.threeMonths => trf('{price} every 3 months', {'price': price}),
        PlanPeriod.sixMonths => trf('{price} every 6 months', {'price': price}),
        PlanPeriod.year => trf('{price} a year', {'price': price}),
      };

  String get _renews => switch (period) {
        PlanPeriod.week => tr('every week'),
        PlanPeriod.month => tr('every month'),
        PlanPeriod.threeMonths => tr('every 3 months'),
        PlanPeriod.sixMonths => tr('every 6 months'),
        PlanPeriod.year => tr('every year'),
      };

  /// What buying this plan means, in full, under the button. Both stores
  /// ask for the price, the renewal, when the trial turns into a payment,
  /// and how to cancel.
  /// [store] is who charges ("Google Play", "Apple"); [cancelIn] is where
  /// people cancel ("Google Play › Subscriptions").
  String disclosure({required String store, required String cancelIn}) {
    if (trial != null) {
      return trf(
          '{length} free, then {price}. {store} charges you when the trial ends unless you cancel at '
          'least 24 hours before. It renews {renews} until you cancel in {cancelIn}.',
          {'length': trial!.length, 'price': priceLine, 'store': store, 'renews': _renews, 'cancelIn': cancelIn});
    }
    return trf(
        '{price}, charged by {store} today. It renews {renews} until you cancel in {cancelIn}, at least '
        '24 hours before the next payment.',
        {'price': priceLine, 'store': store, 'renews': _renews, 'cancelIn': cancelIn});
  }

  String get buttonLabel => trial != null
      ? trf('Start {length} free trial', {'length': trial!.adjective})
      : trf('Subscribe for {price}', {'price': priceLine});
}

/// The trial a paywall headline should promise, if any plan has one.
FreeTrial? bestTrial(List<PlanOffer> plans) {
  FreeTrial? best;
  for (final p in plans) {
    final t = p.trial;
    if (t != null && (best == null || _days(t) > _days(best))) best = t;
  }
  return best;
}

int _days(FreeTrial t) => switch (t.unit) {
      TrialUnit.day => t.count,
      TrialUnit.week => t.count * 7,
      TrialUnit.month => t.count * 30,
      TrialUnit.year => t.count * 365,
    };

/// The plan selected when the paywall opens: the monthly one if there is
/// one (the plan most people pick), else the first.
PlanOffer? defaultPlan(List<PlanOffer> plans) {
  if (plans.isEmpty) return null;
  for (final p in plans) {
    if (p.period == PlanPeriod.month) return p;
  }
  return plans.first;
}
