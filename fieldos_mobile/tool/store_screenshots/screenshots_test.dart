/// Renders real FieldOS screens, filled with demo data, to PNG files for the
/// store listing, the pitch deck and the launch videos. Not part of the normal
/// test run: run it on its own with
///
///   flutter test tool/store_screenshots/screenshots_test.dart
///
/// PNGs land in build/store_screenshots/ (override with SHOTS_DIR). The demo
/// data is invented (round figures, made-up sites); never use a real client's
/// numbers here.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/estimation/estimation_calc.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/assistant/assistant_screen.dart';
import 'package:fieldos_mobile/features/brief/owner_brief_screen.dart';
import 'package:fieldos_mobile/features/procurement/payables_screen.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/language_picker.dart';
import 'package:fieldos_mobile/services/ai_backend.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

const _uuid = Uuid();
// SHOTS_DEVICE picks the screen the app is laid out for:
//   phone (default) 1080x2160, a common Android phone
//   iphone          1290x2796, the App Store 6.9-inch slot
//   tablet7         1200x1920, a 7-inch Android tablet
//   tablet10        1600x2560, a 10-inch Android tablet
//   ipad            2048x2732, the App Store 13-inch iPad slot
// Tablets use display zoom (a higher pixel ratio), so the phone-first
// screens fill the tablet instead of floating in empty space.
final _device = switch (Platform.environment['SHOTS_DEVICE'] ?? 'phone') {
  'iphone' => (const Size(430, 932), 3.0),
  'tablet7' => (const Size(480, 768), 2.5),
  'tablet10' => (const Size(640, 1024), 2.5),
  'ipad' => (const Size(819.2, 1092.8), 2.5),
  _ => (const Size(1080 / 2.625, 2160 / 2.625), 2.625),
};
final Size _logical = _device.$1;
final double _pixelRatio = _device.$2;

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

ThemeData _withIndicFallback(ThemeData t) {
  const fallback = ['NotoDeva', 'NotoTelugu', 'NotoTamil', 'NotoKannada'];
  TextTheme add(TextTheme x) => x.apply(fontFamilyFallback: fallback);
  TextStyle? f(TextStyle? x) => x?.copyWith(fontFamilyFallback: fallback);
  ButtonStyle? b(ButtonStyle? x) {
    final ts = x?.textStyle?.resolve({});
    return ts == null ? x : x!.copyWith(textStyle: WidgetStatePropertyAll(f(ts)));
  }

  return t.copyWith(
    textTheme: add(t.textTheme),
    primaryTextTheme: add(t.primaryTextTheme),
    appBarTheme: t.appBarTheme.copyWith(titleTextStyle: f(t.appBarTheme.titleTextStyle)),
    tabBarTheme: t.tabBarTheme.copyWith(
        labelStyle: f(t.tabBarTheme.labelStyle), unselectedLabelStyle: f(t.tabBarTheme.unselectedLabelStyle)),
    floatingActionButtonTheme:
        t.floatingActionButtonTheme.copyWith(extendedTextStyle: f(t.floatingActionButtonTheme.extendedTextStyle)),
    filledButtonTheme: FilledButtonThemeData(style: b(t.filledButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: b(t.elevatedButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: b(t.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(style: b(t.textButtonTheme.style)),
    chipTheme: t.chipTheme.copyWith(
        labelStyle: f(t.chipTheme.labelStyle), secondaryLabelStyle: f(t.chipTheme.secondaryLabelStyle)),
    dialogTheme: t.dialogTheme.copyWith(titleTextStyle: f(t.dialogTheme.titleTextStyle)),
    snackBarTheme: t.snackBarTheme.copyWith(contentTextStyle: f(t.snackBarTheme.contentTextStyle)),
  );
}

/// Plays back canned assistant replies, so the chat screen can be shown
/// without a server.
class _ScriptedAi implements AiBackend {
  _ScriptedAi(this.replies);
  final List<AiReply> replies;
  @override
  bool get signedIn => true;
  @override
  Future<AiReply> chat(List<Map<String, dynamic>> messages) async => replies.removeAt(0);
  @override
  Future<String> transcribe(Uint8List wav, {String languageCode = 'unknown'}) async => '';
}

void main() {
  // SHOTS_LANG=hi or te renders the app in Hindi or Telugu.
  final lang = AppLanguage.fromCode(Platform.environment['SHOTS_LANG']) ?? AppLanguage.en;
  setUp(() => setCurrentLanguage(lang));
  tearDown(() => setCurrentLanguage(AppLanguage.en));
  // SHOTS_TOUR_SEEN=1 hides the tour invite on Home.
  final tourSeen = Platform.environment['SHOTS_TOUR_SEEN'] == '1';
  final outDir = Directory(Platform.environment['SHOTS_DIR'] ?? 'build/store_screenshots')..createSync(recursive: true);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';

  setUpAll(() async {
    await _loadFont('Inter', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$w.otf',
    ]);
    final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
    await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
    // Hindi and Telugu glyphs: a phone has them as system fonts, the test
    // engine does not. INDIC_FONTS_DIR holds Noto Sans Devanagari and Telugu TTFs.
    final indic = Platform.environment['INDIC_FONTS_DIR'];
    if (indic != null) {
      final files = Directory(indic).listSync().map((f) => f.path).toList()..sort();
      await _loadFont('NotoDeva', files.where((f) => f.contains('devanagari')).toList());
      await _loadFont('NotoTelugu', files.where((f) => f.contains('telugu')).toList());
      // Tamil and Kannada only show up in the language picker's own names.
      final tamil = files.where((f) => f.contains('tamil')).toList();
      final kannada = files.where((f) => f.contains('kannada')).toList();
      if (tamil.isNotEmpty) await _loadFont('NotoTamil', tamil);
      if (kannada.isNotEmpty) await _loadFont('NotoKannada', kannada);
    }
    await _loadFont('Roboto', ['$material/Roboto-Regular.ttf', '$material/Roboto-Medium.ttf', '$material/Roboto-Bold.ttf']);
  });

  late AppDatabase db;
  late ProviderContainer container;
  late String companyId;
  late String userId;
  late Project mainSite;

  Future<void> seed(WidgetTester tester, {List<AiReply> Function()? ai}) async {
    db = AppDatabase.memory();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (ai != null) aiBackendProvider.overrideWith((ref) => _ScriptedAi(ai())),
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
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      userId = container.read(sessionProvider).user!.id;
      final now = DateTime.now();
      final p = await createSampleProject(db, companyId: companyId, userId: userId, now: now);
      // Show it as an ordinary site: no "sample" banner, a real-sounding name.
      await db.settingsDao.set(sampleProjectKey(companyId), '');
      await db.customStatement(
        'UPDATE projects SET name = ?, client_name = ? WHERE id = ?',
        ['Kompally Villa, Block B', 'Mr. Reddy (G+1 house)', p.id],
      );
      mainSite = (await db.projectDao.byId(p.id))!;

      final sites = <String, String>{'Kompally Villa, Block B': p.id};
      for (final (name, client, status) in [
        ('Miyapur Apartments, Tower 2', 'Lakshmi Developers', 'active'),
        ('Gachibowli Office Fit-out', 'Nova Tech Parks', 'active'),
        ('Shamshabad Warehouse', 'Om Logistics', 'planning'),
      ]) {
        final id = _uuid.v4();
        sites[name] = id;
        await db.projectDao.create(ProjectsCompanion.insert(
          id: id,
          companyId: companyId,
          name: name,
          clientName: Value(client),
          status: Value(status),
          startDate: Value(now.subtract(const Duration(days: 60))),
          endDate: Value(now.add(const Duration(days: 200))),
        ));
      }
      await _seedBusiness(db, companyId, userId, sites, now);
      if (tourSeen) await db.settingsDao.set(tourSeenKey, '1');
    });
  }

  Future<void> shoot(WidgetTester tester, String name, Widget screen, {Future<void> Function()? before}) async {
    tester.view.physicalSize = _logical * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);
    // flutter_test draws shadows as hard black outlines unless told otherwise.
    debugDisableShadows = false;
    final key = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _withIndicFallback(buildFieldOsTheme(Brightness.light)),
          home: screen,
        ),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
    if (before != null) await before();
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${outDir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    // Let the screens' own timers (clocks, debounces) run out before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 5));
    debugDisableShadows = true;
  }

  testWidgets('01 home: every site', (tester) async {
    await seed(tester);
    await shoot(tester, '01_home', const HomeScreen());
  });

  testWidgets('02 dashboard', (tester) async {
    await seed(tester);
    await shoot(tester, '02_dashboard', DashboardScreen(companyId: companyId, companyName: 'Sri Sai Constructions'));
  });

  for (final (index, name) in [
    (0, '03_tasks'),
    (1, '04_dpr'),
    (2, '05_issues'),
    (7, '13_equipment'),
    (5, '07_labour'),
    (6, '08_money'),
    (8, '09_inspections'),
    (10, '10_workers'),
  ]) {
    testWidgets('$name tab', (tester) async {
      await seed(tester);
      await shoot(tester, name, ProjectDetailScreen(project: mainSite, initialTab: index));
    });
  }

  testWidgets('11 wage sheet', (tester) async {
    await seed(tester);
    // Today's gang has gone home too, so the sheet shows clean full days.
    await tester.runAsync(() => db.customStatement(
        'UPDATE labour_attendance SET punch_out = punch_in + 30600 WHERE punch_out IS NULL'));
    await shoot(tester, '11_wage_sheet',
        WageSheetScreen(projectId: mainSite.id, projectName: mainSite.name, userId: userId), before: () async {
      // Last full week, so Saturday's sheet shows a whole week's days.
      await tester.tap(find.byIcon(Icons.chevron_left));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 300));
      }
    });
  });

  testWidgets('06 stock', (tester) async {
    await seed(tester);
    await shoot(tester, '06_stock', ProjectDetailScreen(project: mainSite, initialTab: 4), before: () async {
      await tester.tap(find.text(tr('Stock')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('12 approvals', (tester) async {
    await seed(tester);
    await shoot(tester, '12_approvals', ApprovalsScreen(companyId: companyId));
  });

  testWidgets('14 assistant: say it, it saves it', (tester) async {
    late String siteId;
    await seed(tester, ai: () => [
          AiReply(content: [
            {'type': 'text', 'text': _assistantSays[lang]!},
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'add_expense',
              'input': {'project_id': siteId, 'amount': 5000, 'category': 'Material', 'note': 'cement'}
            },
          ], stopReason: 'tool_use'),
        ]);
    siteId = mainSite.id;
    await shoot(tester, '14_assistant', const AssistantScreen(), before: () async {
      await tester.enterText(find.byType(TextField), _assistantAsk[lang]!);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 400));
      }
    });
  });

  testWidgets('15 owner brief', (tester) async {
    await seed(tester);
    await shoot(tester, '15_brief', OwnerBriefScreen(companyId: companyId, companyName: 'Sri Sai Constructions'));
  });

  testWidgets('16 who you owe', (tester) async {
    await seed(tester);
    await shoot(tester, '16_owe', PayablesScreen(companyId: companyId));
  });

  testWidgets('18 language picker', (tester) async {
    await seed(tester);
    late BuildContext pickerContext;
    late WidgetRef pickerRef;
    await shoot(tester, '18_languages', Consumer(builder: (context, ref, _) {
      pickerContext = context;
      pickerRef = ref;
      return const HomeScreen();
    }), before: () async {
      unawaited(showLanguagePicker(pickerContext, pickerRef));
      await tester.pumpAndSettle();
    });
  });

  for (final step in [0, 3, 5]) {
    testWidgets('17 tour step $step', (tester) async {
      await seed(tester);
      await shoot(tester, '17_tour_$step', AppTourScreen(companyId: companyId, project: mainSite, initialStep: step));
    });
  }
}

const _assistantSays = {
  AppLanguage.en: 'Sure, Ravi. Here it is for Kompally Villa. Tap Save and it is in the money book.',
  AppLanguage.hi: 'ज़रूर, रवि। कोमपल्ली विला के लिए यह रहा। सेव दबाइए, खाते में जुड़ जाएगा।',
  AppLanguage.te: 'సరే రవి. కొంపల్లి విల్లాకు ఇదిగో. సేవ్ నొక్కండి, లెక్కలో చేరిపోతుంది.',
};

const _assistantAsk = {
  AppLanguage.en: 'Add ₹5,000 spent on cement at Kompally',
  AppLanguage.hi: 'कोमपल्ली में सीमेंट पर ₹5,000 खर्च जोड़ो',
  AppLanguage.te: 'కొంపల్లి సైట్‌లో సిమెంట్‌కు ₹5,000 ఖర్చు రాయి',
};

/// Budgets, spending, suppliers, stock, machines, checks and a week of
/// labour, so every screen has something true-looking to show.
Future<void> _seedBusiness(
    AppDatabase db, String companyId, String userId, Map<String, String> sites, DateTime now) async {
  final today = DateTime(now.year, now.month, now.day);
  DateTime d(int days) => today.add(Duration(days: days));
  String iso(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  final kompally = sites['Kompally Villa, Block B']!;
  final miyapur = sites['Miyapur Apartments, Tower 2']!;
  final gachibowli = sites['Gachibowli Office Fit-out']!;
  final shamshabad = sites['Shamshabad Warehouse']!;

  // A priced BOQ per site: one RCC line and one brick work line.
  for (final (site, rccM3, brickM3) in [
    (kompally, 180.0, 160.0),
    (miyapur, 90.0, 60.0),
    (gachibowli, 50.0, 30.0),
    (shamshabad, 260.0, 140.0),
  ]) {
    final est = await db.estimationDao.create(EstimationsCompanion.insert(
      id: _uuid.v4(), projectId: site, name: 'Main BOQ', status: const Value('final'), createdBy: userId));
    for (final (i, name, qty, rate) in [(0, 'RCC M25', rccM3, 7200.0), (1, 'Brick work in CM 1:6', brickM3, 5400.0)]) {
      final head = await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
        id: _uuid.v4(),
        estimationId: est.id,
        name: name,
        calculationType: calcVolume,
        rawUnit: 'cum',
        billingUnit: 'cum',
        ratePerUnit: Value(rate),
        sortOrder: Value(i),
      ));
      await db.estimationDao.addMeasurement(MeasurementEntriesCompanion.insert(
        id: _uuid.v4(), costHeadId: head.id, description: 'As per drawings', length: Value(qty), width: const Value(1), depth: const Value(1)));
    }
  }

  // Spending: Miyapur close to its budget, Gachibowli over it.
  for (final (site, material, qty, unit, amount, daysAgo) in [
    (kompally, 'Sand (river)', 6.0, 'loads', 54000.0, -4),
    (kompally, 'Red bricks', 8000.0, 'nos', 64000.0, -3),
    (miyapur, 'Cement (OPC 53)', 900.0, 'bags', 351000.0, -20),
    (miyapur, 'TMT steel 12mm', 3.4, 't', 221000.0, -15),
    (miyapur, 'Ready-mix M25', 60.0, 'cum', 330000.0, -8),
    (gachibowli, 'Gypsum boards', 1200.0, 'sheets', 312000.0, -12),
    (gachibowli, 'Vitrified tiles 2x2', 3800.0, 'sqft', 228000.0, -6),
  ]) {
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
      id: _uuid.v4(), projectId: site, materialName: material, quantity: qty, unit: Value(unit), amount: amount,
      receivedBy: userId, receivedOn: d(daysAgo)));
  }
  for (final (material, qty, unit, daysAgo) in [
    ('Cement (OPC 53)', 32.0, 'bags', -2),
    ('TMT steel 12mm', 0.7, 't', -3),
    ('Red bricks', 3500.0, 'nos', -1),
    ('Sand (river)', 2.0, 'loads', -1),
  ]) {
    await db.materialDao.recordUsage(MaterialUsageCompanion.insert(
      id: _uuid.v4(), projectId: kompally, materialName: material, quantity: qty, unit: Value(unit),
      recordedBy: userId, usedOn: d(daysAgo)));
  }
  for (final (site, category, amount, daysAgo, note) in [
    (kompally, 'Machinery', 6500.0, -2, 'JCB, 5 hours'),
    (kompally, 'Fuel', 2200.0, -1, 'Diesel for mixer'),
    (miyapur, 'Labour', 38000.0, -1, 'Weekly wages'),
    (gachibowli, 'Labour', 26000.0, -1, 'Weekly wages'),
  ]) {
    await db.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(), projectId: site, category: category, amount: amount, incurredOn: iso(d(daysAgo)),
      recordedBy: userId, note: Value(note)));
  }
  await db.paymentDao.create(PaymentsReceivedCompanion.insert(
    id: _uuid.v4(), projectId: kompally, amount: 450000, receivedOn: d(-5), fromParty: 'Mr. Reddy', mode: 'upi',
    recordedBy: userId, note: const Value('Running bill 1')));

  for (final (name, phone, category) in [
    ('Balaji Cement Traders', '98480 12345', 'Cement'),
    ('Sri Venkateswara Steels', '99490 67890', 'Steel'),
    ('Kaveri Sand Suppliers', '90000 24680', 'Sand and aggregate'),
  ]) {
    await db.supplierDao.create(SuppliersCompanion.insert(
      id: _uuid.v4(), companyId: companyId, name: name, contactPhone: Value(phone), category: Value(category)));
  }

  for (final (name, type, status, rate) in [
    ('Concrete mixer (1 bag)', 'Mixer', 'in_use', 1200.0),
    ('JCB 3DX', 'Excavator', 'available', 1300.0),
    ('Needle vibrator', 'Vibrator', 'in_use', 300.0),
  ]) {
    await db.equipmentDao.create(EquipmentCompanion.insert(
      id: _uuid.v4(), projectId: kompally, name: name, equipmentType: Value(type), status: Value(status),
      dailyRate: Value(rate)));
  }

  for (final (title, type, status, result, items) in [
    ('Plinth beam reinforcement check', 'structural', 'completed', 'pass',
        ['Bar sizes as per drawing', 'Cover blocks 40 mm', 'Lap lengths 50d', 'Stirrup spacing 150 mm']),
    ('Weekly site safety walk', 'safety', 'in_progress', null,
        ['Helmets and shoes on everyone', 'Edge protection on first floor', 'First-aid box stocked']),
    ('Column shuttering before pour', 'quality', 'open', null,
        ['Plumb checked both ways', 'Shutter oil applied', 'Props tight']),
  ]) {
    final ins = await db.inspectionDao.create(InspectionsCompanion.insert(
      id: _uuid.v4(), projectId: kompally, title: title, inspectionType: type, status: Value(status),
      scheduledDate: Value(d(status == 'open' ? 1 : -2)), overallResult: Value(result),
      completedDate: Value(status == 'completed' ? d(-2) : null)));
    for (final (i, item) in items.indexed) {
      await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
        id: _uuid.v4(), inspectionId: ins.id, itemDescription: item, sortOrder: Value(i),
        status: Value(status == 'completed' || (status == 'in_progress' && i < 2) ? 'pass' : 'pending')));
    }
  }

  // Older deliveries still unpaid at the planned warehouse site, so "who you owe" has ageing.
  for (final (material, qty, unit, amount, daysAgo) in [
    ('Sand (river)', 8.0, 'loads', 72000.0, -95),
    ('TMT steel 16mm', 1.2, 't', 84000.0, -64),
    ('Cement (OPC 53)', 150.0, 'bags', 58500.0, -38),
  ]) {
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
      id: _uuid.v4(), projectId: shamshabad, materialName: material, quantity: qty, unit: Value(unit), amount: amount,
      receivedBy: userId, receivedOn: d(daysAgo)));
  }
  // Waiting for the owner: a purchase and a budget overrun.
  await db.approvalDao.create(ApprovalsCompanion.insert(
    id: _uuid.v4(), projectId: Value(kompally), entityType: 'purchase_request', entityId: _uuid.v4(),
    requestedBy: userId, decisionNote: const Value('40 bags cement (OPC 53) for column casting, \u20b915,600')));
  await raiseBudgetOverrunApproval(db, gachibowli, 26000, requestedBy: userId);

  // Today on the other sites: a gang on each, a report from Miyapur, and spending.
  for (final (site, names) in [
    (miyapur, ['Suresh', 'Mallesh', 'Anjali', 'Raju', 'Venkat', 'Lakshmi']),
    (gachibowli, ['Imran', 'Prakash', 'Sunitha']),
  ]) {
    for (final n in names) {
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
          id: _uuid.v4(), projectId: site, workerName: n, recordedBy: userId,
          punchIn: today.add(const Duration(hours: 9))));
    }
  }
  await db.dprDao.create(DprEntriesCompanion.insert(
      id: _uuid.v4(), projectId: miyapur, createdBy: userId, entryDate: today.add(const Duration(hours: 17)),
      workSummary: '5th floor slab shuttering done, steel tying 60% complete. Pour planned for Thursday.',
      manpowerCount: const Value(6), weather: const Value('Sunny')));
  await db.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(), projectId: miyapur, category: 'Material', amount: 18500, incurredOn: iso(today),
      recordedBy: userId, note: const Value('Binding wire and cover blocks')));
  await db.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(), projectId: kompally, category: 'Fuel', amount: 1800, incurredOn: iso(today),
      recordedBy: userId, note: const Value('Diesel for mixer')));

  // The rest of this week's labour at Kompally, punched in and out.
  final workers = await db.workerDao.forProject(kompally);
  for (var day = -6; day <= -2; day++) {
    if (d(day).weekday == DateTime.sunday) continue;
    for (final w in workers) {
      await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
        id: _uuid.v4(), projectId: kompally, workerName: w.name, workerId: Value(w.id), recordedBy: userId,
        punchIn: d(day).add(const Duration(hours: 9)),
        punchOut: Value(d(day).add(Duration(hours: 17, minutes: w.name == 'Ramesh' ? 30 : 0)))));
    }
  }
  // Every rupee goes to a BOQ line (bricks, tiles and boards to brick work, the rest
  // to RCC), and every delivery to its supplier.
  final supplierFor = {
    for (final s in await db.supplierDao.forCompany(companyId)) s.category ?? '': s.id,
  };
  await db.customStatement(
      "UPDATE material_receipts SET supplier_id = ? WHERE material_name LIKE 'Cement%' OR material_name LIKE 'Ready-mix%'",
      [supplierFor['Cement']]);
  await db.customStatement(
      "UPDATE material_receipts SET supplier_id = ? WHERE material_name LIKE 'TMT%'", [supplierFor['Steel']]);
  await db.customStatement(
      "UPDATE material_receipts SET supplier_id = ? WHERE material_name LIKE 'Sand%'", [supplierFor['Sand and aggregate']]);
  for (final site in sites.values) {
    final heads = await db.customSelect(
        'SELECT h.id, h.name FROM cost_heads h JOIN estimations e ON e.id = h.estimation_id WHERE e.project_id = ?',
        variables: [Variable.withString(site)]).get();
    String head(String prefix) => heads.firstWhere((r) => r.read<String>('name').startsWith(prefix)).read<String>('id');
    final rcc = head('RCC'), brick = head('Brick');
    await db.customStatement(
        "UPDATE material_receipts SET cost_head_id = CASE WHEN material_name LIKE '%brick%' OR material_name LIKE '%tile%' "
        "OR material_name LIKE '%board%' OR material_name LIKE '%block%' THEN ? ELSE ? END "
        'WHERE project_id = ? AND cost_head_id IS NULL',
        [brick, rcc, site]);
    await db.customStatement(
        'UPDATE site_expenses SET cost_head_id = ? WHERE project_id = ? AND cost_head_id IS NULL', [rcc, site]);
  }

}
