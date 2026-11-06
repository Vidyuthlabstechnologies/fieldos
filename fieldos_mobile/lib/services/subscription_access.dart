/// Whether this phone may use FieldOS right now, and the plans in plain
/// words. Pure logic, kept apart from the store SDK so it can be tested.
///
/// Pricing: everyone pays. Each person starts with the store's 3-day free
/// trial (set up on the subscription in Play Console / App Store Connect,
/// so Google and Apple decide who is eligible and charge when it ends),
/// then the subscription renews until cancelled.
library;

import 'package:fieldos_mobile/core/format.dart';

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
    if (!active) return 'No active subscription';
    final date = expiresAt == null ? null : fmtDate(expiresAt!);
    if (complimentary) {
      return date == null ? 'Free access from the FieldOS team' : 'Free access from the FieldOS team until $date';
    }
    if (billingIssue) {
      return 'Payment problem: update your payment method in the store${date == null ? '' : ' before $date'}';
    }
    if (inTrial) {
      if (date == null) return willRenew ? 'Free trial, then paid' : 'Free trial (will not renew)';
      return willRenew ? 'Free trial until $date, then paid' : 'Free trial until $date (will not renew)';
    }
    if (date == null) return 'Subscribed';
    return willRenew ? 'Subscribed, renews on $date' : 'Subscribed until $date (cancelled)';
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
  String get length => '$count ${unit.name}${count == 1 ? '' : 's'}';

  /// "3-day", for "3-day free trial".
  String get adjective => '$count-${unit.name}';

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
        PlanPeriod.week => 'Weekly',
        PlanPeriod.month => 'Monthly',
        PlanPeriod.threeMonths => 'Every 3 months',
        PlanPeriod.sixMonths => 'Every 6 months',
        PlanPeriod.year => 'Yearly',
      };

  /// "₹499.00 a month", "₹1,299.00 every 3 months".
  String get priceLine => switch (period) {
        PlanPeriod.week => '$price a week',
        PlanPeriod.month => '$price a month',
        PlanPeriod.threeMonths => '$price every 3 months',
        PlanPeriod.sixMonths => '$price every 6 months',
        PlanPeriod.year => '$price a year',
      };

  String get _renews => switch (period) {
        PlanPeriod.week => 'every week',
        PlanPeriod.month => 'every month',
        PlanPeriod.threeMonths => 'every 3 months',
        PlanPeriod.sixMonths => 'every 6 months',
        PlanPeriod.year => 'every year',
      };

  /// What buying this plan means, in full, under the button. Both stores
  /// ask for the price, the renewal, when the trial turns into a payment,
  /// and how to cancel.
  /// [store] is who charges ("Google Play", "Apple"); [cancelIn] is where
  /// people cancel ("Google Play › Subscriptions").
  String disclosure({required String store, required String cancelIn}) {
    if (trial != null) {
      return '${trial!.length} free, then $priceLine. $store charges you when the trial ends unless you cancel at '
          'least 24 hours before. It renews $_renews until you cancel in $cancelIn.';
    }
    return '$priceLine, charged by $store today. It renews $_renews until you cancel in $cancelIn, at least '
        '24 hours before the next payment.';
  }

  String get buttonLabel => trial != null ? 'Start ${trial!.adjective} free trial' : 'Subscribe for $priceLine';
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
