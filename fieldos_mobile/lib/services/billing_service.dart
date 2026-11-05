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
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';

export 'package:fieldos_mobile/services/subscription_access.dart';

/// The RevenueCat entitlement every product unlocks.
const entitlementId = 'pro';

class BillingConfig {
  static const androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');
  static const iosKey = String.fromEnvironment('REVENUECAT_IOS_KEY');

  static String? get keyForThisDevice {
    if (Platform.isAndroid && androidKey.isNotEmpty) return androidKey;
    if (Platform.isIOS && iosKey.isNotEmpty) return iosKey;
    return null;
  }
}

class BillingService {
  BillingService(this.db);

  final AppDatabase db;
  static const _paidUntilKey = 'subscription_paid_until';

  bool get setUp => BillingConfig.keyForThisDevice != null;

  Future<void> _configure() async {
    final key = BillingConfig.keyForThisDevice;
    if (key == null) throw StateError('Payments are not set up in this build.');
    if (!await Purchases.isConfigured) {
      await Purchases.configure(PurchasesConfiguration(key));
    }
  }

  SubscriptionState _fromInfo(CustomerInfo info) {
    final e = info.entitlements.active[entitlementId];
    if (e == null || !e.isActive) return SubscriptionState.none;
    return SubscriptionState(
      active: true,
      inTrial: e.periodType == PeriodType.trial,
      expiresAt: e.expirationDate == null ? null : DateTime.tryParse(e.expirationDate!),
      willRenew: e.willRenew,
    );
  }

  Future<SubscriptionState> _remember(CustomerInfo info) async {
    final s = _fromInfo(info);
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
  Future<SubscriptionState?> current() async {
    try {
      await _configure();
      return await _remember(await Purchases.getCustomerInfo());
    } catch (_) {
      return null;
    }
  }

  /// Monthly / yearly options with the store's local prices.
  Future<List<Package>> packages() async {
    await _configure();
    final offerings = await Purchases.getOfferings();
    return offerings.current?.availablePackages ?? const [];
  }

  /// Returns null if the person backed out of the store sheet.
  Future<SubscriptionState?> buy(Package package) async {
    await _configure();
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return await _remember(result.customerInfo);
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return null;
      rethrow;
    }
  }

  /// For a new phone or a reinstall: finds the subscription already on
  /// this Google Play / Apple account.
  Future<SubscriptionState> restore() async {
    await _configure();
    return _remember(await Purchases.restorePurchases());
  }
}
