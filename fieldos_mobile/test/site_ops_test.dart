/// Quality tests, safety breaches and the security gate: a cube set is three
/// tests with their own due dates and required strength, the result follows
/// from the values, a breach is closed with an action, a frisk or a breath
/// reading above zero is flagged; and a guard on a small phone in Hindi logs
/// a frisk and a breath check.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/site_ops_rules.dart';
import 'package:fieldos_mobile/features/execution/site_ops_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('a cube set is 7, 14 and 28 day tests; the result follows from the values', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.siteOpsDao;
    expect(gradeStrength('M25'), 25);
    expect(gradeStrength('m 30'), 30);
    expect(gradeStrength('steel'), isNull);
    await expectLater(x.addCubeSet(projectId: 'p1', grade: 'X', castOn: '2026-11-01', by: 'u1'), throwsA(isA<ExecutionRefused>()));
    final set = await x.addCubeSet(projectId: 'p1', grade: 'M25', castOn: '2026-11-01', by: 'u1', batchNo: 'B-7', element: 'Column C4', officer: 'Anil');
    expect([for (final t in set) (t.ageDays, t.dueOn, t.requiredValue)], [(7, '2026-11-08', 16.25), (14, '2026-11-15', 22.5), (28, '2026-11-29', 21.0)]);
    expect(testResult(rule: 'min', required: 25, actual: 25), 'pass');
    expect(testResult(rule: 'min', required: 25, actual: 24.9), 'fail');
    expect(testResult(rule: 'max', required: 5, actual: 5.1), 'fail');
    expect(testResult(rule: 'min', required: 25), 'pending');

    final now = DateTime(2026, 11, 14);
    expect(qualityDueState(set[0], now), 'overdue');
    expect(qualityDueState(set[1], now), 'soon');
    expect(qualityDueState(set[2], now), 'later');
    final seven = await x.recordTest(set[0].id, actual: 17.0, by: 'q1', now: DateTime(2026, 11, 8));
    expect((seven.result, seven.testedOn, seven.testedBy), ('pass', '2026-11-08', 'q1'));
    await expectLater(x.recordTest(set[0].id, actual: 10, by: 'q1'), throwsA(isA<ExecutionRefused>()), reason: 'recorded once');
    await expectLater(x.recordTest(set[1].id, actual: -1, by: 'q1'), throwsA(isA<ExecutionRefused>()));
    final fourteen = await x.recordTest(set[1].id, actual: 20, by: 'q1');
    expect(fourteen.result, 'fail');
    final s = summariseQuality(await x.qualityFor('p1'), now);
    expect((s.passed, s.failed, s.early, s.overdue, s.soon), (1, 0, 1, 0, 0), reason: 'a 14-day miss is a warning, not a failure');
    expect(isEarlyCubeMiss(kind: 'cube', result: fourteen.result, ageDays: fourteen.ageDays), isTrue);
    expect(isEarlyCubeMiss(kind: 'cube', result: 'fail', ageDays: 28), isFalse, reason: 'the 28-day result decides');
    expect(isEarlyCubeMiss(kind: 'cube', result: 'pass', ageDays: 7), isFalse);
    expect(isEarlyCubeMiss(kind: 'paint', result: 'fail', ageDays: 7), isFalse, reason: 'only cubes have early ages');
    expect(isEarlyCubeMiss(kind: 'cube', result: 'fail'), isFalse, reason: 'no age, no excuse');
    final twentyEight = await x.recordTest(set[2].id, actual: 20.5, by: 'q1'); // under fck - 4 = 21 for M25
    expect(twentyEight.result, 'fail');
    final s2 = summariseQuality(await x.qualityFor('p1'), now);
    expect((s2.passed, s2.failed, s2.early), (1, 1, 1), reason: 'a missed 28-day cube is a real failure');

    final paint = await x.addQualityTest(projectId: 'p1', kind: 'paint', parameter: 'Dry film thickness', unit: 'micron', requiredValue: 60, by: 'u1');
    expect(paint.rule, 'min');
    await expectLater(x.addQualityTest(projectId: 'p1', kind: 'paint', parameter: ' ', requiredValue: 60, by: 'u1'), throwsA(isA<ExecutionRefused>()));
    await expectLater(x.addQualityTest(projectId: 'p1', kind: 'paint', parameter: 'x', requiredValue: 0, by: 'u1'), throwsA(isA<ExecutionRefused>()));
    for (final k in qualityKinds) {
      expect(qualityKindLabel(k), isNot(k));
    }
    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'site_quality_tests') e.operation];
    expect(queued.length, 7);
    expect(executionFromRemote('site_quality_tests', {...executionToRemote('site_quality_tests', fourteen), 'synced_at': 'x'}), isNotNull);
  });

  test('a breach is closed once, with what was done', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.siteOpsDao;
    await expectLater(x.addBreach(projectId: 'p1', department: 'civil', description: ' ', by: 'u1'), throwsA(isA<ExecutionRefused>()));
    final a = await x.addBreach(projectId: 'p1', department: 'civil', description: 'No harness at height', severity: 'critical', by: 'u1');
    await x.addBreach(projectId: 'p1', department: 'civil', description: 'No helmet', by: 'u1');
    await x.addBreach(projectId: 'p1', department: 'electrical', description: 'Open panel', by: 'u1');
    final top = breachesByDepartment(await x.breachesFor('p1')).first;
    expect((top.key, top.value), ('civil', 2));
    await expectLater(x.closeBreach(a.id, action: ' ', by: 'pm'), throwsA(isA<ExecutionRefused>()));
    final closed = await x.closeBreach(a.id, action: 'Warned, harness issued', by: 'pm');
    expect((closed.closedBy, closed.actionTaken), ('pm', 'Warned, harness issued'));
    await expectLater(x.closeBreach(a.id, action: 'again', by: 'pm'), throwsA(isA<ExecutionRefused>()));
    for (final d in safetyDepartments) {
      expect(departmentLabel(d), isNot(d));
    }
  });

  test('the gate flags a frisk that finds something and a breath reading above zero', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.siteOpsDao;
    expect(gateResult(kind: 'frisk'), 'ok');
    expect(gateResult(kind: 'frisk', item: 'Gutka'), 'flagged');
    expect(gateResult(kind: 'breath', reading: 0), 'ok');
    expect(gateResult(kind: 'breath', reading: 12.5), 'flagged');
    await expectLater(x.addGateCheck(projectId: 'p1', kind: 'punch_in', personName: ' ', by: 'g'), throwsA(isA<ExecutionRefused>()));
    await expectLater(x.addGateCheck(projectId: 'p1', kind: 'breath', personName: 'Ramu', by: 'g'), throwsA(isA<ExecutionRefused>()));
    final morning = DateTime(2026, 11, 25, 7, 30);
    await x.addGateCheck(projectId: 'p1', kind: 'punch_in', personName: 'Ramu', by: 'g', now: morning);
    await x.addGateCheck(projectId: 'p1', kind: 'punch_in', personName: 'Sita', by: 'g', now: morning.add(const Duration(minutes: 5)));
    await x.addGateCheck(projectId: 'p1', kind: 'punch_out', personName: 'ramu', by: 'g', now: morning.add(const Duration(hours: 9)));
    await x.addGateCheck(projectId: 'p1', kind: 'punch_in', personName: 'Old', by: 'g', now: DateTime(2026, 11, 24, 8));
    final f = await x.addGateCheck(projectId: 'p1', kind: 'frisk', personName: 'Kumar', item: 'Paan parag', by: 'g', now: morning);
    expect(f.result, 'flagged');
    expect(insideTheGate(await x.gateFor('p1'), DateTime(2026, 11, 25, 18)), ['Sita']);
    for (final k in gateKinds) {
      expect(gateKindLabel(k), isNot(k));
    }
    expect(SiteRole.all, containsAll([SiteRole.security, SiteRole.qualityOfficer]));
    expect(opsTabForRole(SiteRole.security), 2);
    expect(opsTabForRole(SiteRole.qualityOfficer), 0);
  });

  testWidgets('a guard logs a frisk and a breath check (Hindi, small phone)', (tester) async {
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
      site = await db.projectDao.create(ProjectsCompanion.insert(
          id: const Uuid().v4(), companyId: container.read(sessionProvider).activeCompany!.id, name: 'Tarnaka Towers',
          status: const Value('active')));
      await db.settingsDao.set(languageSettingKey, AppLanguage.hi.code);
      await db.settingsDao.set(screensInLanguageKey, '1');
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
        supportedLocales: [for (final l in AppLanguage.offered) l.locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: SiteOpsScreen(project: site, initialTab: 2),
      ),
    ));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('gate-inside')), findsOneWidget);

    await tester.tap(find.byKey(const Key('gate-frisk')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('gate-name')), 'Kumar');
    await tester.tap(find.byKey(const Key('gate-item-Gutka')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('gate-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const Key('gate-breath')));
    await tester.tap(find.byKey(const Key('gate-breath')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('gate-name')), 'Ramu');
    await tester.enterText(find.byKey(const Key('gate-reading')), '0');
    await tester.tap(find.byKey(const Key('gate-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final rows = (await tester.runAsync(() => db.siteOpsDao.gateFor(site.id)))!;
    expect(rows.map((r) => (r.kind, r.result)).toSet(), {('frisk', 'flagged'), ('breath', 'ok')});
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}
