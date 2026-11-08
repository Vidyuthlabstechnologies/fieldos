/// The FieldOS subscription, sold through Google Play and the App Store via
/// RevenueCat (one SDK for both stores; it validates receipts, so the app
/// needs no billing server of its own).
///
/// Each person subscribes for themselves: RevenueCat ties the purchase to
/// the phone's Google Play / Apple account, so it follows the person to a
/// new phone with Restore. The 3-day free trial is an offer on the store
/// product, not something the app counts, so reinstalling can't reset it.
///
/// Keys come from --dart-define (REVENUECAT_ANDROID_KEY /
/// REVENUECAT_IOS_KEY, the PUBLIC SDK keys). Without them nothing is
/// locked, which is what development builds want.
///
/// Access codes (Android only) let people the FieldOS team chooses in
/// without paying, above all Google's app reviewers, who must be able to
/// see every feature. A code is a RevenueCat customer, `access_<CODE>`,
/// that the team gives the `fieldos_pro` entitlement as a promotional grant in the
/// RevenueCat dashboard; taking the grant away there switches the code
/// off. Codes are never sold: Google Play's billing rules cover anything
/// paid for. Apple does not allow codes that unlock features at all (App
/// Review Guideline 3.1.1); its reviewers test with sandbox purchases.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';

export 'package:fieldos_mobile/services/subscription_access.dart';

/// The RevenueCat entitlement every product unlocks.
const entitlementId = 'fieldos_pro';

/// The Android application id, for the Play subscriptions page.
const androidPackageName = 'com.mldynamic.fieldos';

/// What an access code becomes in RevenueCat. The prefix keeps typed codes
/// apart from real customers, so a code can only ever open a customer the
/// FieldOS team made for it.
const accessCodePrefix = 'access_';

/// The RevenueCat customer for a typed access code: capitals, with spaces
/// and dashes dropped, so "k7q2-m9xr 4tbz" and "K7Q2M9XR4TBZ" are the same
/// code. Null when it can't be a code: other characters, or too short to
/// be safe from guessing.
String? accessCodeCustomerId(String typed) {
  final code = typed.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^[A-Z0-9]{10,40}$').hasMatch(code)) return null;
  return '$accessCodePrefix$code';
}

class BillingConfig {
  static const androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  static String? get keyForThisDevice {
    if (Platform.isAndroid && androidKey.isNotEmpty) return androidKey;
    if (Platform.isIOS && iosKey.isNotEmpty) return iosKey;
    return null;
  }
}

/// A purchase or restore that did not go through, with a message for the
/// screen. [pending] means the store accepted the order but the payment
/// still needs approving (UPI and some cards in India): FieldOS opens by
/// itself once it is approved.
class BillingException implements Exception {
  BillingException(this.message, {this.pending = false});

  final String message;
  final bool pending;

  @override
  String toString() => message;
}

class BillingService {
  /// [apiKey] defaults to this build's RevenueCat key for this phone.
  BillingService(this.db, {String? apiKey}) : _apiKey = apiKey ?? BillingConfig.keyForThisDevice;

  final AppDatabase db;
  final String? _apiKey;
  static const _paidUntilKey = 'subscription_paid_until';

  /// The packages behind the plans last shown, by id.
  final Map<String, Package> _packages = {};

  bool get setUp => _apiKey != null;

  /// Whether the paywall offers "Enter access code" (Android only, see the
  /// library comment).
  bool get acceptsAccessCodes => setUp && defaultTargetPlatform == TargetPlatform.android;

  /// Who takes the money, as people call it on this phone.
  String get storeName => Platform.isIOS ? 'Apple' : 'Google Play';

  /// Where people cancel, in their words.
  String get cancelPath => Platform.isIOS ? 'Settings › your name › Subscriptions' : 'Google Play › Subscriptions';

  Future<void> _configure() async {
    final key = _apiKey;
    if (key == null) throw StateError('Payments are not set up in this build.');
    if (!await Purchases.isConfigured) {
      await Purchases.configure(PurchasesConfiguration(key));
    }
  }

  Future<SubscriptionState> _remember(CustomerInfo info) async {
    final s = stateFromCustomerInfo(info);
    // A subscription with no expiry (lifetime) is remembered as far ahead.
    final until = s.active ? (s.expiresAt ?? DateTime.now().add(const Duration(days: 3650))) : null;
    await db.settingsDao.set(_paidUntilKey, until?.toUtc().toIso8601String() ?? '');
    return s;
  }

  Future<DateTime?> lastPaidUntil() async {
    final raw = await db.settingsDao.get(_paidUntilKey);
    return raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  /// The store's current answer, or null if it can't be reached (offline).
  /// [fresh] skips RevenueCat's few-minute cache, for "check again" after a
  /// payment that was waiting for approval.
  Future<SubscriptionState?> current({bool fresh = false}) async {
    try {
      await _configure();
      if (fresh) await Purchases.invalidateCustomerInfoCache();
      return await _remember(await Purchases.getCustomerInfo());
    } catch (_) {
      return null;
    }
  }

  /// Calls [onChange] whenever the store reports a change, for example when
  /// a payment that was waiting for approval goes through. Returns the
  /// function that stops listening.
  Future<VoidCallback> listen(void Function(SubscriptionState state) onChange) async {
    await _configure();
    void listener(CustomerInfo info) => _remember(info).then(onChange);
    Purchases.addCustomerInfoUpdateListener(listener);
    return () => Purchases.removeCustomerInfoUpdateListener(listener);
  }

  /// The plans on sale, with the store's local prices and the free trial
  /// when this person can still take it.
  Future<List<PlanOffer>> plans() async {
    await _configure();
    final offerings = await Purchases.getOfferings();
    final packages = offerings.current?.availablePackages ?? const <Package>[];
    _packages
      ..clear()
      ..addEntries(packages.map((p) => MapEntry(p.identifier, p)));
    var eligibility = const <String, IntroEligibility>{};
    if (Platform.isIOS && packages.isNotEmpty) {
      try {
        eligibility = await Purchases.checkTrialOrIntroductoryPriceEligibility(
            [for (final p in packages) p.storeProduct.identifier]);
      } catch (_) {
        // Unknown eligibility shows the plain price, never a trial that
        // might not be given.
      }
    }
    return [
      for (final p in packages)
        planFromPackage(p, ios: Platform.isIOS, iosEligibility: eligibility[p.storeProduct.identifier]?.status),
    ];
  }

  /// Buys the plan [planId] from the last [plans]. Returns null if the
  /// person backed out of the store sheet; throws [BillingException].
  Future<SubscriptionState?> buy(String planId) async {
    await _configure();
    final package = _packages[planId];
    if (package == null) throw BillingException('That plan is no longer on sale. Please pick again.');
    try {
      await _leaveAccessCode();
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return await _remember(result.customerInfo);
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) return null;
      if (code == PurchasesErrorCode.productAlreadyPurchasedError) {
        // Bought before on this account (another phone, or a reinstall).
        final restored = await restore();
        if (restored.active) return restored;
      }
      throw billingErrorFor(code, store: storeName);
    }
  }

  /// For a new phone or a reinstall: finds the subscription already on
  /// this Google Play / Apple account.
  Future<SubscriptionState> restore() async {
    await _configure();
    try {
      await _leaveAccessCode();
      return await _remember(await Purchases.restorePurchases());
    } on PlatformException catch (e) {
      throw billingErrorFor(PurchasesErrorHelper.getErrorCode(e), store: storeName);
    }
  }

  /// Opens FieldOS with an access code from the FieldOS team. Throws
  /// [BillingException] for a mistyped code, or one that was never switched
  /// on or has ended; the phone is then back on its own store account.
  Future<SubscriptionState> redeemAccessCode(String typed) async {
    final customer = accessCodeCustomerId(typed);
    if (customer == null) {
      throw BillingException('Access codes are 10 or more letters and numbers. Type it exactly as you got it.');
    }
    await _configure();
    try {
      final s = await _remember((await Purchases.logIn(customer)).customerInfo);
      if (s.active) return s;
      await _remember(await Purchases.logOut());
    } on PlatformException catch (e) {
      throw billingErrorFor(PurchasesErrorHelper.getErrorCode(e), store: storeName);
    }
    throw BillingException(
        'That code is not valid or has ended. Check it and try again, or ask whoever gave it to you.');
  }

  /// Purchases and restores belong to this phone's own store account. A
  /// phone that last used an access code leaves it first, so a purchase
  /// can never land on a code that other people share.
  Future<void> _leaveAccessCode() async {
    if ((await Purchases.appUserID).startsWith(accessCodePrefix)) await Purchases.logOut();
  }

  /// The store page where this person can cancel or change the plan.
  Future<Uri> managementUrl() async {
    try {
      await _configure();
      final url = (await Purchases.getCustomerInfo()).managementURL;
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri != null) return uri;
    } catch (_) {
      // Fall through to the store's general page.
    }
    return Platform.isIOS
        ? Uri.parse('https://apps.apple.com/account/subscriptions')
        : Uri.parse('https://play.google.com/store/account/subscriptions?package=$androidPackageName');
  }
}

/// The subscription the store reports, in the app's terms.
SubscriptionState stateFromCustomerInfo(CustomerInfo info) {
  final e = info.entitlements.active[entitlementId];
  if (e == null || !e.isActive) return SubscriptionState.none;
  return SubscriptionState(
    active: true,
    inTrial: e.periodType == PeriodType.trial,
    expiresAt: e.expirationDate == null ? null : DateTime.tryParse(e.expirationDate!),
    willRenew: e.willRenew,
    billingIssue: e.billingIssueDetectedAt != null,
    complimentary: e.store == Store.promotional,
  );
}

/// One store package as the paywall describes it. On Android, Google Play
/// only lists the offers this account can still take, so a free phase on
/// the default option means the trial is really there. On iPhone the store
/// always lists the trial, so it counts only when Apple says [iosEligibility]
/// is eligible.
@visibleForTesting
PlanOffer planFromPackage(Package p, {required bool ios, IntroEligibilityStatus? iosEligibility}) {
  final product = p.storeProduct;
  final period = _planPeriod(p.packageType, product.subscriptionPeriod);
  FreeTrial? trial;
  if (ios) {
    final intro = product.introductoryPrice;
    if (intro != null && intro.price == 0 && iosEligibility == IntroEligibilityStatus.introEligibilityStatusEligible) {
      trial = _trial(intro.periodUnit, intro.periodNumberOfUnits * math.max(1, intro.cycles));
    }
  } else {
    final free = product.defaultOption?.freePhase?.billingPeriod;
    if (free != null) trial = _trial(free.unit, free.value);
  }
  final longerThanAMonth = period != PlanPeriod.month && period != PlanPeriod.week;
  return PlanOffer(
    id: p.identifier,
    period: period,
    price: product.priceString,
    pricePerMonth: longerThanAMonth ? product.pricePerMonthString : null,
    trial: trial,
  );
}

FreeTrial? _trial(PeriodUnit unit, int count) {
  if (count <= 0) return null;
  return switch (unit) {
    PeriodUnit.day => count % 7 == 0 ? FreeTrial(count ~/ 7, TrialUnit.week) : FreeTrial(count, TrialUnit.day),
    PeriodUnit.week => FreeTrial(count, TrialUnit.week),
    PeriodUnit.month => FreeTrial(count, TrialUnit.month),
    PeriodUnit.year => FreeTrial(count, TrialUnit.year),
    PeriodUnit.unknown => null,
  };
}

PlanPeriod _planPeriod(PackageType type, String? iso) {
  switch (type) {
    case PackageType.weekly:
      return PlanPeriod.week;
    case PackageType.monthly:
      return PlanPeriod.month;
    case PackageType.threeMonth:
      return PlanPeriod.threeMonths;
    case PackageType.sixMonth:
      return PlanPeriod.sixMonths;
    case PackageType.annual:
      return PlanPeriod.year;
    default:
      return switch (iso) {
        'P1W' || 'P7D' => PlanPeriod.week,
        'P3M' => PlanPeriod.threeMonths,
        'P6M' => PlanPeriod.sixMonths,
        'P1Y' || 'P12M' => PlanPeriod.year,
        _ => PlanPeriod.month,
      };
  }
}

/// A store error as a message people can act on.
@visibleForTesting
BillingException billingErrorFor(PurchasesErrorCode code, {required String store}) => switch (code) {
      PurchasesErrorCode.paymentPendingError => BillingException(
          'Your payment is waiting for approval, for example in your UPI app. FieldOS opens by itself once '
          '$store confirms it.',
          pending: true),
      PurchasesErrorCode.networkError || PurchasesErrorCode.offlineConnectionError =>
        BillingException('No internet connection. Connect and try again.'),
      PurchasesErrorCode.purchaseNotAllowedError => BillingException(
          'This phone is not allowed to make purchases. Check the payment settings or parental controls in $store.'),
      PurchasesErrorCode.productNotAvailableForPurchaseError =>
        BillingException('This plan is not on sale in your country right now.'),
      PurchasesErrorCode.storeProblemError =>
        BillingException('$store had a problem with that. Please try again in a minute.'),
      PurchasesErrorCode.operationAlreadyInProgressError =>
        BillingException('A purchase is already in progress. Wait for it to finish.'),
      PurchasesErrorCode.receiptAlreadyInUseError || PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
        BillingException('This $store account already pays for FieldOS for someone else. Write to us and we will '
            'sort it out.'),
      _ => BillingException('$store could not complete that. Please try again, or send a bug report from the menu.'),
    };
