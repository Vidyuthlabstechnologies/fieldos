import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fieldos_mobile/services/billing_service.dart';

/// How store products become the plans on the paywall. A trial is promised
/// only when the store will really give it: Google lists only the offers an
/// account can still take; Apple always lists the trial and answers
/// eligibility separately.
void main() {
  const context = PresentedOfferingContext('default', null, null);

  PricingPhase phase(String iso, PeriodUnit unit, int value, String formatted, int micros) => PricingPhase(
        Period(unit, value, iso),
        RecurrenceMode.finiteRecurring,
        1,
        Price(formatted, micros, 'INR'),
        null,
      );

  Package androidMonthly({required bool withFreeTrial}) {
    final full = PricingPhase(
      const Period(PeriodUnit.month, 1, 'P1M'),
      RecurrenceMode.infiniteRecurring,
      null,
      const Price('₹499.00', 499000000, 'INR'),
      null,
    );
    final free = phase('P3D', PeriodUnit.day, 3, 'Free', 0);
    final option = SubscriptionOption(
      withFreeTrial ? 'monthly:trial' : 'monthly',
      'fieldos_pro:monthly',
      'fieldos_pro',
      withFreeTrial ? [free, full] : [full],
      const [],
      !withFreeTrial,
      const Period(PeriodUnit.month, 1, 'P1M'),
      false,
      full,
      withFreeTrial ? free : null,
      null,
      null,
      null,
    );
    return Package(
      '\$rc_monthly',
      PackageType.monthly,
      StoreProduct('fieldos_pro:monthly', 'FieldOS Pro', 'FieldOS Pro', 499, '₹499.00', 'INR',
          defaultOption: option, subscriptionPeriod: 'P1M', pricePerMonthString: '₹499.00'),
      context,
    );
  }

  Package iosYearly() => const Package(
        '\$rc_annual',
        PackageType.annual,
        StoreProduct('fieldos_pro_yearly', 'FieldOS Pro', 'FieldOS Pro', 4999, '₹4,999.00', 'INR',
            introductoryPrice: IntroductoryPrice(0, '₹0.00', 'P3D', 1, PeriodUnit.day, 3),
            subscriptionPeriod: 'P1Y',
            pricePerMonthString: '₹416.58'),
        context,
      );

  test('Android: the free phase Google lists is the trial', () {
    final plan = planFromPackage(androidMonthly(withFreeTrial: true), ios: false);
    expect(plan.id, '\$rc_monthly');
    expect(plan.period, PlanPeriod.month);
    expect(plan.price, '₹499.00');
    expect(plan.pricePerMonth, isNull);
    expect(plan.trial, const FreeTrial(3, TrialUnit.day));
  });

  test('Android: an account that already had the trial sees the plain price', () {
    final plan = planFromPackage(androidMonthly(withFreeTrial: false), ios: false);
    expect(plan.trial, isNull);
    expect(plan.buttonLabel, 'Subscribe for ₹499.00 a month');
  });

  test('iPhone: the trial counts only when Apple says this account is eligible', () {
    expect(
      planFromPackage(iosYearly(), ios: true, iosEligibility: IntroEligibilityStatus.introEligibilityStatusEligible).trial,
      const FreeTrial(3, TrialUnit.day),
    );
    for (final status in [
      IntroEligibilityStatus.introEligibilityStatusIneligible,
      IntroEligibilityStatus.introEligibilityStatusUnknown,
      null,
    ]) {
      expect(planFromPackage(iosYearly(), ios: true, iosEligibility: status).trial, isNull, reason: '$status');
    }
    final plan = planFromPackage(iosYearly(), ios: true);
    expect(plan.period, PlanPeriod.year);
    expect(plan.pricePerMonth, '₹416.58');
  });

  test('store errors become messages people can act on', () {
    final pending = billingErrorFor(PurchasesErrorCode.paymentPendingError, store: 'Google Play');
    expect(pending.pending, isTrue);
    expect(pending.message, contains('waiting for approval'));
    expect(billingErrorFor(PurchasesErrorCode.networkError, store: 'Google Play').message,
        'No internet connection. Connect and try again.');
    final other = billingErrorFor(PurchasesErrorCode.unknownError, store: 'Apple');
    expect(other.pending, isFalse);
    expect(other.message, startsWith('Apple could not complete that.'));
  });

  test('only a real network failure blames the internet when plans fail to load', () {
    expect(plansErrorFor(PurchasesErrorCode.networkError, store: 'Google Play').message,
        'No internet connection. Connect and try again.');
    final setup = plansErrorFor(PurchasesErrorCode.configurationError, store: 'Google Play').message;
    expect(setup, contains('not on sale in Google Play yet'));
    expect(setup, isNot(contains('internet')));
    expect(plansErrorFor(PurchasesErrorCode.unknownError, store: 'Google Play').message, isNot(contains('internet')));
  });
}
