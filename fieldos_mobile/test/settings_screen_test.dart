import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/providers.dart';

/// Settings used to be owners-only ("Only a company owner can change
/// settings"), so a site engineer had no way to the privacy policy, the
/// voice language, support or their own password.
void main() {
  Future<ProviderContainer> pump(WidgetTester tester, {required bool owner}) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena Rao', password: '123456');
      final c = await session.createCompany('Sri Sai Constructions');
      if (!owner) await session.setLocalRole(c.id, 'site_engineer');
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const SettingsScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a site engineer gets the account, voice, help and legal settings',
      (tester) async {
    final container = await pump(tester, owner: false);
    expect(container.read(sessionProvider).role, Roles.member);
    expect(find.text('Meena Rao'), findsOneWidget);
    expect(find.text('Site engineer · Sri Sai Constructions'), findsOneWidget);
    for (final label in ['Change password', 'App lock', 'Language', 'Export all sites to Excel', 'Report a bug', 'Email support']) {
      await tester.scrollUntilVisible(find.text(label), 200);
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Sarvam fallback key'), findsNothing);
    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.scrollUntilVisible(find.text('Open-source licences'), 200);
    expect(find.text('Open-source licences'), findsOneWidget);
  });

  testWidgets('nobody is asked for a Sarvam or AI key, not even an owner', (tester) async {
    await pump(tester, owner: true);
    await tester.scrollUntilVisible(find.text('Open-source licences'), 200);
    expect(find.textContaining('Sarvam'), findsNothing);
    expect(find.textContaining('API key'), findsNothing);
  });

  testWidgets('the voice language can be chosen here', (tester) async {
    final container = await pump(tester, owner: false);
    await tester.scrollUntilVisible(find.text('Language'), 200);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Telugu'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => container.read(settingsServiceProvider).getVoiceLanguage());
    expect(saved, 'te-IN');
  });
}
