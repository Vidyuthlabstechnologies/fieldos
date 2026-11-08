/// Access codes: how Google's reviewers (and anyone else the FieldOS team
/// chooses) get past the paywall without paying. The real BillingService
/// runs against a stand-in for the RevenueCat SDK, so what is checked is
/// which customer each step lands on: a code only opens when the team
/// gave it Pro, a dead code puts the phone back on its own account, and a
/// purchase or restore never lands on a code that other people share.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/billing_service.dart';

/// RevenueCat as the app sees it: one phone, signed in to one Google
/// account, and the customers RevenueCat knows.
class FakeRevenueCat {
  String appUserId = r'$RCAnonymousID:phone';

  /// Customers the FieldOS team gave Pro in the RevenueCat dashboard.
  final promo = <String>{};

  /// Customers holding the Google Play subscription.
  final paying = <String>{};

  /// Whether the phone's Google account has bought FieldOS before.
  bool googleAccountPaid = false;

  bool offline = false;
  final calls = <String>[];

  static const _day = '2026-11-06T00:00:00Z';

  bool get anonymous => appUserId.startsWith(r'$RCAnonymousID:');

  Map<String, Object?> customer(String id) {
    final viaPromo = promo.contains(id);
    final viaPlay = paying.contains(id);
    final ent = <String, Object?>{
      if (viaPromo || viaPlay)
        'fieldos_pro': {
          'identifier': 'fieldos_pro',
          'isActive': true,
          'willRenew': viaPlay,
          'latestPurchaseDate': _day,
          'originalPurchaseDate': _day,
          'productIdentifier': viaPlay ? 'fieldos_pro:monthly' : 'rc_promo_pro_yearly',
          'isSandbox': false,
          'store': viaPlay ? 'PLAY_STORE' : 'PROMOTIONAL',
          'periodType': 'NORMAL',
          'ownershipType': 'PURCHASED',
          // Midday, so the date reads the same in every time zone.
          'expirationDate': viaPlay ? '2026-12-06T12:00:00Z' : '2027-11-06T12:00:00Z',
          'verification': 'NOT_REQUESTED',
        },
    };
    return {
      'entitlements': {'all': ent, 'active': ent, 'verification': 'NOT_REQUESTED'},
      'allPurchaseDates': <String, Object?>{},
      'activeSubscriptions': <Object?>[],
      'allPurchasedProductIdentifiers': <Object?>[],
      'nonSubscriptionTransactions': <Object?>[],
      'firstSeen': _day,
      'originalAppUserId': id,
      'allExpirationDates': <String, Object?>{},
      'requestDate': _day,
    };
  }

  static final _offering = {
    'identifier': 'default',
    'serverDescription': 'Default',
    'metadata': <String, Object>{},
    'availablePackages': [
      {
        'identifier': r'$rc_monthly',
        'packageType': 'MONTHLY',
        'product': {
          'identifier': 'fieldos_pro:monthly',
          'description': 'FieldOS Pro',
          'title': 'FieldOS Pro',
          'price': 499.0,
          'priceString': '₹499.00',
          'currencyCode': 'INR',
          'productCategory': 'SUBSCRIPTION',
          'subscriptionPeriod': 'P1M',
        },
        'presentedOfferingContext': {'offeringIdentifier': 'default'},
      },
    ],
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    if (offline && call.method != 'isConfigured' && call.method != 'getAppUserID') {
      throw PlatformException(code: '${PurchasesErrorCode.networkError.index}', message: 'offline');
    }
    switch (call.method) {
      case 'isConfigured':
        return true;
      case 'getAppUserID':
        return appUserId;
      case 'logIn':
        appUserId = (call.arguments as Map)['appUserID'] as String;
        return {'customerInfo': customer(appUserId), 'created': false};
      case 'logOut':
        // The real SDK refuses to log out a phone that is already anonymous.
        if (anonymous) throw PlatformException(code: '${PurchasesErrorCode.logOutWithAnonymousUserError.index}');
        appUserId = r'$RCAnonymousID:fresh';
        return customer(appUserId);
      case 'getOfferings':
        return {
          'all': {'default': _offering},
          'current': _offering,
        };
      case 'purchasePackage':
        googleAccountPaid = true;
        paying.add(appUserId);
        return {
          'customerInfo': customer(appUserId),
          'transaction': {
            'transactionIdentifier': 'GPA.1',
            'productIdentifier': 'fieldos_pro:monthly',
            'purchaseDate': _day,
          },
        };
      case 'restorePurchases':
        // RevenueCat moves the Google account's subscription to whoever restores.
        if (googleAccountPaid) {
          paying
            ..clear()
            ..add(appUserId);
        }
        return customer(appUserId);
      case 'getCustomerInfo':
        return customer(appUserId);
      case 'invalidateCustomerInfoCache':
        return null;
    }
    throw MissingPluginException(call.method);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  const code = 'access_K7Q2M9XR4TBZ';
  late FakeRevenueCat rc;
  late AppDatabase db;
  late BillingService billing;

  setUp(() {
    rc = FakeRevenueCat();
    db = AppDatabase.memory();
    billing = BillingService(db, apiKey: 'goog_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, rc.handle);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    await db.close();
  });

  test('a typed code is read the same however it is spaced or cased, and short or odd ones are refused', () {
    expect(accessCodeCustomerId('K7Q2M9XR4TBZ'), code);
    expect(accessCodeCustomerId(' k7q2-m9xr 4tbz '), code);
    expect(accessCodeCustomerId('K7Q2M9XR4'), isNull, reason: 'under 10 characters is too easy to guess');
    expect(accessCodeCustomerId(''), isNull);
    expect(accessCodeCustomerId('K7Q2M9XR4T/Z'), isNull);
    expect(accessCodeCustomerId(r'$RCAnonymousID:abcdef1234'), isNull, reason: 'never another customer');
    expect(accessCodeCustomerId('A' * 41), isNull);
  });

  test('access codes are offered on Android only, and only when payments are on', () {
    expect(billing.acceptsAccessCodes, isTrue);
    expect(BillingService(db).acceptsAccessCodes, isFalse, reason: 'no RevenueCat key in this build');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(billing.acceptsAccessCodes, isFalse, reason: 'Apple does not allow codes that unlock features');
  });

  test('a code the team gave Pro opens FieldOS, and is remembered for offline days', () async {
    rc.promo.add(code);
    final s = await billing.redeemAccessCode(' k7q2-m9xr 4tbz ');
    expect(s.active, isTrue);
    expect(s.complimentary, isTrue);
    expect(s.describe(), 'Free access from the FieldOS team until 6 Nov 2027');
    expect(rc.appUserId, code);
    expect(await billing.lastPaidUntil(), DateTime.utc(2027, 11, 6, 12));
    expect((await billing.current())?.active, isTrue, reason: 'still open the next time the app checks');
  });

  test('a mistyped code never reaches RevenueCat', () async {
    for (final typed in ['', 'abc', 'K7Q2M9XR4T!Z']) {
      await expectLater(
        billing.redeemAccessCode(typed),
        throwsA(isA<BillingException>().having((e) => e.message, 'message', contains('10 or more letters'))),
      );
    }
    expect(rc.calls, isNot(contains('logIn')));
  });

  test('a code that was never switched on, or has ended, puts the phone back on its own account', () async {
    await expectLater(
      billing.redeemAccessCode('ZZZZZZZZZZZZ'),
      throwsA(isA<BillingException>().having((e) => e.message, 'message', contains('not valid or has ended'))),
    );
    expect(rc.calls.where((c) => c == 'logIn' || c == 'logOut'), ['logIn', 'logOut']);
    expect(rc.anonymous, isTrue);
    expect(await billing.lastPaidUntil(), isNull);
  });

  test('no internet while checking a code says so', () async {
    rc.offline = true;
    await expectLater(
      billing.redeemAccessCode('K7Q2M9XR4TBZ'),
      throwsA(isA<BillingException>().having((e) => e.message, 'message', contains('No internet'))),
    );
  });

  test('a purchase after a code ended goes to the phone itself, never to the shared code', () async {
    rc.appUserId = code; // the team took the code's Pro away
    await billing.plans();
    final s = await billing.buy(r'$rc_monthly');
    expect(s?.active, isTrue);
    expect(rc.paying, isNot(contains(code)));
    expect(rc.paying.single, startsWith(r'$RCAnonymousID:'));
    expect(rc.calls.indexOf('logOut'), lessThan(rc.calls.indexOf('purchasePackage')));
  });

  test('restore after a code ended also leaves the code first', () async {
    rc
      ..googleAccountPaid = true
      ..appUserId = code;
    final s = await billing.restore();
    expect(s.active, isTrue);
    expect(rc.paying, isNot(contains(code)));
    expect(rc.anonymous, isTrue);
  });

  test('a phone that never used a code buys and restores as itself', () async {
    await billing.plans();
    expect((await billing.buy(r'$rc_monthly'))?.active, isTrue);
    expect((await billing.restore()).active, isTrue);
    expect(rc.calls, isNot(contains('logOut')));
    expect(rc.paying, {r'$RCAnonymousID:phone'});
  });

  test('a Google Play subscription is not mistaken for free access', () async {
    rc.paying.add(r'$RCAnonymousID:phone');
    final s = await billing.current();
    expect(s?.active, isTrue);
    expect(s?.complimentary, isFalse);
  });
}
