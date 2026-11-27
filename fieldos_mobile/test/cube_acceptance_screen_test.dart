/// The Quality tab judges concrete the way IS 456:2000 asks (clauses 15.4 and
/// 16.1, Table 11): a 28-day result is the average of three cubes, and each
/// group of four samples is checked as a group (customer review: a PMC auditor
/// would not accept a single cube compared with a flat share of the grade).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/site_ops_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late Project site;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    db = AppDatabase.memory();
    container = ProviderContainer(overrides: [
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
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'anita', name: 'Anita D', password: '123456');
      await session.createCompany('Deshmukh Builders');
      site = await db.projectDao.create(ProjectsCompanion.insert(
          id: 'p-1', companyId: container.read(sessionProvider).activeCompany!.id, name: 'G+12 tower', status: const Value('active')));
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: Scaffold(body: QualityTestsTab(project: site, canWrite: true)),
      ),
    ));
    await settle(tester);
  }

  /// A pour with its 28-day cube recorded as [mean], one pour per day.
  Future<void> pour(WidgetTester tester, int day, double mean, {String grade = 'M25'}) => tester.runAsync(() async {
        final set = await db.siteOpsDao.addCubeSet(projectId: site.id, grade: grade, castOn: '2026-10-${day.toString().padLeft(2, '0')}', by: 'u1');
        await db.siteOpsDao.recordTest(set.firstWhere((t) => t.ageDays == 28).id, actual: mean, by: 'q1');
      });

  testWidgets('four good samples: the group complies and says what it needed', (tester) async {
    await open(tester);
    for (final (day, mean) in [(1, 28.0), (2, 30.0), (3, 31.0), (4, 29.5)]) {
      await pour(tester, day, mean);
    }
    await pump(tester);
    expect(find.byKey(const Key('acceptance-M25')), findsOneWidget);
    final line = tester.widget<Text>(find.byKey(const Key('acceptance-M25-1'))).data!;
    expect(line, contains('Samples 1–4'));
    expect(line, contains('Actual 29.625'), reason: 'exact, not rounded: a rounded figure could mislead right at the limit');
    expect(line, contains('Required ≥ 29'));
    expect(find.descendant(of: find.byKey(const Key('acceptance-M25')), matching: find.text('Passed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a group fails as a group although every sample is above the individual limit', (tester) async {
    await open(tester);
    for (final (day, mean) in [(1, 26.0), (2, 27.0), (3, 28.0), (4, 25.0)]) {
      await pour(tester, day, mean);
    }
    await pump(tester);
    expect(find.descendant(of: find.byKey(const Key('acceptance-M25')), matching: find.text('Failed')), findsOneWidget);
    expect(find.textContaining('Samples under the limit'), findsNothing, reason: 'each is over fck - 4 = 21');
  });

  testWidgets('a sample under fck - 4 is named, and a half-filled group says how many are in', (tester) async {
    await open(tester);
    await pour(tester, 1, 30);
    await pour(tester, 2, 20.5);
    await pump(tester);
    expect(find.textContaining('Samples under the limit of 21: 2'), findsOneWidget);
    expect(find.text('2 of 4 samples in'), findsOneWidget);
  });

  testWidgets('three cubes are averaged and kept in the note', (tester) async {
    await open(tester);
    late QualityTest t28;
    await tester.runAsync(() async {
      final set = await db.siteOpsDao.addCubeSet(projectId: site.id, grade: 'M25', castOn: '2026-10-01', by: 'u1');
      t28 = set.firstWhere((t) => t.ageDays == 28);
    });
    await pump(tester);
    await tester.tap(find.byKey(Key('test-record-${t28.id}')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('cube-0')), '27');
    await tester.enterText(find.byKey(const Key('cube-1')), '28');
    await tester.enterText(find.byKey(const Key('cube-2')), '29');
    await tester.tap(find.byKey(const Key('test-record-save')));
    await settle(tester);
    late QualityTest saved;
    await tester.runAsync(() async => saved = (await db.siteOpsDao.qualityById(t28.id))!);
    expect(saved.actualValue, 28);
    expect(saved.result, 'pass');
    expect(saved.note, '27 / 28 / 29 N/mm²');
  });

  testWidgets('a cube more than 15% from the average makes the sample invalid: nothing is recorded', (tester) async {
    await open(tester);
    late QualityTest t28;
    await tester.runAsync(() async {
      final set = await db.siteOpsDao.addCubeSet(projectId: site.id, grade: 'M25', castOn: '2026-10-01', by: 'u1');
      t28 = set.firstWhere((t) => t.ageDays == 28);
    });
    await pump(tester);
    await tester.tap(find.byKey(Key('test-record-${t28.id}')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('cube-0')), '20');
    await tester.enterText(find.byKey(const Key('cube-1')), '28');
    await tester.enterText(find.byKey(const Key('cube-2')), '29');
    await tester.tap(find.byKey(const Key('test-record-save')));
    await settle(tester);
    expect(find.textContaining('more than 15% from the average'), findsOneWidget);
    late QualityTest still;
    await tester.runAsync(() async => still = (await db.siteOpsDao.qualityById(t28.id))!);
    expect(still.result, 'pending');
  });

  testWidgets('two cubes are not a sample: enter all three, or just the average', (tester) async {
    await open(tester);
    late QualityTest t28;
    await tester.runAsync(() async {
      final set = await db.siteOpsDao.addCubeSet(projectId: site.id, grade: 'M25', castOn: '2026-10-01', by: 'u1');
      t28 = set.firstWhere((t) => t.ageDays == 28);
    });
    await pump(tester);
    await tester.tap(find.byKey(Key('test-record-${t28.id}')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('cube-0')), '27');
    await tester.enterText(find.byKey(const Key('cube-1')), '28');
    await tester.tap(find.byKey(const Key('test-record-save')));
    await settle(tester);
    expect(find.textContaining('Enter all three cubes'), findsOneWidget);
    // Leaving the cubes empty and typing the average still works.
    await tester.tap(find.byKey(Key('test-record-${t28.id}')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('test-actual')), '27.4');
    await tester.tap(find.byKey(const Key('test-record-save')));
    await settle(tester);
    late QualityTest saved;
    await tester.runAsync(() async => saved = (await db.siteOpsDao.qualityById(t28.id))!);
    expect(saved.actualValue, 27.4);
  });

  testWidgets('a 7-day cube keeps its single field: only the 28-day result is a sample of three', (tester) async {
    await open(tester);
    late QualityTest t7;
    await tester.runAsync(() async {
      final set = await db.siteOpsDao.addCubeSet(projectId: site.id, grade: 'M25', castOn: '2026-10-01', by: 'u1');
      t7 = set.firstWhere((t) => t.ageDays == 7);
    });
    await pump(tester);
    await tester.tap(find.byKey(Key('test-record-${t7.id}')));
    await settle(tester);
    expect(find.byKey(const Key('cube-0')), findsNothing);
    expect(find.byKey(const Key('test-actual')), findsOneWidget);
  });
}
