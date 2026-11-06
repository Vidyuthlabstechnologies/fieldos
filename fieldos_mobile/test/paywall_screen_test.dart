import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show PurchasesErrorCode;

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
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
  bool codes = true;
  final redeemed = <String>[];

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
  @override
  bool get acceptsAccessCodes => codes;
  @override
  Future<SubscriptionState> redeemAccessCode(String typed) async {
    redeemed.add(typed);
    if (accessCodeCustomerId(typed) == 'access_K7Q2M9XR4TBZ') {
      return SubscriptionState(active: true, complimentary: true, expiresAt: DateTime(2027, 11, 6));
    }
    throw BillingException('That code is not valid or has ended. Check it and try again, or ask whoever gave it to you.');
  }
}

void main() {
  const monthly = PlanOffer(id: 'm', period: PlanPeriod.month, price: '₹499.00', trial: FreeTrial(3, TrialUnit.day));
  const yearly = PlanOffer(id: 'y', period: PlanPeriod.year, price: '₹4,999.00', pricePerMonth: '₹416.58');

  Future<(FakeBilling, List<String>)> pump(
    WidgetTester tester, {
    List<PlanOffer> offers = const [monthly],
    Size size = const Size(412, 915),
    Brightness brightness = Brightness.light,
    bool codes = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final billing = FakeBilling(db, offers: offers)..codes = codes;
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

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  testWidgets('an access code from the FieldOS team opens the app; a wrong one says so and keeps the dialog',
      (tester) async {
    final (billing, unlocked) = await pump(tester, size: const Size(320, 568));
    await openMenu(tester);
    await tester.tap(find.text('Enter access code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('such as app reviewers'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('access-code')), 'ZZZZ-ZZZZ-ZZZZ');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not valid or has ended'), findsOneWidget);
    expect(unlocked, isEmpty);

    await tester.enterText(find.byKey(const Key('access-code')), 'k7q2-m9xr-4tbz');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(billing.redeemed, ['ZZZZ-ZZZZ-ZZZZ', 'k7q2-m9xr-4tbz']);
    expect(find.text('Enter access code'), findsNothing, reason: 'the dialog closed');
    expect(unlocked, ['yes']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling the access code leaves the paywall as it was', (tester) async {
    final (billing, unlocked) = await pump(tester);
    await openMenu(tester);
    await tester.tap(find.text('Enter access code'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(billing.redeemed, isEmpty);
    expect(unlocked, isEmpty);
    expect(find.text('Start 3-day free trial'), findsOneWidget);
  });

  testWidgets('no access code where the store does not take them (iPhone)', (tester) async {
    await pump(tester, codes: false);
    await openMenu(tester);
    expect(find.text('Email support'), findsOneWidget);
    expect(find.text('Enter access code'), findsNothing);
  });

  testWidgets('My subscription: free access from the team has nothing to manage, cancel or restore', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final billing = FakeBilling(db, offers: const [monthly])
      ..live = SubscriptionState(active: true, complimentary: true, expiresAt: DateTime(2027, 11, 6));
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      billingServiceProvider.overrideWithValue(billing),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    Future<void> showSheet() async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFieldOsTheme(Brightness.light),
          home: const Scaffold(body: MySubscriptionSheet()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await showSheet();
    expect(find.text('Free access from the FieldOS team until 6 Nov 2027'), findsOneWidget);
    expect(find.textContaining('nothing to pay or cancel'), findsOneWidget);
    expect(find.text('Manage or cancel'), findsNothing);
    expect(find.text('Restore purchase'), findsNothing);

    billing.live = SubscriptionState(active: true, expiresAt: DateTime(2026, 12, 6), willRenew: true);
    await tester.pumpWidget(const SizedBox());
    await showSheet();
    expect(find.text('Subscribed, renews on 6 Dec 2026'), findsOneWidget);
    expect(find.text('Manage or cancel'), findsOneWidget);
    expect(find.text('Restore purchase'), findsOneWidget);
  });
}
