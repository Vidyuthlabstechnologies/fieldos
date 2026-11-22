/// First run, from a new builder's side: Google first on a new phone,
/// company setup before any paywall (so an invited engineer joins first),
/// the "Get your first site running" checklist on Home, the trial notice
/// and the invite message a team actually receives.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/app.dart';
import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/onboarding/get_started.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/subscription/paywall_screen.dart';
import 'package:fieldos_mobile/features/subscription/trial_notice.dart';
import 'package:fieldos_mobile/features/team/invite_team.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

import 'paywall_screen_test.dart' show FakeBilling, FakeCompanyPlans;

class _Google implements GoogleAccountPicker {
  @override
  bool get available => true;
  @override
  Future<GoogleIdentityResult?> pick() async => null;
  @override
  Future<void> signOut() async {}
}

Override _quietCloud() => cloudSyncClientProvider.overrideWith((ref) {
      final c = SupabaseClient('http://localhost:1', 'anon',
          authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
      ref.onDispose(c.dispose);
      return c;
    });

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase)> boot(WidgetTester tester, Widget home,
      {List<Override> overrides = const [], Size size = const Size(412, 915), bool company = false, String? role}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db), _quietCloud(), ...overrides]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await db.settingsDao.set(languageSettingKey, 'en');
      if (company || role != null) {
        final session = container.read(sessionProvider.notifier);
        await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
        final c = await session.createCompany('Sri Sai Constructions');
        if (role != null) await session.setLocalRole(c.id, role);
      }
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await tester.pumpAndSettle();
    return (container, db);
  }

  /// Drift answers on real time; give Home's providers a few rounds.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
  }

  Future<String> addSite(WidgetTester tester, AppDatabase db, ProviderContainer c, String name) async {
    final companyId = c.read(sessionProvider).activeCompany!.id;
    await tester.runAsync(() => db.projectDao.create(ProjectsCompanion.insert(id: name, companyId: companyId, name: name)));
    return companyId;
  }

  group('login on a new phone', () {
    testWidgets('Google is the one big button; the username form waits behind a link', (tester) async {
      await boot(tester, const LoginScreen(), overrides: [googlePickerProvider.overrideWithValue(_Google())]);
      expect(find.widgetWithText(FilledButton, 'Continue with Google'), findsOneWidget);
      expect(find.text('Username'), findsNothing);
      expect(find.text('Password'), findsNothing);
      await tester.tap(find.byKey(const Key('login-use-password')));
      await tester.pumpAndSettle();
      expect(find.text('Username'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Continue with Google'), findsOneWidget,
          reason: 'beside the form, the form button leads');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a phone that already has an account opens on the username form', (tester) async {
      await boot(tester, const LoginScreen(), company: true, overrides: [googlePickerProvider.overrideWithValue(_Google())]);
      expect(find.byKey(const Key('login-use-password')), findsNothing);
      expect(find.text('Username'), findsOneWidget);
    });
  });

  testWidgets('an invited engineer sees company setup, not the paywall, before joining', (tester) async {
    await boot(tester, const App(), overrides: [
      billingServiceProvider.overrideWith((ref) => FakeBilling(ref.watch(appDatabaseProvider), offers: const [])),
      companyPlanServiceProvider.overrideWith((ref) => FakeCompanyPlans(ref.watch(appDatabaseProvider), const [])),
    ]);
    // Signed in, no company yet, no subscription.
    final container = ProviderScope.containerOf(tester.element(find.byType(App)));
    await tester.runAsync(() => container
        .read(sessionProvider.notifier)
        .register(username: 'meena', name: 'Meena', password: '123456'));
    await tester.pumpAndSettle();
    expect(container.read(billingServiceProvider).setUp, isTrue);
    expect(find.byType(CompanySetupScreen), findsOneWidget);
    expect(find.text('Join with a code'), findsOneWidget);
    expect(find.byType(PaywallScreen), findsNothing);

    // Naming a company leads on to the paywall (the trial), not round it.
    await tester.enterText(find.byType(TextField), 'Meena Builders');
    await tester.tap(find.text('Create company'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  group('Get your first site running', () {
    test('ticks itself off from what is on the phone; the sample site never counts', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final company = await db.companyDao.create('Sri Sai');
      Future<GetStartedProgress> load({bool cloud = true}) async => loadGetStarted(db,
          companyId: company.id, projects: await db.projectDao.forCompany(company.id), cloud: cloud);

      var p = await load();
      expect(p.doneCount, 0);
      expect(p.next, GetStartedStep.site);
      expect(p.steps.length, 4);
      expect((await load(cloud: false)).steps, isNot(contains(GetStartedStep.team)));

      final sample = await createSampleProject(db, companyId: company.id, userId: 'u1');
      p = await load();
      expect(p.done, isEmpty, reason: 'the sample has attendance and a report, but is not their site');
      expect(p.site, isNull);
      expect(sample.id, isNotEmpty);

      await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: company.id, name: 'Green Valley'));
      p = await load();
      expect(p.done, {GetStartedStep.site});
      expect(p.site?.id, 'p1');
      expect(p.next, GetStartedStep.attendance);

      await db.into(db.labourAttendance).insert(LabourAttendanceCompanion.insert(
          id: 'a1', projectId: 'p1', workerName: 'Raju', recordedBy: 'u1', punchIn: DateTime(2026, 11, 21, 9)));
      await db.into(db.dprEntries).insert(DprEntriesCompanion.insert(
          id: 'd1', projectId: 'p1', createdBy: 'u1', entryDate: DateTime(2026, 11, 21), workSummary: 'Slab shuttering'));
      p = await load();
      expect(p.next, GetStartedStep.team);
      await db.settingsDao.set(inviteSharedKey(company.id), '1');
      p = await load();
      expect(p.finished, isTrue);
      expect(p.hidden, isFalse);
    });

    testWidgets('on Home: progress, one tap to the right tab, and Hide stays hidden', (tester) async {
      final (container, db) = await boot(tester, const SizedBox(), company: true);
      await addSite(tester, db, container, 'Green Valley');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const HomeScreen()),
      ));
      await settle(tester);
      expect(find.text('Get your first site running'), findsOneWidget);
      expect(find.text('1 of 4 done · about 5 minutes'), findsOneWidget);
      expect(find.text('Who came to site today. Wages work out from it.'), findsOneWidget, reason: 'the next step says why');

      await tester.tap(find.byKey(const ValueKey('get-started-attendance')));
      await tester.pumpAndSettle();
      final detail = tester.widget<ProjectDetailScreen>(find.byType(ProjectDetailScreen));
      expect(detail.project.name, 'Green Valley');
      expect(detail.initialTab, 5, reason: 'Labour');
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('get-started-hide')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('get-started')), findsNothing);
      final companyId = container.read(sessionProvider).activeCompany!.id;
      expect(await tester.runAsync(() => db.settingsDao.get(getStartedHiddenKey(companyId))), '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a site engineer does not get the owner checklist', (tester) async {
      final (container, db) = await boot(tester, const SizedBox(), role: 'site_engineer');
      await addSite(tester, db, container, 'Green Valley');
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const HomeScreen()),
      ));
      await settle(tester);
      expect(find.byKey(const Key('get-started')), findsNothing);
    });

    testWidgets('fits a narrow phone at double text size, in Telugu', (tester) async {
      final (container, db) = await boot(tester, const SizedBox(), company: true, size: const Size(360, 1600));
      await addSite(tester, db, container, 'Green Valley');
      await tester.runAsync(() async {
        await db.settingsDao.set(languageSettingKey, 'te');
        await db.settingsDao.set(screensInLanguageKey, '1');
      });
      setCurrentLanguage(AppLanguage.te);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFieldOsTheme(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 1600), textScaler: TextScaler.linear(2)),
            child: const HomeScreen(),
          ),
        ),
      ));
      await settle(tester);
      // At double size the assistant and tour cards fill the first screen.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('get-started-team')), 300,
          scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)));
      await tester.pumpAndSettle();
      expect(find.text('మీ మొదటి సైట్‌ను మొదలుపెట్టండి'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('trial notice', () {
    test('days left count a part day as a day, then "today"', () {
      final now = DateTime(2026, 11, 21, 10);
      expect(trialDaysLeft(now.add(const Duration(days: 3)), now), 3);
      expect(trialDaysLeft(now.add(const Duration(days: 2, hours: 1)), now), 3);
      expect(trialDaysLeft(now.add(const Duration(hours: 5)), now), 1);
      expect(trialDaysLeft(now.add(const Duration(minutes: 30)), now), 0);
    });

    Future<void> pumpTrial(WidgetTester tester, SubscriptionState live) async {
      final now = DateTime(2026, 11, 21, 10);
      final db = AppDatabase.memory();
      final billing = FakeBilling(db, offers: const [])..live = live;
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        billingServiceProvider.overrideWithValue(billing),
      ]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: Scaffold(body: TrialNoticeCard(now: now))),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('a running trial says the days left and how to stop the charge', (tester) async {
      await pumpTrial(
          tester,
          SubscriptionState(
              active: true, inTrial: true, willRenew: true, expiresAt: DateTime(2026, 11, 23, 9)));
      expect(find.text('Free trial: 2 days left'), findsOneWidget);
      expect(find.textContaining('cancel in Google Play › Subscriptions before then'), findsOneWidget);
    });

    testWidgets('nothing once paid', (tester) async {
      await pumpTrial(tester, SubscriptionState(active: true, willRenew: true, expiresAt: DateTime(2026, 12, 21)));
      expect(find.byKey(const Key('trial-notice')), findsNothing);
    });

    testWidgets('nothing for free access from the FieldOS team', (tester) async {
      await pumpTrial(
          tester, SubscriptionState(active: true, inTrial: true, complimentary: true, expiresAt: DateTime(2026, 11, 22)));
      expect(find.byKey(const Key('trial-notice')), findsNothing);
    });
  });

  test('the invite has the steps, this country\'s store link and the code, in the owner\'s language', () {
    final en = joinCodeMessage(companyName: 'Sri Sai Constructions', code: 'K7Q2M9');
    expect(en, contains('Join Sri Sai Constructions on FieldOS'));
    expect(en, contains('https://play.google.com/store/apps/details?id=${currentMarket.appId}'));
    expect(en, contains('Tap "Join with a code" and enter K7Q2M9'));
    setCurrentLanguage(AppLanguage.hi);
    final hi = joinCodeMessage(companyName: null, code: 'K7Q2M9');
    expect(hi, contains('हमारी कंपनी'));
    expect(hi, contains('"${tr('Join with a code')}"'), reason: 'quotes the button the way it reads on their phone');
    expect(androidPackageName, currentMarket.appId);
  });

  test('every onboarding label is in all 13 languages', () {
    for (final lang in AppLanguage.values.where((l) => l != AppLanguage.en)) {
      setCurrentLanguage(lang);
      for (final key in [
        'Get your first site running',
        'Use a username and password instead',
        'Send the invite',
        'Free trial: {n} days left',
        '3. Tap "Join with a code" and enter {code}',
      ]) {
        expect(tr(key), isNot(key), reason: '${lang.name}: $key');
      }
    }
  });
}
