/// The schedule (Gantt chart) on a small phone in Hindi and in Arabic: the
/// bars and summary show, nothing overflows, and the owner links a task to
/// the earlier work it waits for, which then pushes it later.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/schedule/gantt_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));
  final now = DateTime(2026, 11, 10, 9);

  Future<(ProviderContainer, AppDatabase, Project, Task, Task)> seeded(WidgetTester tester) async {
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
    late Task footing, columns;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
      final companyId = container.read(sessionProvider).activeCompany!.id;
      site = await db.projectDao.create(ProjectsCompanion.insert(
          id: const Uuid().v4(), companyId: companyId, name: 'Kompally Villas', status: const Value('active')));
      // Footing was due on the 9th and is still open on the 10th.
      footing = await db.taskDao.create(TasksCompanion.insert(
          id: const Uuid().v4(), projectId: site.id, title: 'Footing concrete',
          startDate: Value(DateTime(2026, 11, 5)), dueDate: Value(DateTime(2026, 11, 9))));
      columns = await db.taskDao.create(TasksCompanion.insert(
          id: const Uuid().v4(), projectId: site.id, title: 'Ground floor columns',
          startDate: Value(DateTime(2026, 11, 10)), dueDate: Value(DateTime(2026, 11, 14))));
      await db.taskDao.create(TasksCompanion.insert(id: const Uuid().v4(), projectId: site.id, title: 'Paint touch-up'));
    });
    return (container, db, site, footing, columns);
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container, Project site, AppLanguage lang) async {
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
        home: GanttScreen(project: site, now: now),
      ),
    ));
    await settle(tester);
  }

  testWidgets('Hindi: chart and summary show; linking pushes the later task', (tester) async {
    final (container, db, site, footing, columns) = await seeded(tester);
    await pump(tester, container, site, AppLanguage.hi);
    expect(tester.takeException(), isNull);
    expect(find.text(tr('Schedule')), findsOneWidget);
    expect(find.byKey(Key('gantt-row-${footing.id}')), findsOneWidget);
    expect(find.text(trf('{n} tasks have no dates and are not on the chart.', {'n': 1})), findsOneWidget);
    expect(find.text(tr('Heading to finish on time')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gantt-zoom')));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(Key('gantt-row-${columns.id}')));
    await settle(tester);
    expect(find.text(tr('Nothing linked.')), findsOneWidget);
    await tester.tap(find.byKey(const Key('gantt-link')));
    await settle(tester);
    await tester.tap(find.byKey(Key('gantt-pick-${footing.id}')));
    await settle(tester);
    expect(tester.takeException(), isNull);

    final links = await tester.runAsync(() => db.siteExecutionDao.constraintsFor(site.id));
    expect(links!.single.kind, 'predecessor');
    expect(links.single.linkId, footing.id);
    // Footing finishes today at the earliest, so columns start tomorrow and
    // end a day late: the site is now late.
    expect(find.text(trf('Heading to finish {day}, {n} days late', {'day': fmtDay(DateTime(2026, 11, 15)), 'n': 1})),
        findsOneWidget);

    // The reverse link would be a loop and is refused.
    await tester.tap(find.byKey(Key('gantt-row-${footing.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('gantt-link')));
    await settle(tester);
    await tester.tap(find.byKey(Key('gantt-pick-${columns.id}')));
    await settle(tester);
    expect(find.text(tr('That would make a loop: the other task already waits for this one.')), findsOneWidget);
    final after = await tester.runAsync(() => db.siteExecutionDao.constraintsFor(site.id));
    expect(after, hasLength(1));
  });

  testWidgets('Arabic (right to left) shows without overflow', (tester) async {
    final (container, _, site, footing, _) = await seeded(tester);
    await pump(tester, container, site, AppLanguage.ar);
    expect(tester.takeException(), isNull);
    expect(find.byKey(Key('gantt-row-${footing.id}')), findsOneWidget);
    await tester.tap(find.byKey(Key('gantt-row-${footing.id}')));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}

String fmtDay(DateTime d) => fmtDate(d, short: true);

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}
