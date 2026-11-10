/// Whether this build is meant for the Play Store or App Store, and what a
/// store build must carry (audit P0, 2026-11-10).
///
/// A build without the production Supabase project or the RevenueCat key
/// used to come out looking fine: signed, installable, with cloud sync
/// quietly hidden and the paywall skipped (everything free). That is right
/// for a development build and wrong for a customer's phone. Store builds
/// are made with --dart-define=FIELDOS_STORE_RELEASE=true (release.yml,
/// tool/android/build_store_release.sh, tool/ios/build_ipa.sh), and those
/// scripts refuse to build without the values; if one still slips through,
/// the app shows a plain "this copy is broken" screen instead of running
/// unlocked or offline-only.
library;

import 'package:fieldos_mobile/sync/sync_config.dart';

const storeRelease = bool.fromEnvironment('FIELDOS_STORE_RELEASE');

/// What a store build is missing, in words for the person reading the
/// build log or a bug report. Empty when nothing is.
List<String> storeReleaseProblems({
  required SyncConfig cloud,
  required String? billingKey,
}) {
  final problems = <String>[];
  if (!cloud.isConfigured) {
    problems.add('Production Supabase project missing (SUPABASE_URL / SUPABASE_ANON_KEY)');
  } else {
    final url = Uri.tryParse(cloud.url);
    if (url == null || url.scheme != 'https' || url.host == '127.0.0.1' || url.host == '10.0.2.2' || url.host == 'localhost') {
      problems.add('SUPABASE_URL is not a production https address: ${cloud.url}');
    }
  }
  if (billingKey == null || billingKey.isEmpty) {
    problems.add('RevenueCat key for this platform missing (REVENUECAT_ANDROID_KEY / REVENUECAT_IOS_KEY)');
  } else if (!billingKey.startsWith('goog_') && !billingKey.startsWith('appl_')) {
    problems.add('RevenueCat key is not a public store SDK key (goog_... or appl_...)');
  }
  return problems;
}
