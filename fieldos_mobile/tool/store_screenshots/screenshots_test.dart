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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
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
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

const _uuid = Uuid();
const _pixelRatio = 2.625; // a common 1080-wide Android phone
const _logical = Size(1080 / _pixelRatio, 2160 / _pixelRatio);

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = File(p).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  final outDir = Directory(Platform.environment['SHOTS_DIR'] ?? 'build/store_screenshots')..createSync(recursive: true);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';

  setUpAll(() async {
    await _loadFont('Inter', [
      for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/Inter-$w.otf',
    ]);
    final material = '$flutterRoot/bin/cache/artifacts/material_fonts';
    await _loadFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
    await _loadFont('Roboto', ['$material/Roboto-Regular.ttf', '$material/Roboto-Medium.ttf', '$material/Roboto-Bold.ttf']);
  });

  late AppDatabase db;
  late ProviderContainer container;
  late String companyId;
  late String userId;
  late Project mainSite;

  Future<void> seed(WidgetTester tester) async {
    db = AppDatabase.memory();
    container = ProviderContainer(overrides: [
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
          theme: buildFieldOsTheme(Brightness.light),
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
        WageSheetScreen(projectId: mainSite.id, projectName: mainSite.name, userId: userId));
  });

  testWidgets('06 stock', (tester) async {
    await seed(tester);
    await shoot(tester, '06_stock', ProjectDetailScreen(project: mainSite, initialTab: 4), before: () async {
      await tester.tap(find.text('Stock'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('12 approvals', (tester) async {
    await seed(tester);
    await shoot(tester, '12_approvals', ApprovalsScreen(companyId: companyId));
  });
}

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

  // Waiting for the owner: a purchase and a budget overrun.
  await db.approvalDao.create(ApprovalsCompanion.insert(
    id: _uuid.v4(), projectId: Value(kompally), entityType: 'purchase_request', entityId: _uuid.v4(),
    requestedBy: userId, decisionNote: const Value('40 bags cement (OPC 53) for column casting, \u20b915,600')));
  await raiseBudgetOverrunApproval(db, gachibowli, 26000, requestedBy: userId);

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
}
