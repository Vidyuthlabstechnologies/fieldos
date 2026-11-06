/// The sample site: what it holds, that it never reaches the cloud (nor
/// anything later added under it), that removing it leaves real projects
/// alone, and the home screen's way in and out.
library;

import 'package:drift/drift.dart' hide isNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  final now = DateTime(2026, 11, 10, 11);

  group('with a database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<int> outboxCount() async => (await db.select(db.syncOutbox).get()).length;

    test('fills a site with tasks (one late), labour, a report, an issue, stock and money', () async {
      final p = await createSampleProject(db, companyId: 'c', userId: 'u', now: now);
      expect(p.name, sampleProjectName);
      final tasks = await db.taskDao.forProject(p.id);
      expect(tasks, hasLength(6));
      expect(tasks.where((t) => isLate(t, now)), isNotEmpty);
      expect(await db.workerDao.forProject(p.id), hasLength(5));
      expect(await db.dprDao.forProject(p.id), hasLength(1));
      expect(await db.issueDao.forProject(p.id), hasLength(1));
      expect(await db.expenseDao.forProject(p.id), hasLength(3));
      expect(await db.paymentDao.forProject(p.id), hasLength(1));
      expect(await sampleProjectId(db, 'c'), p.id);
    });

    test('a second tap gives back the same sample', () async {
      final a = await createSampleProject(db, companyId: 'c', userId: 'u', now: now);
      final b = await createSampleProject(db, companyId: 'c', userId: 'u', now: now);
      expect(b.id, a.id);
      expect((await db.projectDao.forCompany('c')).length, 1);
    });

    test('nothing about the sample is queued for the cloud, even what is added later', () async {
      final p = await createSampleProject(db, companyId: 'c', userId: 'u', now: now);
      expect(await outboxCount(), 0);

      final t = (await db.taskDao.forProject(p.id)).first;
      await db.taskDao.setProgress(t.id, 50);
      final machine = await db.equipmentDao.create(EquipmentCompanion.insert(id: 'm1', projectId: p.id, name: 'Mixer'));
      // A log points at the machine, not the project, and still stays local.
      await db.equipmentDao.addLog(
        EquipmentLogsCompanion.insert(
          id: 'l1',
          equipmentId: machine.id,
          logDate: now,
          logType: 'usage',
          createdBy: 'u',
        ),
      );
      expect(await outboxCount(), 0);

      // A real project still syncs.
      await db.projectDao.create(ProjectsCompanion.insert(id: 'real', companyId: 'c', name: 'Tower B'));
      await db.taskDao.create(TasksCompanion.insert(id: 'rt', projectId: 'real', title: 'Footing'));
      expect((await db.select(db.syncOutbox).get()).map((o) => o.recordId), ['real', 'rt']);
    });

    test('removing it deletes everything under it and leaves real projects', () async {
      await db.projectDao.create(ProjectsCompanion.insert(id: 'real', companyId: 'c', name: 'Tower B'));
      await db.taskDao.create(TasksCompanion.insert(id: 'rt', projectId: 'real', title: 'Footing'));
      final p = await createSampleProject(db, companyId: 'c', userId: 'u', now: now);
      await db.equipmentDao.create(EquipmentCompanion.insert(id: 'm1', projectId: p.id, name: 'Mixer'));
      await db.equipmentDao.addLog(
        EquipmentLogsCompanion.insert(id: 'l1', equipmentId: 'm1', logDate: now, logType: 'usage', createdBy: 'u'),
      );

      await removeSampleProject(db, 'c');

      expect((await db.projectDao.forCompany('c')).map((p) => p.id), ['real']);
      expect((await db.taskDao.forProject('real')).single.id, 'rt');
      for (final TableInfo<Table, dynamic> table in [
        db.tasks,
        db.workers,
        db.labourAttendance,
        db.dprEntries,
        db.issues,
        db.siteExpenses,
      ]) {
        final rows = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM ${table.actualTableName} WHERE project_id = ?',
              variables: [Variable(p.id)],
            )
            .getSingle();
        expect(rows.read<int>('n'), 0, reason: table.actualTableName);
      }
      expect(await db.select(db.equipmentLogs).get(), isEmpty);
      expect(await sampleProjectId(db, 'c'), isNull);
      expect(await db.syncOutboxDao.localOnlyIds(), isEmpty);

      // And a new sample can be made again afterwards.
      final again = await createSampleProject(db, companyId: 'c', userId: 'u', now: now);
      expect(again.id, isNot(p.id));
    });
  });

  testWidgets('a new company can open the sample site from home, then remove it', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      await session.createCompany('Sri Sai Constructions');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const HomeScreen()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Try a sample site first'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text(sampleProjectName), findsWidgets);
    expect(find.textContaining('stays on this phone'), findsOneWidget);
    expect(find.text('Plinth beam'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Remove').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Start your first project'), findsOneWidget);
    expect(find.text('Sample site removed'), findsOneWidget);
  });
}
