/// Bug hunt on the schedule and drawing screens: a link two phones added
/// offline, a drawing whose new revision has fewer pages, and Telugu on a
/// 320dp phone.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/drawing_sheet_screen.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_screens.dart';
import 'package:fieldos_mobile/features/schedule/gantt_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

Uint8List _png() => img.encodePng(img.Image(width: 8, height: 6));

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));
  final now = DateTime(2026, 11, 10, 9);

  Future<(ProviderContainer, AppDatabase, Project, String)> seeded(WidgetTester tester, {List<Override> extra = const []}) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      cloudSyncClientProvider.overrideWith((ref) {
        final c = SupabaseClient('http://localhost:1', 'anon',
            authOptions: const AuthClientOptions(autoRefreshToken: false, authFlowType: AuthFlowType.implicit));
        ref.onDispose(c.dispose);
        return c;
      }),
      ...extra,
    ]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    late Project site;
    late String me;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
      me = container.read(sessionProvider).user!.id;
      site = await db.projectDao.create(ProjectsCompanion.insert(
          id: const Uuid().v4(), companyId: container.read(sessionProvider).activeCompany!.id, name: 'Kompally Villas',
          status: const Value('active')));
    });
    return (container, db, site, me);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, Widget home, AppLanguage lang) async {
    await tester.runAsync(() async {
      final settings = container.read(appDatabaseProvider).settingsDao;
      await settings.set(languageSettingKey, lang.code);
      await settings.set(screensInLanguageKey, '1');
    });
    setCurrentLanguage(lang);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        locale: lang.locale,
        supportedLocales: [for (final l in AppLanguage.offered) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    ));
    await settle(tester);
  }

  testWidgets('removing a link two phones both added takes it off the chart (Telugu, small phone)', (tester) async {
    final (container, db, site, me) = await seeded(tester);
    late Task footing, columns;
    await tester.runAsync(() async {
      footing = await db.taskDao.create(TasksCompanion.insert(
          id: const Uuid().v4(), projectId: site.id, title: 'Footing concrete',
          startDate: Value(DateTime(2026, 11, 5)), dueDate: Value(DateTime(2026, 11, 9))));
      columns = await db.taskDao.create(TasksCompanion.insert(
          id: const Uuid().v4(), projectId: site.id, title: 'Ground floor columns',
          startDate: Value(DateTime(2026, 11, 10)), dueDate: Value(DateTime(2026, 11, 14))));
      // The same link, added on two phones offline and synced.
      for (var i = 0; i < 2; i++) {
        await db.siteExecutionDao.addConstraint(
            projectId: site.id, taskId: columns.id, kind: 'predecessor', description: footing.title, by: me, linkId: footing.id);
      }
    });
    await pump(tester, container, GanttScreen(project: site, now: now), AppLanguage.te);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(Key('gantt-row-${columns.id}')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(Key('gantt-unlink-${footing.id}')));
    await settle(tester);
    final rows = (await tester.runAsync(() => db.siteExecutionDao.constraintsFor(site.id)))!;
    expect(rows.where((c) => c.clearedAt == null), isEmpty, reason: 'both copies cleared');

    await tester.tap(find.byKey(Key('gantt-row-${columns.id}')));
    await settle(tester);
    expect(find.text(tr('Nothing linked.')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new revision with fewer pages opens on its first page', (tester) async {
    final dir = Directory.systemTemp.createTempSync('hunt_pages');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = File('${dir.path}/sheet.png')..writeAsBytesSync(_png());
    final asked = <(String, int)>[];
    final pageCount = <String, int>{};
    final (container, db, site, me) = await seeded(tester, extra: [
      sheetPageLoaderProvider.overrideWithValue((r, page) async {
        asked.add((r.rev, page));
        final pages = pageCount[r.id]!;
        if (page >= pages) throw StateError('no page $page');
        return SheetPage(image, const Size(800, 600), pages);
      }),
    ]);
    late Drawing dr;
    await tester.runAsync(() async {
      final x = db.siteExecutionDao;
      dr = await x.addDrawing(projectId: site.id, number: 'A-101', title: 'Ground floor plan', by: me);
      final r1 = await x.addRevision(drawingId: dr.id, rev: 'R1', filePath: '${dir.path}/r1.pdf', by: me, now: DateTime(2026, 11, 1));
      pageCount[r1.id] = 3;
      await x.decideRevision(r1.id, approve: true, by: me, now: DateTime(2026, 11, 1));
    });
    await pump(tester, container, DrawingSheetScreen(project: site, drawingId: dr.id), AppLanguage.te);
    await tester.tap(find.byTooltip(tr('Next page')));
    await settle(tester);
    await tester.tap(find.byTooltip(tr('Next page')));
    await settle(tester);
    expect(asked.last, ('R1', 2));

    // R2 (one page) is approved: the screen moves to it.
    await tester.runAsync(() async {
      final x = db.siteExecutionDao;
      final r2 = await x.addRevision(drawingId: dr.id, rev: 'R2', filePath: '${dir.path}/r2.pdf', by: me, now: DateTime(2026, 11, 5));
      pageCount[r2.id] = 1;
      await x.decideRevision(r2.id, approve: true, by: me, now: DateTime(2026, 11, 5));
    });
    container.invalidate(executionDataProvider(site.id));
    await settle(tester);
    expect(find.text('A-101 R2'), findsOneWidget);
    expect(asked.last, ('R2', 0));
    expect(find.text(tr('The drawing could not be shown')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final tab in [0, 1, 2, 3, 4, 5]) {
    testWidgets('site execution tab $tab in Telugu on a 320dp phone, long words and a submittal on round 3', (tester) async {
      final (container, db, site, me) = await seeded(tester);
      await tester.runAsync(() async {
        final x = db.siteExecutionDao;
        final today = DateTime.now();
        final slab = await db.taskDao.create(TasksCompanion.insert(
            id: const Uuid().v4(), projectId: site.id, title: 'స్లాబ్ కాస్టింగ్, మూడవ అంతస్తు, బ్లాక్ ఏ ' * 3,
            startDate: Value(today.add(const Duration(days: 1))), dueDate: Value(today.add(const Duration(days: 2)))));
        await x.addConstraint(projectId: site.id, taskId: slab.id, kind: 'equipment', description: 'టవర్ క్రేన్ ' * 10, by: me,
            needBy: '2020-01-01');
        final dr = await x.addDrawing(projectId: site.id, number: 'S-12/REV-LONG-NUMBER-0001', title: 'మూడవ అంతస్తు బీమ్‌లు ' * 6,
            discipline: 'structural', by: me);
        await x.addRevision(drawingId: dr.id, rev: 'R0', filePath: '/nowhere/s12.jpg', by: me);
        await x.raiseRfi(projectId: site.id, question: 'బీమ్ లోతు ఎంత? ' * 12, by: me, taskId: slab.id, dueOn: '2020-01-01');
        await x.raiseDefect(projectId: site.id, description: 'కిటికీ పైన పగులు ' * 10, severity: 'critical', by: me, dueOn: '2020-01-01');
        await x.addUnit(projectId: site.id, block: 'బ్లాక్ ఏ', floor: 'మూడవ', name: 'ఫ్లాట్ 304 ' * 4, by: me, checklist: ['తాళాలు ' * 8]);
        var sub = await x.raiseSubmittal(
            projectId: site.id, title: 'ఫ్లోర్ టైల్స్ 600 x 600 నమూనా బోర్డు ' * 3, kind: 'method_statement', fromParty: 'సబ్ కాంట్రాక్టర్ ' * 3,
            reviewer: 'ఆర్కిటెక్ట్ ' * 3, specSection: '09 30 00', requiredBy: '2020-01-01', drawingId: dr.id, by: me);
        for (var i = 0; i < 2; i++) {
          sub = await x.decideSubmittal(sub.id, status: 'revise_resubmit', note: 'రంగు మార్చండి ' * 20, by: me);
          sub = await x.resubmitSubmittal(sub.id, by: me);
        }
      });
      await pump(tester, container, SiteExecutionScreen(project: site, initialTab: tab), AppLanguage.te);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}
