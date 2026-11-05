/// The Team plan subscription, sold through Google Play and the App Store
/// via RevenueCat (one SDK for both stores, and it validates receipts so
/// this app needs no billing server of its own).
///
/// The subscription belongs to the COMPANY: the app logs in to RevenueCat
/// with the company id as the app user id, and RevenueCat's webhook tells
/// our server (supabase/functions/revenuecat-webhook), which is the only
/// thing allowed to change a company's plan. The app never decides it is
/// paid by itself; it reads the plan back with the company_plan RPC.
///
/// Keys come from --dart-define (REVENUECAT_ANDROID_KEY /
/// REVENUECAT_IOS_KEY, the PUBLIC SDK keys). Without them the upgrade
/// button is hidden and everything else works.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

export 'package:fieldos_mobile/sync/plan_status.dart';

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
  String? _loggedInAs;

  bool get available => BillingConfig.keyForThisDevice != null;

  Future<void> _useCompany(String companyId) async {
    final key = BillingConfig.keyForThisDevice;
    if (key == null) throw StateError('Billing is not set up in this build.');
    if (!await Purchases.isConfigured) {
      await Purchases.configure(PurchasesConfiguration(key)..appUserID = companyId);
    } else if (_loggedInAs != companyId) {
      await Purchases.logIn(companyId);
    }
    _loggedInAs = companyId;
  }

  /// The Team plan options (e.g. monthly, yearly) with store prices.
  Future<List<Package>> teamPackages(String companyId) async {
    await _useCompany(companyId);
    final offerings = await Purchases.getOfferings();
    return offerings.current?.availablePackages ?? const [];
  }

  /// Returns false if the person backed out of the store sheet.
  Future<bool> buy(String companyId, Package package) async {
    await _useCompany(companyId);
    try {
      await Purchases.purchase(PurchaseParams.package(package));
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  /// For a new phone, or after reinstalling: re-sends the store's
  /// existing subscription to RevenueCat, which re-notifies the server.
  Future<void> restore(String companyId) async {
    await _useCompany(companyId);
    await Purchases.restorePurchases();
  }
}
