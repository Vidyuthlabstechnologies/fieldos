/// Hunt (access): a store build's RevenueCat key must be this platform's
/// (goog_ on Android, appl_ on iPhone). The other store's key configures,
/// then every plan fails to load, so no one can start the trial.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/release_config.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';

void main() {
  const prod = SyncConfig(url: 'https://abcd.supabase.co', anonKey: 'eyJhbGciOi.x.y');

  test("an iPhone build with Google's key is reported", () {
    expect(storeReleaseProblems(cloud: prod, billingKey: 'goog_abc', ios: true), [contains('appl_')]);
  });

  test("an Android build with Apple's key is reported", () {
    expect(storeReleaseProblems(cloud: prod, billingKey: 'appl_abc', ios: false), [contains('goog_')]);
  });

  test("each platform's own key is fine", () {
    expect(storeReleaseProblems(cloud: prod, billingKey: 'appl_abc', ios: true), isEmpty);
    expect(storeReleaseProblems(cloud: prod, billingKey: 'goog_abc', ios: false), isEmpty);
  });
}
