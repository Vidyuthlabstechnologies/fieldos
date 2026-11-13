/// The site execution screens (FOS-205 to FOS-209) on a small phone in
/// Hindi: every tab opens with real records, nothing overflows, and the
/// owner can approve a drawing and hand over a unit from the screen.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_portfolio_screen.dart';
import 'package:fieldos_mobile/features/execution/execution_screens.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  Future<(ProviderContainer, AppDatabase, Project)> seeded(WidgetTester tester) async {
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
    late Project site;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
      final s = container.read(sessionProvider);
      final me = s.user!.id;
      final companyId = s.activeCompany!.id;
      site = await db.projectDao.create(ProjectsCompanion.insert(
          id: const Uuid().v4(), companyId: companyId, name: 'Kompally Villas', status: const Value('active')));
      final now = DateTime.now();
      final slab = await db.taskDao.create(TasksCompanion.insert(
          id: const Uuid().v4(), projectId: site.id, title: 'Slab casting, 3rd floor',
          startDate: Value(now.add(const Duration(days: 2))), dueDate: Value(now.add(const Duration(days: 3)))));
      final x = db.siteExecutionDao;
      await x.addStandard(companyId: companyId, kind: 'handover_check', item: 'Keys and manuals', by: me);
      await x.addConstraint(projectId: site.id, taskId: slab.id, kind: 'material', description: '12 mm steel, 2 t', by: me);
      await x.raiseRfi(projectId: site.id, question: 'Beam B12 depth: 450 or 600?', by: me, taskId: slab.id, askedOf: 'Consultant');
      final s12 = await x.addDrawing(projectId: site.id, number: 'S-12', title: '3rd floor beams', discipline: 'structural', by: me);
      await x.addRevision(drawingId: s12.id, rev: 'R0', filePath: '/nowhere/s12.jpg', by: me);
      await x.addHoldPoint(projectId: site.id, title: 'Reinforcement check before pour', by: me, taskId: slab.id);
      final flat = await x.addUnit(projectId: site.id, block: 'A', floor: '3', name: 'Flat 304', by: me, checklist: ['Keys and manuals']);
      await x.raiseDefect(projectId: site.id, unitId: flat.id, description: 'Hairline crack above window', severity: 'major', by: me);
    });
    return (container, db, site);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, Widget home) async {
    await tester.runAsync(() async {
      final settings = container.read(appDatabaseProvider).settingsDao;
      await settings.set(languageSettingKey, AppLanguage.hi.code);
      await settings.set(screensInLanguageKey, '1');
    });
    setCurrentLanguage(AppLanguage.hi);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        locale: AppLanguage.hi.locale,
        supportedLocales: [for (final l in AppLanguage.values) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    ));
    await settle(tester);
  }

  for (final (tab, expected) in [
    (0, 'Slab casting, 3rd floor'),
    (1, 'S-12  3rd floor beams'),
    (2, 'Beam B12 depth: 450 or 600?'),
    (3, 'Hairline crack above window'),
    (4, 'Flat 304'),
  ]) {
    testWidgets('tab $tab opens in Hindi on a small phone', (tester) async {
      final (container, _, site) = await seeded(tester);
      await pump(tester, container, SiteExecutionScreen(project: site, initialTab: tab));
      expect(find.text(expected), findsWidgets);
      if (tab == 0) expect(find.text('3 का इंतज़ार'), findsOneWidget, reason: 'steel, the RFI and the hold point');
    });
  }

  testWidgets('the owner approves a drawing from its register', (tester) async {
    final (container, db, site) = await seeded(tester);
    await pump(tester, container, SiteExecutionScreen(project: site, initialTab: 1));
    await tester.tap(find.text('S-12  3rd floor beams'));
    await settle(tester);
    await tester.tap(find.text('निर्माण के लिए मंज़ूर करें'));
    await settle(tester);
    await tester.tap(find.text('सेव करें').last);
    await settle(tester);
    final rev = await tester.runAsync(() => db.siteExecutionDao.revisionsFor(site.id));
    expect(rev!.single.status, 'approved');
    expect(find.text('साइट पर'), findsOneWidget);
  });

  testWidgets('a unit with an open defect cannot be handed over from the screen', (tester) async {
    final (container, _, site) = await seeded(tester);
    await pump(tester, container, SiteExecutionScreen(project: site, initialTab: 4));
    await tester.tap(find.text('Flat 304'));
    await settle(tester);
    expect(find.textContaining('1 डिफेक्ट बंद नहीं'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.ancestor(of: find.text('सौंपें'), matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
  });

  testWidgets('the portfolio and the company standards open in Hindi', (tester) async {
    final (container, _, site) = await seeded(tester);
    final companyId = site.companyId;
    await pump(tester, container, ExecutionPortfolioScreen(companyId: companyId));
    expect(find.text('Kompally Villas'), findsOneWidget);
    expect(find.text('ध्यान चाहिए'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.rule_outlined));
    await settle(tester);
    expect(find.text('Keys and manuals'), findsOneWidget);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}
