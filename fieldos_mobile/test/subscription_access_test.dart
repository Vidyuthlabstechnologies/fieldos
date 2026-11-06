import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/services/subscription_access.dart';

void main() {
  final now = DateTime.utc(2026, 11, 5, 12);

  test('nothing is locked when payments are not set up in the build', () {
    expect(accessFor(billingSetUp: false, live: SubscriptionState.none, lastPaidUntil: null, now: now), Access.allowed);
  });

  test('the store answer wins when it can be reached', () {
    const trial = SubscriptionState(active: true, inTrial: true);
    expect(accessFor(billingSetUp: true, live: trial, lastPaidUntil: null, now: now), Access.allowed);
    expect(
        accessFor(billingSetUp: true, live: SubscriptionState.none, lastPaidUntil: now.add(const Duration(days: 20)), now: now),
        Access.blocked,
        reason: 'cancelled or refunded: a remembered date must not keep it open');
  });

  test('offline: open until 3 days past the last paid-up date, never for a new install', () {
    expect(accessFor(billingSetUp: true, live: null, lastPaidUntil: null, now: now), Access.blocked);
    final paidUntil = now.subtract(const Duration(days: 2));
    expect(accessFor(billingSetUp: true, live: null, lastPaidUntil: paidUntil, now: now), Access.allowed);
    expect(accessFor(billingSetUp: true, live: null, lastPaidUntil: now.subtract(const Duration(days: 4)), now: now),
        Access.blocked);
  });

  test('describe', () {
    final d = DateTime(2026, 11, 8);
    expect(SubscriptionState(active: true, inTrial: true, expiresAt: d, willRenew: true).describe(),
        'Free trial until 8 Nov 2026, then paid');
    expect(SubscriptionState(active: true, expiresAt: d, willRenew: true).describe(), 'Subscribed, renews on 8 Nov 2026');
    expect(SubscriptionState(active: true, expiresAt: d).describe(), 'Subscribed until 8 Nov 2026 (cancelled)');
    expect(SubscriptionState(active: true, expiresAt: d, willRenew: true, billingIssue: true).describe(),
        'Payment problem: update your payment method in the store before 8 Nov 2026');
    expect(SubscriptionState.none.describe(), 'No active subscription');
  });

  group('plans in plain words', () {
    const monthlyTrial = PlanOffer(id: 'm', period: PlanPeriod.month, price: '₹499.00', trial: FreeTrial(3, TrialUnit.day));
    const monthly = PlanOffer(id: 'm', period: PlanPeriod.month, price: '₹499.00');
    const yearly = PlanOffer(id: 'y', period: PlanPeriod.year, price: '₹4,999.00', pricePerMonth: '₹416.58');

    test('the button and the small print say what happens and when', () {
      expect(monthlyTrial.buttonLabel, 'Start 3-day free trial');
      expect(monthly.buttonLabel, 'Subscribe for ₹499.00 a month');
      expect(
        monthlyTrial.disclosure(store: 'Google Play', cancelIn: 'Google Play › Subscriptions'),
        '3 days free, then ₹499.00 a month. Google Play charges you when the trial ends unless you cancel at least '
        '24 hours before. It renews every month until you cancel in Google Play › Subscriptions.',
      );
      expect(
        yearly.disclosure(store: 'Apple', cancelIn: 'Settings › your name › Subscriptions'),
        '₹4,999.00 a year, charged by Apple today. It renews every year until you cancel in Settings › your name › '
        'Subscriptions, at least 24 hours before the next payment.',
      );
    });

    test('the headline promises the longest trial on offer, and none when nobody can take one', () {
      const weekTrial = PlanOffer(id: 'y', period: PlanPeriod.year, price: '₹1', trial: FreeTrial(1, TrialUnit.week));
      expect(bestTrial([monthlyTrial, weekTrial]), const FreeTrial(1, TrialUnit.week));
      expect(bestTrial([monthly, yearly]), isNull);
      expect(const FreeTrial(1, TrialUnit.week).length, '1 week');
      expect(const FreeTrial(3, TrialUnit.day).length, '3 days');
    });

    test('the monthly plan is picked first', () {
      expect(defaultPlan([yearly, monthly])?.id, 'm');
      expect(defaultPlan([yearly])?.id, 'y');
      expect(defaultPlan(const []), isNull);
    });
  });
}
