import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show PurchasesErrorCode;

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/subscription/paywall_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';

/// A store that answers from a script, so the paywall can be checked
/// without Google Play.
class FakeBilling extends BillingService {
  FakeBilling(super.db, {required this.offers});

  final List<PlanOffer> offers;
  Object? buyError;
  SubscriptionState? afterBuy = const SubscriptionState(active: true, inTrial: true);
  SubscriptionState restored = SubscriptionState.none;
  SubscriptionState? live = SubscriptionState.none;
  final bought = <String>[];

  @override
  bool get setUp => true;
  @override
  String get storeName => 'Google Play';
  @override
  String get cancelPath => 'Google Play › Subscriptions';
  @override
  Future<List<PlanOffer>> plans() async => offers;
  @override
  Future<SubscriptionState?> buy(String planId) async {
    bought.add(planId);
    if (buyError != null) throw buyError!;
    return afterBuy;
  }

  @override
  Future<SubscriptionState> restore() async => restored;
  @override
  Future<SubscriptionState?> current({bool fresh = false}) async => live;
}

void main() {
  const monthly = PlanOffer(id: 'm', period: PlanPeriod.month, price: '₹499.00', trial: FreeTrial(3, TrialUnit.day));
  const yearly = PlanOffer(id: 'y', period: PlanPeriod.year, price: '₹4,999.00', pricePerMonth: '₹416.58');

  Future<(FakeBilling, List<String>)> pump(
    WidgetTester tester, {
    List<PlanOffer> offers = const [monthly],
    Size size = const Size(412, 915),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final billing = FakeBilling(db, offers: offers);
    final unlocked = <String>[];
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      billingServiceProvider.overrideWithValue(billing),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(brightness),
        home: PaywallScreen(onUnlocked: () => unlocked.add('yes')),
      ),
    ));
    await tester.pumpAndSettle();
    return (billing, unlocked);
  }

  Future<void> tapBuy(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('paywall-buy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('paywall-buy')));
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(320, 568), Size(412, 915)]) {
    for (final brightness in Brightness.values) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()} ${brightness.name}', (tester) async {
        await pump(tester, offers: const [monthly, yearly], size: size, brightness: brightness);
        expect(find.text('Try it free for 3 days'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the trial is offered and starting it opens the app', (tester) async {
    final (billing, unlocked) = await pump(tester);
    expect(find.text('Start 3-day free trial'), findsOneWidget);
    expect(find.textContaining('3 days free, then ₹499.00 a month.'), findsOneWidget);
    await tapBuy(tester);
    expect(billing.bought, ['m']);
    expect(unlocked, ['yes']);
  });

  testWidgets('without a trial the price is on the button', (tester) async {
    await pump(tester, offers: const [yearly]);
    expect(find.text('Keep every site on track'), findsOneWidget);
    expect(find.text('Subscribe for ₹4,999.00 a year'), findsOneWidget);
    expect(find.text('Works out to ₹416.58 a month'), findsOneWidget);
  });

  testWidgets('a UPI payment waiting for approval is explained, and opens the app once approved', (tester) async {
    final (billing, unlocked) = await pump(tester);
    billing.buyError = billingErrorFor(PurchasesErrorCode.paymentPendingError, store: 'Google Play');
    await tapBuy(tester);
    expect(find.text('Payment waiting for approval'), findsOneWidget);
    expect(unlocked, isEmpty);

    // Not approved yet.
    await tester.ensureVisible(find.text('Check again'));
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Still waiting for the payment'), findsOneWidget);

    billing.live = const SubscriptionState(active: true);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(unlocked, ['yes']);
  });

  testWidgets('restore with nothing to restore says which account was checked', (tester) async {
    final (_, unlocked) = await pump(tester);
    await tester.ensureVisible(find.text('Restore purchase'));
    await tester.tap(find.text('Restore purchase'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No FieldOS subscription was found on this Google Play account'), findsOneWidget);
    expect(unlocked, isEmpty);
  });
}
