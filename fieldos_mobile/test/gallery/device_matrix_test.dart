/// Lays every main screen out on many phones and settings and reports what
/// breaks: text or rows that overflow, buttons too small to tap with a
/// gloved thumb, icons with no label for a screen reader, and text too faint
/// to read in sunlight.
///
/// It is skipped in normal test runs. To run one setting:
///
///   AUDIT_MATRIX=1 MATRIX_DEVICE=android_small MATRIX_SCALE=2.0 \
///     MATRIX_DARK=1 MATRIX_LANG=te INDIC_FONTS=/path/to/noto \
///     flutter test test/gallery/device_matrix_test.dart
///
/// MATRIX_DEVICE is one of the keys of [devices] (default android_medium).
/// MATRIX_SHOTS=1 also writes a PNG per screen. Results go to
/// `build/matrix/<setting>/report.json`, one entry per screen.
library;

import 'dart:convert';
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
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/brief/owner_brief_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/features/map/site_map_screen.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/procurement/payables_screen.dart';
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
import 'package:fieldos_mobile/l10n/language_welcome.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// A phone or tablet: its size in logical pixels, pixel ratio, and the
/// system bars it draws over the app (status bar or notch on top; on the
/// bottom the 3-button bar, the gesture handle, or the iPhone home bar).
typedef Device = ({Size size, double ratio, double top, double bottom});

const Map<String, Device> devices = {
  // Low-end Android, 5-inch, 3-button navigation.
  'android_small': (size: Size(360, 640), ratio: 2.0, top: 24, bottom: 48),
  // The common Android size (Pixel 7a, Galaxy A-series), 3-button.
  'android_medium': (size: Size(412, 915), ratio: 2.625, top: 24, bottom: 48),
  // Big Android with gesture navigation (Pixel 8 Pro, Galaxy S Ultra).
  'android_large': (size: Size(448, 998), ratio: 3.0, top: 32, bottom: 24),
  // Galaxy Z Fold cover screen: tall and very narrow.
  'fold_cover': (size: Size(344, 882), ratio: 2.625, top: 28, bottom: 24),
  // Galaxy Z Fold opened: almost square.
  'fold_open': (size: Size(673, 841), ratio: 2.625, top: 28, bottom: 24),
  'tablet7': (size: Size(600, 960), ratio: 2.0, top: 24, bottom: 48),
  'tablet10': (size: Size(800, 1280), ratio: 2.0, top: 24, bottom: 48),
  'iphone_se': (size: Size(375, 667), ratio: 2.0, top: 20, bottom: 0),
  'iphone_15': (size: Size(393, 852), ratio: 3.0, top: 59, bottom: 34),
  'iphone_pro_max': (size: Size(440, 956), ratio: 3.0, top: 62, bottom: 34),
  'ipad': (size: Size(820, 1180), ratio: 2.0, top: 24, bottom: 20),
};

final _env = Platform.environment;
final _run = _env['AUDIT_MATRIX'] == '1';
final _only = _env['MATRIX_ONLY'];
final _deviceName = _env['MATRIX_DEVICE'] ?? 'android_medium';
final Device _device = devices[_deviceName]!;
final _scale = double.parse(_env['MATRIX_SCALE'] ?? '1.0');
final _dark = _env['MATRIX_DARK'] == '1';
// MATRIX_MARKET=us|my|ae|uk lays the screens out as that country's app
// (its money, wording and languages); default India.
final _market = Market.fromId(_env['MATRIX_MARKET']) ?? Market.india;
final _lang = AppLanguage.fromCode(_env['MATRIX_LANG']) ?? AppLanguage.en;
final _shots = _env['MATRIX_SHOTS'] == '1';
final _a11y = _env['MATRIX_A11Y'] != '0';
// Contrast is sampled from the rendered pixels, which misreads small
// anti-aliased text, so it is opt-in; theme_contrast_test checks the colours.
final _contrast = _env['MATRIX_CONTRAST'] == '1';
final _setting = '${_market == Market.india ? '' : '${_market.id}_'}${_deviceName}_x${_scale}_${_dark ? 'dark' : 'light'}_${_lang.code}';
final _outDir = Directory('${_env['MATRIX_OUT'] ?? 'build/matrix'}/$_setting');

var _fontsLoaded = false;
Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
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
  final flutterRoot = _env['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  await load('Roboto', ['$flutterRoot/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf']);
  final indic = _env['INDIC_FONTS'];
  // Phones bring a Chinese font of their own; Brand doesn't name one. For a
  // Chinese run, load the test machine's CJK font (CJK_FONT) in Kannada's
  // slot of the fallback list, which a Chinese screen never uses.
  final cjk = _env['CJK_FONT'];
  if (cjk != null && _lang.code == 'zh') await load('NotoSansKannada', [cjk]);
  if (indic != null) {
    for (final f in Brand.fontFallback) {
      final file = File('$indic/$f.ttf');
      if (cjk != null && _lang.code == 'zh' && f == 'NotoSansKannada') continue;
      if (file.existsSync()) await load(f, [file.path]);
    }
  }
}

typedef _Shot = Widget Function(ProviderContainer c, Project p);

final Map<String, _Shot> _screens = {
  '00_language_welcome': (c, p) => const LanguageWelcomeScreen(),
  '01_login': (c, p) => const LoginScreen(),
  '02_company_setup': (c, p) => const CompanySetupScreen(),
  '03_paywall': (c, p) => PaywallScreen(onUnlocked: () {}),
  '04_home': (c, p) => const HomeScreen(),
  for (final (i, name) in [
    (0, 'tasks'), (1, 'dpr'), (2, 'issues'), (3, 'chat'), (4, 'procure'), (5, 'labour'),
    (6, 'money'), (7, 'equipment'), (8, 'inspections'), (9, 'documents'), (10, 'workers'), (11, 'estimation'),
  ])
    '${10 + i}_project_$name': (c, p) => ProjectDetailScreen(project: p, initialTab: i),
  '30_wage_sheet': (c, p) =>
      WageSheetScreen(projectId: p.id, projectName: p.name, userId: c.read(sessionProvider).user!.id),
  '31_period_report': (c, p) => PeriodReportScreen(project: p),
  '32_material_rates': (c, p) => MaterialRatesScreen(projectId: p.id, companyId: p.companyId),
  '33_unit_converter': (c, p) => const UnitConverterScreen(),
  '40_dashboard': (c, p) => DashboardScreen(companyId: p.companyId, companyName: 'Sri Sai Constructions'),
  '41_approvals': (c, p) => ApprovalsScreen(companyId: p.companyId),
  '42_my_tasks': (c, p) => MyTasksScreen(companyId: p.companyId),
  '43_site_map': (c, p) => SiteMapScreen(companyId: p.companyId),
  '44_subcontractors': (c, p) => SubcontractorsScreen(companyId: p.companyId),
  '45_search': (c, p) => SearchScreen(companyId: p.companyId),
  '46_team_sync': (c, p) => const TeamSyncScreen(),
  '47_settings': (c, p) => const SettingsScreen(),
  '48_bug_report': (c, p) => const BugReportScreen(),
  '50_site_brief': (c, p) => OwnerBriefScreen(companyId: p.companyId, companyName: 'Sri Sai Constructions'),
  '51_who_you_owe': (c, p) => PayablesScreen(companyId: p.companyId),
  for (var i = 0; i < appTourSteps().length; i++)
    '6${i.toString().padLeft(2, '0')}_tour': (c, p) =>
        AppTourScreen(companyId: p.companyId, project: p, initialStep: i),
};

/// One problem found on a screen.
Map<String, Object?> _issue(String kind, String detail) => {'kind': kind, 'detail': detail};

/// The first line of a Flutter error, plus the widget it points at, which is
/// enough to find it in the code.
String _summarise(FlutterErrorDetails d) {
  final lines = d.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final head = d.exceptionAsString().split('\n').first;
  final created = lines.where((l) => l.contains('created by') || l.contains('.dart:')).take(3).join(' | ');
  return '$head  $created';
}

void main() {
  final results = <String, List<Map<String, Object?>>>{};

  tearDownAll(() {
    if (!_run) return;
    _outDir.createSync(recursive: true);
    File('${_outDir.path}/report.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert({'setting': _setting, 'screens': results}));
  });

  for (final entry in _screens.entries) {
    testWidgets('$_setting ${entry.key}', (tester) async {
      debugSetMarket(_market);
      addTearDown(() => debugSetMarket(Market.india));
      final issues = results[entry.key] = [];
      // Real soft shadows, as on a phone, not test-mode black outlines.
      debugDisableShadows = false;
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
        await _loadFonts();
        final session = container.read(sessionProvider.notifier);
        await session.register(username: 'ramesh', name: 'Ramesh Rao', password: '123456');
        final company = await session.createCompany('Sri Sai Constructions');
        project = await createSampleProject(db, companyId: company.id, userId: container.read(sessionProvider).user!.id);
        await db.settingsDao.set(tourSeenKey, '1');
        // As if the person picked the language and turned on "Show screens
        // in it", so screens that load the saved choice don't fall back to
        // English.
        await db.settingsDao.set(languageSettingKey, _lang.code);
        await db.settingsDao.set(screensInLanguageKey, _lang == AppLanguage.en ? '0' : '1');
      });

      setCurrentLanguage(_lang);
      final d = _device;
      tester.view.physicalSize = d.size * d.ratio;
      tester.view.devicePixelRatio = d.ratio;
      final insets = FakeViewPadding(top: d.top * d.ratio, bottom: d.bottom * d.ratio);
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
      tester.platformDispatcher.textScaleFactorTestValue = _scale;
      tester.platformDispatcher.platformBrightnessTestValue = _dark ? Brightness.dark : Brightness.light;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      // Collect layout errors instead of failing on the first one, so one
      // run lists every broken screen.
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final s = _summarise(details);
        if (!issues.any((i) => i['detail'] == s)) issues.add(_issue('layout', s));
      };
      final boundary = GlobalKey();
      try {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildFieldOsTheme(Brightness.light),
              darkTheme: buildFieldOsTheme(Brightness.dark),
              locale: _lang.locale,
              supportedLocales: [for (final l in AppLanguage.values) l.locale],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => TabletZoom(child: SystemNavBarSafeArea(child: child!)),
              home: entry.value(container, project),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await tester.pump(const Duration(milliseconds: 300));
        }
      } finally {
        FlutterError.onError = previous;
      }
      final pending = tester.takeException();
      if (pending != null) issues.add(_issue('exception', pending.toString().split('\n').first));

      final handle = tester.ensureSemantics();
      for (final (kind, g) in [
        if (_a11y) ('tap_target', androidTapTargetGuideline),
        if (_a11y) ('label', labeledTapTargetGuideline),
        if (_contrast) ('contrast', textContrastGuideline),
      ]) {
        final r = await g.evaluate(tester);
        if (!r.passed) {
          for (final line in (r.reason ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(12)) {
            issues.add(_issue(kind, line.trim()));
          }
        }
      }
      handle.dispose();

      if (_shots) {
        final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final ui.Image shot = await render.toImage(pixelRatio: d.ratio);
          final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
          _outDir.createSync(recursive: true);
          File('${_outDir.path}/${entry.key}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      debugDisableShadows = true;
    }, skip: !_run || (_only != null && !entry.key.contains(_only!)));
  }
}
