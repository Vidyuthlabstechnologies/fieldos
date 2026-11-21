/// Renders the first-run screens to PNGs for review: Google-first login,
/// company setup, and Home with the "Get your first site running"
/// checklist and the trial notice (English, Telugu and Hindi).
///
/// Skipped in normal runs. To render:
///
///   RENDER_SCREENS=1 INDIC_FONTS=<dir of NotoSans*.ttf> flutter test test/gallery/first_run_gallery_test.dart
///
/// The PNGs land in build/screens/first_run/ (1080 px wide).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/auth/google_auth.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/team/invite_team.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/subscription_access.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

import '../paywall_screen_test.dart' show FakeBilling;

final _render = Platform.environment['RENDER_SCREENS'] == '1';

class _Google implements GoogleAccountPicker {
  @override
  bool get available => true;
  @override
  Future<GoogleIdentityResult?> pick() async => null;
  @override
  Future<void> signOut() async {}
}

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

  Future<(ProviderContainer, AppDatabase)> setUp(WidgetTester tester,
      {bool company = true, int stepsDone = 1, bool trial = true}) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      googlePickerProvider.overrideWithValue(_Google()),
      if (trial)
        billingServiceProvider.overrideWithValue(FakeBilling(db, offers: const [])
          ..live = SubscriptionState(
              active: true, inTrial: true, willRenew: true, expiresAt: DateTime.now().add(const Duration(days: 2, hours: 3)))),
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
    await tester.runAsync(() async {
      await _loadFonts();
      await db.settingsDao.set(tourSeenKey, '1');
      if (!company) return;
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ramesh', name: 'Ramesh Rao', password: '123456');
      final c = await session.createCompany('Sri Sai Constructions');
      if (stepsDone >= 1) {
        await db.projectDao.create(ProjectsCompanion.insert(
            id: 'p1', companyId: c.id, name: 'Green Valley Villas, Block A', clientName: const Value('Mr. Reddy')));
      }
      if (stepsDone >= 2) {
        await db.into(db.labourAttendance).insert(LabourAttendanceCompanion.insert(
            id: 'a1', projectId: 'p1', workerName: 'Raju', recordedBy: 'u', punchIn: DateTime.now()));
      }
      if (stepsDone >= 3) {
        await db.into(db.dprEntries).insert(DprEntriesCompanion.insert(
            id: 'd1', projectId: 'p1', createdBy: 'u', entryDate: DateTime.now(), workSummary: 'Slab shuttering'));
      }
      if (stepsDone >= 4) await db.settingsDao.set(inviteSharedKey(c.id), '1');
    });
    return (container, db);
  }

  Future<void> shoot(WidgetTester tester, ProviderContainer container, String name, Widget screen,
      {AppLanguage lang = AppLanguage.en, Brightness brightness = Brightness.light}) async {
    final db = container.read(appDatabaseProvider);
    await tester.runAsync(() async {
      await db.settingsDao.set(languageSettingKey, lang.code);
      await db.settingsDao.set(screensInLanguageKey, lang == AppLanguage.en ? '0' : '1');
    });
    setCurrentLanguage(lang);
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
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
          theme: buildFieldOsTheme(brightness),
          locale: lang.locale,
          supportedLocales: [for (final l in AppLanguage.offered) l.locale],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => SystemNavBarSafeArea(child: child!),
          home: screen,
        ),
      ),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 300));
    }
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final shot = await render.toImage(pixelRatio: ratio);
      final image = await _withNavBar(shot, 48 * ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/screens/first_run')..createSync(recursive: true);
      File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    setCurrentLanguage(AppLanguage.en);
  }

  testWidgets('01 login on a new phone: Google first', (t) async {
    final (c, _) = await setUp(t, company: false);
    await shoot(t, c, '01_login_google_first', const LoginScreen());
  }, skip: !_render);

  testWidgets('02 company setup', (t) async {
    final (c, db) = await setUp(t, company: false);
    await t.runAsync(() => c.read(sessionProvider.notifier).register(username: 'ramesh', name: 'Ramesh Rao', password: '123456'));
    await shoot(t, c, '02_company_setup', const CompanySetupScreen());
  }, skip: !_render);

  testWidgets('03 home: first site added, trial notice', (t) async {
    final (c, _) = await setUp(t);
    await shoot(t, c, '03_home_get_started_1_of_4', const HomeScreen());
  }, skip: !_render);

  testWidgets('04 home: 3 of 4, Telugu', (t) async {
    final (c, _) = await setUp(t, stepsDone: 3);
    await shoot(t, c, '04_home_get_started_3_of_4_te', const HomeScreen(), lang: AppLanguage.te);
  }, skip: !_render);

  testWidgets('05 home: all done, dark, Hindi', (t) async {
    final (c, _) = await setUp(t, stepsDone: 4, trial: false);
    await shoot(t, c, '05_home_get_started_done_hi_dark', const HomeScreen(),
        lang: AppLanguage.hi, brightness: Brightness.dark);
  }, skip: !_render);
}
