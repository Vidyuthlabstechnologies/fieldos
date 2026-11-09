import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/project/new_project_sheet.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  Future<(ProviderContainer, AppDatabase, String)> setUpCompany(WidgetTester tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      // A cloud client that never starts its refresh timer, for screens
      // that touch sync (a site opened from Home).
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
    late String companyId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
    });
    return (container, db, companyId);
  }

  Future<void> pumpApp(WidgetTester tester, ProviderContainer container, Widget home,
      {Size size = const Size(412, 915)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('a company with no projects is invited to start one', (tester) async {
    final (container, _, _) = await setUpCompany(tester);
    await pumpApp(tester, container, const HomeScreen(), size: const Size(320, 568));
    expect(find.text('Start your first project'), findsOneWidget);
    expect(find.text('Sri Sai Constructions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projects list running sites first, with their stage and no blank client line', (tester) async {
    final (container, db, companyId) = await setUpCompany(tester);
    await tester.runAsync(() async {
      for (final (name, status, client) in [
        ('Old school', 'completed', 'District office'),
        ('Tower B', 'active', ''),
        ('Clinic', 'planning', null),
      ]) {
        await db.projectDao.create(ProjectsCompanion.insert(
          id: name,
          companyId: companyId,
          name: name,
          clientName: Value(client),
          status: Value(status),
        ));
      }
    });
    // Tall enough that the picture buttons leave every project on screen.
    await pumpApp(tester, container, const HomeScreen(), size: const Size(412, 1400));
    expect(find.textContaining('Ravi'), findsOneWidget);
    expect(find.textContaining('1 active site'), findsOneWidget);
    final towerY = tester.getTopLeft(find.text('Tower B')).dy;
    final clinicY = tester.getTopLeft(find.text('Clinic')).dy;
    final schoolY = tester.getTopLeft(find.text('Old school')).dy;
    expect(towerY < clinicY && clinicY < schoolY, isTrue, reason: 'active, then planning, then completed');
    expect(find.text('Active'), findsNothing, reason: 'a running site needs no badge');
    expect(find.text('Planning'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('District office'), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'New project'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picture buttons open the running site on the right tab, or ask which site', (tester) async {
    final (container, db, companyId) = await setUpCompany(tester);
    await tester.runAsync(() async {
      for (final (name, status) in [('Tower B', 'active'), ('Clinic', 'planning')]) {
        await db.projectDao.create(ProjectsCompanion.insert(
          id: name,
          companyId: companyId,
          name: name,
          status: Value(status),
        ));
      }
    });
    await pumpApp(tester, container, const HomeScreen(), size: const Size(412, 1400));
    for (final label in ['Attendance', 'Expense', 'Daily report', 'Material']) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    // One running site: straight in, no question.
    await tester.tap(find.bySemanticsLabel('Attendance'));
    await tester.pumpAndSettle();
    expect(find.text('Which site?'), findsNothing);
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Close the site screen so its live queries stop before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a new project needs a name, and an empty client is saved as none', (tester) async {
    final (container, db, companyId) = await setUpCompany(tester);
    Project? created;
    await pumpApp(
      tester,
      container,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => created = await showNewProjectSheet(context, companyId: companyId),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create project'));
    await tester.pumpAndSettle();
    expect(find.text('Give the project a name, such as the site or building.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Project name'), '  Tower   B ');
    await tester.tap(find.text('Create project'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(created?.name, 'Tower B');
    expect(created?.clientName, isNull);
    expect(created?.status, 'active');
  });

  test('a project stage change is checked and synced', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final c = await db.companyDao.create('Co');
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: c.id, name: 'Tower'));
    final before = await db.syncOutboxDao.pendingCount();
    await db.projectDao.setStatus('p1', 'on_hold');
    expect((await db.projectDao.byId('p1'))?.status, 'on_hold');
    expect(await db.syncOutboxDao.pendingCount(), before + 1);
    expect(() => db.projectDao.setStatus('p1', 'paused'), throwsArgumentError);
  });
}
