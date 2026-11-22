/// Settings > API keys on a small phone in Hindi: the owner makes a key and
/// sees it once, the list shows its prefix and whether it can write, changes
/// made through keys are listed, and revoking asks first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/features/settings/api_keys_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class _FakeKeys implements ApiKeysService {
  @override
  SupabaseClient get client => throw UnimplementedError();
  final keys = <ApiKey>[];
  final plain = 'fos_${'ab' * 24}';

  @override
  Future<List<ApiKey>> list(String companyId) async => [...keys];

  @override
  Future<String> create(String companyId, String name, {bool write = false}) async {
    keys.add(ApiKey(id: 'k${keys.length}', name: name, prefix: plain.substring(0, 12), createdAt: DateTime(2026, 11, 14), canWrite: write));
    return plain;
  }

  final changes = <ApiChange>[];

  @override
  Future<List<ApiChange>> recentChanges(String companyId) async => [...changes];

  @override
  Future<void> revoke(String keyId) async {
    final i = keys.indexWhere((k) => k.id == keyId);
    final k = keys[i];
    keys[i] = ApiKey(id: k.id, name: k.name, prefix: k.prefix, createdAt: k.createdAt, revokedAt: DateTime(2026, 11, 15));
  }
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  testWidgets('the owner makes a key, sees it once, and revokes it (Hindi, small phone)', (tester) async {
    final fake = _FakeKeys();
    setCurrentLanguage(AppLanguage.hi);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [apiKeysServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        locale: AppLanguage.hi.locale,
        supportedLocales: [for (final l in AppLanguage.offered) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const ApiKeysScreen(companyId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(tr('No keys yet')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('api-key-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('api-key-name')), 'Tally connector');
    await tester.tap(find.byKey(const Key('api-key-write')));
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'the switch fits a 320 px dialog');
    await tester.tap(find.byKey(const Key('api-key-create')));
    await tester.pumpAndSettle();
    expect(find.text(fake.plain), findsOneWidget, reason: 'shown once');
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('api-key-done')));
    await tester.pumpAndSettle();
    expect(find.text(fake.plain), findsNothing);
    expect(find.textContaining('fos_abababab'), findsOneWidget);
    expect(find.text('Tally connector'), findsOneWidget);
    expect(fake.keys.single.canWrite, isTrue);
    expect(find.textContaining(tr('reads and writes')), findsOneWidget);

    await tester.tap(find.byKey(const Key('api-key-revoke-k0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-key-revoke-confirm')));
    await tester.pumpAndSettle();
    expect(fake.keys.single.revokedAt, isNotNull);
    expect(find.byKey(const Key('api-key-revoke-k0')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changes made through keys are listed for the owner', (tester) async {
    final fake = _FakeKeys()
      ..changes.add(ApiChange(keyName: 'Zapier', action: 'create', resource: 'tasks', at: DateTime(2026, 11, 21, 10)));
    await tester.pumpWidget(ProviderScope(
      overrides: [apiKeysServiceProvider.overrideWithValue(fake)],
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const ApiKeysScreen(companyId: 'c1')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Zapier added a task'), findsOneWidget);
  });
}
