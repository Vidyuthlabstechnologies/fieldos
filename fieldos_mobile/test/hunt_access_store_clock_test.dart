/// Hunt (access): the per-person store subscription offline. Its 3 days
/// past the paid-up date are measured on the phone's clock, so a clock set
/// back must not stretch them (company plans already guard this, see
/// company_plan_test.dart).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/billing_service.dart';

void main() {
  final paidUntil = DateTime.utc(2027, 1, 31, 12);

  group('accessFor offline with the latest time seen', () {
    test('a clock set back before the latest time seen counts from that time', () {
      // Really 10 days past the paid-up date; the clock is set back to a
      // day before it.
      final seen = paidUntil.add(const Duration(days: 10));
      expect(
          accessFor(
              billingSetUp: true,
              live: null,
              lastPaidUntil: paidUntil,
              latestSeen: seen,
              now: paidUntil.subtract(const Duration(days: 1))),
          Access.blocked);
    });

    test('a small clock correction is not a clock set back', () {
      final seen = paidUntil.add(const Duration(days: 2, hours: 23, minutes: 55));
      expect(
          accessFor(
              billingSetUp: true,
              live: null,
              lastPaidUntil: paidUntil,
              latestSeen: seen,
              now: seen.subtract(const Duration(minutes: 5))),
          Access.allowed);
    });

    test('the exact end of the 3 days is blocked; just before it is open', () {
      final end = paidUntil.add(offlineGrace);
      expect(
          accessFor(
              billingSetUp: true,
              live: null,
              lastPaidUntil: paidUntil,
              now: end.subtract(const Duration(milliseconds: 1))),
          Access.allowed);
      expect(accessFor(billingSetUp: true, live: null, lastPaidUntil: paidUntil, now: end), Access.blocked);
    });

    test('the store answer still wins over any clock', () {
      expect(
          accessFor(
              billingSetUp: true,
              live: const SubscriptionState(active: true),
              lastPaidUntil: paidUntil,
              latestSeen: paidUntil.add(const Duration(days: 300)),
              now: paidUntil),
          Access.allowed);
    });
  });

  group('BillingService keeps the latest time seen', () {
    late AppDatabase db;
    late BillingService billing;

    setUp(() {
      db = AppDatabase.memory();
      billing = BillingService(db, apiKey: null);
    });
    tearDown(() => db.close());

    test('moves forward only, so setting the clock back is noticed', () async {
      final t1 = DateTime.utc(2027, 2, 5, 9);
      expect(await billing.latestSeen(t1), t1);
      final back = DateTime.utc(2027, 1, 20);
      expect(await billing.latestSeen(back), t1);
      final later = DateTime.utc(2027, 2, 6);
      expect(await billing.latestSeen(later), later);
    });

    test('a phone that went offline after its last payment, clock set back, stays locked', () async {
      await db.settingsDao.set('subscription_paid_until', paidUntil.toIso8601String());
      // The phone opens 10 days after the paid-up date (blocked), then the
      // clock is set back to within the paid days.
      final real = paidUntil.add(const Duration(days: 10));
      expect(
          accessFor(
              billingSetUp: true,
              live: null,
              lastPaidUntil: await billing.lastPaidUntil(),
              latestSeen: await billing.latestSeen(real),
              now: real),
          Access.blocked);
      final setBack = paidUntil.subtract(const Duration(days: 1));
      expect(
          accessFor(
              billingSetUp: true,
              live: null,
              lastPaidUntil: await billing.lastPaidUntil(),
              latestSeen: await billing.latestSeen(setBack),
              now: setBack),
          Access.blocked);
    });
  });
}
