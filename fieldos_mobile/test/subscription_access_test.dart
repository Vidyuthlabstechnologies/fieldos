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
        'Free trial until 08/11/2026, then paid');
    expect(SubscriptionState(active: true, expiresAt: d, willRenew: true).describe(), 'Subscribed, renews on 08/11/2026');
    expect(SubscriptionState.none.describe(), 'No active subscription');
  });
}
