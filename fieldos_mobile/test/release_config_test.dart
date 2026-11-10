/// Store builds must carry the production cloud and billing (audit P0,
/// 2026-11-10): the app's own check, and the build script's refusal.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/release_config.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';
import 'package:fieldos_mobile/sync/sync_config.dart';

void main() {
  const prod = SyncConfig(url: 'https://abcd.supabase.co', anonKey: 'eyJhbGciOi.x.y');

  test('a complete store setup has no problems', () {
    expect(storeReleaseProblems(cloud: prod, billingKey: 'goog_abc'), isEmpty);
    expect(storeReleaseProblems(cloud: prod, billingKey: 'appl_abc'), isEmpty);
  });

  test('missing cloud, local cloud or missing billing are each reported', () {
    expect(storeReleaseProblems(cloud: const SyncConfig(url: '', anonKey: ''), billingKey: 'goog_abc'),
        [contains('Production Supabase project missing')]);
    expect(storeReleaseProblems(cloud: SyncConfig.localAndroidEmulator, billingKey: 'goog_abc'),
        [contains('not a production https address')]);
    expect(storeReleaseProblems(cloud: prod, billingKey: null), [contains('RevenueCat key')]);
    expect(storeReleaseProblems(cloud: prod, billingKey: 'sk_secret'), [contains('public store SDK key')]);
  });

  test('a development build (this test run) is not a store build and stays open without billing', () {
    expect(storeRelease, isFalse);
    expect(accessFor(billingSetUp: false, live: null, lastPaidUntil: null, now: DateTime(2026, 11, 10)), Access.allowed);
  });

  group('tool/android/build_store_release.sh refuses an incomplete store build', () {
    Future<ProcessResult> run(Map<String, String> env) => Process.run('bash', ['tool/android/build_store_release.sh'],
        environment: {'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin', 'PREFLIGHT_ONLY': '1', ...env},
        includeParentEnvironment: false);
    const good = {
      'SUPABASE_URL': 'https://abcd.supabase.co',
      // {"role":"anon"} as the JWT body.
      'SUPABASE_ANON_KEY': 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.sig',
      'REVENUECAT_ANDROID_KEY': 'goog_abc',
    };

    test('without the cloud project', () async {
      final r = await run({...good}..remove('SUPABASE_URL'));
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('SUPABASE_URL'));
    });
    test('without the RevenueCat key', () async {
      final r = await run({...good}..remove('REVENUECAT_ANDROID_KEY'));
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('REVENUECAT_ANDROID_KEY'));
    });
    test('pointed at a local stack', () async {
      final r = await run({...good, 'SUPABASE_URL': 'http://10.0.2.2:54321'});
      expect(r.exitCode, isNot(0));
    });
    test('with the service_role key', () async {
      final r = await run({...good, 'SUPABASE_ANON_KEY': localServiceRoleKey});
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('service_role'));
    });
    test('unsigned (no upload key on this machine)', () async {
      if (File('android/app/key.properties').existsSync()) return markTestSkipped('this machine has the upload key');
      final r = await run(good);
      expect(r.exitCode, isNot(0));
      expect(r.stderr, contains('key.properties'));
    });
  });
}
