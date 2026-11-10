/// The 1.7 bug hunt rendered every screen in all six languages on a small
/// phone (320 x 640), with large text and Android's 3-button bar, and found
/// screens whose own layout broke. These are those screens, so they stay
/// fixed:
/// - the app tour squeezed the live screen above its card until it broke;
/// - the Workers tab pushed "Add worker" off the right edge in Tamil;
/// - the Wage sheet pushed the next-week arrow off the edge;
/// - the Money tab's three totals ran into each other with large text;
/// - in Tamil and Telugu the tour also broke the Issues list ("Mark fixed"
///   took the whole row), the Dashboard card's status pill, Home's status
///   notes and the Money list in a short space.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/branded_page.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, Project)> sample(WidgetTester tester, AppLanguage lang) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = SupabaseClient('http://localhost:1', 'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
        ref.onDispose(c.dispose);
        return c;
      }),
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late Project project;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ramesh', name: 'Ramesh Rao', password: '123456');
      final company = await session.createCompany('Sri Sai Constructions');
      project = await createSampleProject(db, companyId: company.id, userId: container.read(sessionProvider).user!.id);
      await db.settingsDao.set(tourSeenKey, '1');
      await db.settingsDao.set(languageSettingKey, lang.code);
    });
    setCurrentLanguage(lang);
    return (container, project);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, AppLanguage lang, Widget screen,
      {Size size = const Size(320, 640), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    // Status bar on top, Android's 3-button bar (48 dp) at the bottom.
    const insets = FakeViewPadding(top: 24, bottom: 48);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        locale: lang.locale,
        supportedLocales: [for (final l in AppLanguage.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: screen,
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  /// [finder]'s widget is fully inside the screen's width.
  void onScreen(WidgetTester tester, Finder finder) {
    final box = tester.getRect(finder);
    expect(box.left, greaterThanOrEqualTo(0), reason: '$finder starts off the left edge');
    expect(box.right, lessThanOrEqualTo(tester.view.physicalSize.width / tester.view.devicePixelRatio + 0.5),
        reason: '$finder runs off the right edge');
  }

  for (final lang in [AppLanguage.en, AppLanguage.ta, AppLanguage.te]) {
    testWidgets('every tour step fits a small phone in ${lang.englishName}', (tester) async {
      final (container, project) = await sample(tester, lang);
      for (var step = 0; step < appTourSteps().length; step++) {
        await pump(tester, container, lang,
            AppTourScreen(key: ValueKey(step), companyId: project.companyId, project: project, initialStep: step));
        expect(tester.takeException(), isNull, reason: 'tour step $step');
        // The Next (or last-step) button is on screen and tappable.
        final next = step == appTourSteps().length - 1 ? find.text(tr('Start my project')) : find.byIcon(Icons.arrow_forward);
        expect(next.hitTestable(), findsOneWidget, reason: 'tour step $step');
      }
    });
  }

  testWidgets('Workers tab keeps Add worker on screen in Tamil', (tester) async {
    final (container, project) = await sample(tester, AppLanguage.ta);
    await pump(tester, container, AppLanguage.ta, ProjectDetailScreen(project: project, initialTab: 10));
    expect(tester.takeException(), isNull);
    onScreen(tester, find.byTooltip(tr('Add worker')));
    // "a day" and the trade read in Tamil too.
    expect(find.textContaining('a day'), findsNothing);
    expect(find.textContaining('Mason'), findsNothing);
  });

  testWidgets('Wage sheet keeps the next-week arrow on screen with large Tamil text', (tester) async {
    final (container, project) = await sample(tester, AppLanguage.ta);
    await pump(
        tester,
        container,
        AppLanguage.ta,
        WageSheetScreen(
            projectId: project.id, projectName: project.name, userId: container.read(sessionProvider).user!.id),
        size: const Size(360, 760),
        textScale: 1.3);
    expect(tester.takeException(), isNull);
    onScreen(tester, find.byTooltip(tr('Next week')));
  });

  testWidgets('Money totals fit side by side with large text', (tester) async {
    final (container, project) = await sample(tester, AppLanguage.en);
    await pump(tester, container, AppLanguage.en, ProjectDetailScreen(project: project, initialTab: 6),
        size: const Size(360, 760), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  test('approvals say when they were raised in the app\'s language', () {
    final now = DateTime(2026, 11, 9, 12);
    setCurrentLanguage(AppLanguage.hi);
    expect(raisedWhen(now, now: now), tr('raised today'));
    expect(raisedWhen(now.subtract(const Duration(days: 1)), now: now), tr('raised yesterday'));
    expect(raisedWhen(DateTime(2026, 11, 3), now: now), trf('raised on {date}', {'date': '3 Nov'}));
    expect(raisedWhen(now, now: now), isNot(contains('raised')));
    setCurrentLanguage(AppLanguage.en);
    expect(raisedWhen(DateTime(2026, 11, 3), now: now), 'raised on 3 Nov');
  });

  testWidgets('the navy sign-in pages ask for white status-bar icons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandedSheetPage(header: [Text('FieldOS')], sheet: Text('form'))));
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first);
    expect(region.value.statusBarIconBrightness, Brightness.light);
  });
}
