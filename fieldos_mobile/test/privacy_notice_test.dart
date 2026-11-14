/// The short privacy notice reads in every language FieldOS speaks (DPDP
/// Act section 5(3)), and Settings › Your privacy holds every right and
/// takes back the AI assistant permission.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/legal/privacy_notice.dart';
import 'package:fieldos_mobile/features/legal/privacy_rights_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  test('every line of the notice is translated into every Indian language', () {
    for (final l in AppLanguage.values.where((l) => l != AppLanguage.en)) {
      final missing = privacyNoticeKeys.where((k) => trIn(l, k) == k).toList();
      expect(missing, isEmpty, reason: '${l.englishName} is missing $missing');
    }
  });

  test('the notice names who gets AI questions and where, and how to complain', () {
    final all = privacyNoticeKeys.join(' ');
    expect(all, contains('Anthropic in the USA'));
    expect(all, contains('Mumbai, India'));
    expect(all, contains('Grievance Officer'));
    expect(all, contains('Data Protection Board of India'));
  });

  testWidgets('Your privacy switches the notice language and withdraws the AI permission', (tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late String userId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
      userId = container.read(sessionProvider).user!.id;
      await setAiConsent(db, userId, true);
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const PrivacyRightsScreen()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Your account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('notice-lang-te')));
    await tester.pumpAndSettle();
    expect(find.text('మీ ఖాతా'), findsOneWidget);

    final toggle = find.byKey(const Key('privacy-ai-consent'));
    await tester.scrollUntilVisible(toggle, 200);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => aiConsentGiven(db, userId)), isFalse);

    await tester.scrollUntilVisible(find.text('Complain to the Grievance Officer'), 200);
    expect(find.text('Complain to the Grievance Officer'), findsOneWidget);
  });
}
