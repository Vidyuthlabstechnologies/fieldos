/// Renders every main screen of the app to a PNG, filled with the sample
/// site's data, for design reviews, wireframes and store pictures.
///
/// It is skipped in normal test runs. To render:
///
///   RENDER_SCREENS=1 flutter test test/gallery/screen_gallery_test.dart
///
/// The PNGs land in build/screens/ (1080 px wide). Real fonts are loaded
/// (Inter and the Material icons) so text isn't drawn as test boxes.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/features/brief/owner_brief_screen.dart';
import 'package:fieldos_mobile/features/procurement/payables_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/features/map/site_map_screen.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/procurement/purchase_screens.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/reports/period_report_screen.dart';
import 'package:fieldos_mobile/features/search/search_screen.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/features/subcontractor/subcontractor_screen.dart';
import 'package:fieldos_mobile/features/subscription/paywall_screen.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/features/tasks/my_tasks_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

final _render = Platform.environment['RENDER_SCREENS'] == '1';
final _only = Platform.environment['RENDER_ONLY'];
var _withInvite = false;

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await load('Inter', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$w.otf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  await load('Roboto', ['$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf']);
  // Phones bring their own Indian-script fonts; the test machine doesn't.
  // Point INDIC_FONTS at a folder of Noto Sans .ttf files to render those.
  final indic = Platform.environment['INDIC_FONTS'];
  if (indic != null) {
    for (final f in Brand.fontFallback) {
      final file = File('$indic/$f.ttf');
      if (file.existsSync()) await load(f, [file.path]);
    }
  }
}


/// Draws Android's translucent 3-button bar (back, home, recents) over the
/// bottom of [shot], as a phone with button navigation shows it.
Future<ui.Image> _withNavBar(ui.Image shot, double height) async {
  final w = shot.width.toDouble(), h = shot.height.toDouble();
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawImage(shot, Offset.zero, Paint());
  final top = h - height;
  c.drawRect(Rect.fromLTWH(0, top, w, height), Paint()..color = const Color(0x8A000000));
  final white = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = height * 0.045;
  final cy = top + height / 2, r = height * 0.17;
  final back = Path()
    ..moveTo(w * 0.25 + r, cy - r)
    ..lineTo(w * 0.25 - r, cy)
    ..lineTo(w * 0.25 + r, cy + r)
    ..close();
  c.drawPath(back, white);
  c.drawCircle(Offset(w * 0.5, cy), r, white);
  c.drawRect(Rect.fromCenter(center: Offset(w * 0.75, cy), width: r * 1.8, height: r * 1.8), white);
  return rec.endRecording().toImage(shot.width, shot.height);
}

void main() {
  const size = Size(412, 915);
  const ratio = 1080 / 412;

  Future<(ProviderContainer, AppDatabase, Project)> sampleCompany(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
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
    late Project project;
    await tester.runAsync(() async {
      await _loadFonts();
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ramesh', name: 'Ramesh Rao', password: '123456');
      final company = await session.createCompany('Sri Sai Constructions');
      project = await createSampleProject(db,
          companyId: company.id, userId: container.read(sessionProvider).user!.id);
      if (!_withInvite) await db.settingsDao.set(tourSeenKey, '1');
    });
    return (container, db, project);
  }

  Future<void> shoot(WidgetTester tester, ProviderContainer container, String name, Widget screen,
      {AppLanguage lang = AppLanguage.en, Future<void> Function()? then}) async {
    setCurrentLanguage(lang);
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    // A status bar on top and Android's 3-button navigation bar (48 dp) at
    // the bottom, so anything drawn under the phone's own buttons shows.
    const insets = FakeViewPadding(top: 24 * ratio, bottom: 48 * ratio);
    tester.view.padding = insets;
    tester.view.viewPadding = insets;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildFieldOsTheme(Brightness.light),
          locale: lang.locale,
          supportedLocales: [for (final l in AppLanguage.values) l.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => SystemNavBarSafeArea(child: child!),
          home: screen,
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    if (then != null) {
      await then();
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    // Paint the navigation bar in, the way the phone would.
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final shot = await render.toImage(pixelRatio: ratio);
      final image = await _withNavBar(shot, 48 * ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/screens')..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  final shots = <String, Future<void> Function(WidgetTester, ProviderContainer, AppDatabase, Project)>{
    '01_login': (t, c, db, p) => shoot(t, c, '01_login', const LoginScreen()),
    '02_company_setup': (t, c, db, p) => shoot(t, c, '02_company_setup', const CompanySetupScreen()),
    '03_paywall': (t, c, db, p) => shoot(t, c, '03_paywall', PaywallScreen(onUnlocked: () {})),
    '04_home': (t, c, db, p) => shoot(t, c, '04_home', const HomeScreen()),
    for (final (i, name) in [
      (0, 'tasks'), (1, 'dpr'), (2, 'issues'), (3, 'chat'), (4, 'procure'), (5, 'labour'),
      (6, 'money'), (7, 'equipment'), (8, 'inspections'), (9, 'documents'), (10, 'workers'), (11, 'estimation'),
    ])
      '${10 + i}_project_$name': (t, c, db, p) =>
          shoot(t, c, '${10 + i}_project_$name', ProjectDetailScreen(project: p, initialTab: i)),
    '30_wage_sheet': (t, c, db, p) => shoot(t, c, '30_wage_sheet',
        WageSheetScreen(projectId: p.id, projectName: p.name, userId: c.read(sessionProvider).user!.id)),
    '31_period_report': (t, c, db, p) => shoot(t, c, '31_period_report', PeriodReportScreen(project: p)),
    '32_material_rates': (t, c, db, p) =>
        shoot(t, c, '32_material_rates', MaterialRatesScreen(projectId: p.id, companyId: p.companyId)),
    '33_unit_converter': (t, c, db, p) => shoot(t, c, '33_unit_converter', const UnitConverterScreen()),
    '40_dashboard': (t, c, db, p) =>
        shoot(t, c, '40_dashboard', DashboardScreen(companyId: p.companyId, companyName: 'Sri Sai Constructions')),
    '41_approvals': (t, c, db, p) => shoot(t, c, '41_approvals', ApprovalsScreen(companyId: p.companyId)),
    '42_my_tasks': (t, c, db, p) => shoot(t, c, '42_my_tasks', MyTasksScreen(companyId: p.companyId)),
    '43_site_map': (t, c, db, p) => shoot(t, c, '43_site_map', SiteMapScreen(companyId: p.companyId)),
    '44_subcontractors': (t, c, db, p) =>
        shoot(t, c, '44_subcontractors', SubcontractorsScreen(companyId: p.companyId)),
    '45_search': (t, c, db, p) => shoot(t, c, '45_search', SearchScreen(companyId: p.companyId)),
    '46_team_sync': (t, c, db, p) => shoot(t, c, '46_team_sync', const TeamSyncScreen()),
    '47_settings': (t, c, db, p) => shoot(t, c, '47_settings', const SettingsScreen()),
    '48_bug_report': (t, c, db, p) => shoot(t, c, '48_bug_report', const BugReportScreen()),
    '51_who_you_owe': (t, c, db, p) => shoot(t, c, '51_who_you_owe', PayablesScreen(companyId: p.companyId)),
    '50_site_brief': (t, c, db, p) =>
        shoot(t, c, '50_site_brief', OwnerBriefScreen(companyId: p.companyId, companyName: 'Sri Sai Constructions')),
    '05_home_tour_invite': (t, c, db, p) => shoot(t, c, '05_home_tour_invite', const HomeScreen()),
    for (final i in List.generate(11, (i) => i))
      '6${i.toString().padLeft(2, '0')}_tour': (t, c, db, p) => shoot(t, c, '6${i.toString().padLeft(2, '0')}_tour',
          AppTourScreen(companyId: p.companyId, project: p, initialStep: i)),
    // The everyday screens in each Indian language, to catch words that
    // overflow or fall back to English.
    for (final lang in [AppLanguage.hi, AppLanguage.te, AppLanguage.ta, AppLanguage.kn, AppLanguage.mr]) ...{
      '70_home_${lang.code}': (t, c, db, p) => shoot(t, c, '70_home_${lang.code}', const HomeScreen(), lang: lang),
      '71_tasks_${lang.code}': (t, c, db, p) =>
          shoot(t, c, '71_tasks_${lang.code}', ProjectDetailScreen(project: p), lang: lang),
      '72_labour_${lang.code}': (t, c, db, p) =>
          shoot(t, c, '72_labour_${lang.code}', ProjectDetailScreen(project: p, initialTab: 5), lang: lang),
      '73_money_${lang.code}': (t, c, db, p) =>
          shoot(t, c, '73_money_${lang.code}', ProjectDetailScreen(project: p, initialTab: 6), lang: lang),
      '74_tour_${lang.code}': (t, c, db, p) => shoot(t, c, '74_tour_${lang.code}',
          AppTourScreen(companyId: p.companyId, project: p, initialStep: 1), lang: lang),
    },
  };

  for (final entry in shots.entries) {
    testWidgets('render ${entry.key}', (tester) async {
      _withInvite = entry.key.contains('invite');
      // Real soft shadows, as on a phone. Tests draw them as solid black
      // outlines by default, which made every button look heavy-rimmed.
      debugDisableShadows = false;
      try {
        final (container, db, project) = await sampleCompany(tester);
        await entry.value(tester, container, db, project);
      } finally {
        debugDisableShadows = true;
      }
    }, skip: !_render || (_only != null && !entry.key.contains(_only!)));
  }
}
