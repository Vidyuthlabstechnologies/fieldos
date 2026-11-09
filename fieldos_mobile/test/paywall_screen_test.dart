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
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Company plans as the server would answer, with no network.
class FakeCompanyPlans extends CompanyPlanService {
  FakeCompanyPlans(AppDatabase db, this.plans) : super(db: db, cloud: null);

  List<CompanyPlan>? plans;

  @override
  Future<List<CompanyPlan>?> current() async {
    if (plans != null) await remember(plans!);
    return plans;
  }
}

/// A store that answers from a script, so the paywall can be checked
/// without Google Play.
class FakeBilling extends BillingService {
  FakeBilling(super.db, {required this.offers});

  final List<PlanOffer> offers;
  Object? plansError;
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
  Future<List<PlanOffer>> plans() async {
    if (plansError != null) throw plansError!;
    return offers;
  }
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
    Object? plansError,
    bool withCompany = false,
    Future<void> Function()? onCompanyLinked,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final billing = FakeBilling(db, offers: offers)
      ..codes = codes
      ..plansError = plansError;
    final unlocked = <String>[];
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      billingServiceProvider.overrideWithValue(billing),
      companyPlanServiceProvider.overrideWithValue(FakeCompanyPlans(db, const [])),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    if (withCompany) {
      await tester.runAsync(() async {
        final session = container.read(sessionProvider.notifier);
        await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
        await session.createCompany('Sri Sai Constructions');
      });
    }
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(brightness),
        home: PaywallScreen(onUnlocked: () => unlocked.add('yes'), onCompanyLinked: onCompanyLinked),
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

  // Onsite's most-liked review: "either pay 35k a year or we delete your
  // data". Here the paywall promises the opposite and the export is on it.
  testWidgets('the paywall says records are kept and offers the Excel export', (tester) async {
    await pump(tester, withCompany: true);
    await tester.ensureVisible(find.byKey(const Key('paywall-your-data')));
    expect(find.text('Your records stay yours'), findsOneWidget);
    expect(find.textContaining('never deleted when a plan ends'), findsOneWidget);
    expect(find.byKey(const Key('paywall-export')), findsOneWidget);
  });

  testWidgets('before a company exists there is nothing to export, so no card', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('paywall-your-data')), findsNothing);
  });

  testWidgets('plans that are not on sale yet are not blamed on the internet', (tester) async {
    await pump(tester, plansError: plansErrorFor(PurchasesErrorCode.configurationError, store: 'Google Play'));
    expect(find.textContaining('not on sale in Google Play yet'), findsOneWidget);
    expect(find.textContaining('internet'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
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
      companyPlanServiceProvider.overrideWithValue(FakeCompanyPlans(db, const [])),
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

  // Store rules: a company plan is sold by invoice, so the app may let its
  // people in but never show its price or a way to buy it.
  testWidgets('people on a company plan can sign in to it; no price or purchase link for it', (tester) async {
    await pump(tester, onCompanyLinked: () async {});
    final card = find.byKey(const Key('paywall-company-plan'));
    await tester.ensureVisible(card);
    expect(find.descendant(of: card, matching: find.text('Your company has a FieldOS plan?')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('Sign in to my company')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.textContaining('₹')), findsNothing);
    expect(find.descendant(of: card, matching: find.textContaining('http')), findsNothing);
    expect(find.descendant(of: card, matching: find.textContaining('lakh')), findsNothing);
  });

  testWidgets('no company plan card where the gate cannot check one', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('paywall-company-plan')), findsNothing);
  });

  testWidgets('My subscription: a company plan shows its sites and needs no store subscription', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final billing = FakeBilling(db, offers: const [monthly]);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      billingServiceProvider.overrideWithValue(billing),
      companyPlanServiceProvider.overrideWithValue(FakeCompanyPlans(db, [
        CompanyPlan(
            companyId: null, plan: 'site_pro', siteLimit: 3, endsOn: DateTime(2027, 3, 31), companyName: null),
      ])),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: const Scaffold(body: MySubscriptionSheet()),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('FieldOS Site Pro'), findsOneWidget);
    expect(find.textContaining('Everyone in the company is included. Up to 3 active sites.'), findsOneWidget);
    expect(find.text('0 of 3 active sites in use'), findsOneWidget);
    expect(find.textContaining('do not need a subscription of your own'), findsOneWidget);
    expect(find.text('Manage or cancel'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
  });
}
