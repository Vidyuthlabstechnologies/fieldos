/// The main screens in Hindi and Telugu on a small phone: labels are
/// longer than English, so this catches overflow and checks the screen
/// really switched language.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/features/estimation/estimation_screen.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase)> signedIn(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // Never signed in to the cloud here; no token-refresh timer either.
        cloudSyncClientProvider.overrideWith((ref) {
          final c = SupabaseClient(
            'http://localhost:1',
            'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit),
          );
          ref.onDispose(c.dispose);
          return c;
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
    });
    return (container, db);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, AppLanguage lang, Widget home) async {
    // Saved the way the picker saves it, so the language controller loads it.
    await tester.runAsync(() => container.read(appDatabaseProvider).settingsDao.set(languageSettingKey, lang.code));
    setCurrentLanguage(lang);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFieldOsTheme(Brightness.light),
          locale: lang.locale,
          supportedLocales: [for (final l in AppLanguage.values) l.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: home,
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('picking Telugu in Settings switches the open screen and is remembered', (tester) async {
    final (container, db) = await signedIn(tester);
    await pump(tester, container, AppLanguage.en, const SettingsScreen());
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.text('App language').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('తెలుగు'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('సెట్టింగ్‌లు'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
    expect(await tester.runAsync(() => db.settingsDao.get(languageSettingKey)), 'te');
  });

  for (final lang in [AppLanguage.hi, AppLanguage.te]) {
    group(lang.englishName, () {
      testWidgets('sign-in screen', (tester) async {
        final db = AppDatabase.memory();
        final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
        addTearDown(() async {
          container.dispose();
          await db.close();
        });
        await pump(tester, container, lang, const LoginScreen());
        expect(tester.takeException(), isNull);
        expect(find.text(tr('Password')), findsWidgets);
        expect(tr('Password'), isNot('Password'));
        // The three language buttons are there in their own scripts.
        for (final l in AppLanguage.values) {
          expect(find.text(l.nativeName), findsOneWidget);
        }
      });

      testWidgets('home with no projects', (tester) async {
        final (container, _) = await signedIn(tester);
        await pump(tester, container, lang, const HomeScreen());
        expect(tester.takeException(), isNull);
        expect(find.text(tr('Start your first project')), findsOneWidget);
      });

      testWidgets('settings', (tester) async {
        final (container, _) = await signedIn(tester);
        await pump(tester, container, lang, const SettingsScreen());
        expect(tester.takeException(), isNull);
        expect(find.text(tr('App language')), findsWidgets);
        expect(find.text(lang.nativeName), findsOneWidget);
      });

      testWidgets('a project, its tabs and its empty reports', (tester) async {
        final (container, db) = await signedIn(tester);
        late Project project;
        await tester.runAsync(() async {
          final companyId = container.read(sessionProvider).activeCompany!.id;
          project = await db.projectDao.create(
            ProjectsCompanion.insert(id: 'p', companyId: companyId, name: 'Tower B'),
          );
        });
        await pump(tester, container, lang, ProjectDetailScreen(project: project));
        expect(tester.takeException(), isNull);
        expect(find.text(tr('DPR')), findsWidgets);
        expect(find.text(tr('Tasks')), findsWidgets);
      });

      testWidgets('estimation, which used to stay in English', (tester) async {
        final (container, _) = await signedIn(tester);
        await pump(tester, container, lang, const Scaffold(body: EstimationView(projectId: 'p', userId: 'u')));
        expect(tester.takeException(), isNull);
        expect(find.text(tr('Estimations')), findsOneWidget);
        expect(find.text(tr('No estimations yet.')), findsOneWidget);
        expect(tr('No estimations yet.'), isNot('No estimations yet.'));
        await tester.tap(find.byTooltip(tr('Add')));
        await tester.pumpAndSettle();
        expect(find.text(tr('New estimation')), findsOneWidget);
        expect(find.text(tr('Contractor profit % (optional)')), findsOneWidget);
      });
    });
  }
}
