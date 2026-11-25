/// Pre-construction: an approval is stuck when nothing moves for a week,
/// the longest wait is the bottleneck, closed approvals stay closed, a
/// phase follows the project's stage, liaison time and cost add up, GFC is
/// a drawing revision, everything is queued for the cloud; and on a small
/// phone in Hindi a manager adds an approval, moves it and logs time.
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
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/execution/pre_construction_rules.dart';
import 'package:fieldos_mobile/features/execution/pre_construction_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('approvals: stuck after a week, the longest wait is the bottleneck, closed stays closed', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.preConstructionDao;
    await expectLater(x.addApproval(projectId: 'p1', authority: 'ghmc', title: ' ', by: 'u1'), throwsA(isA<ExecutionRefused>()));
    final t0 = DateTime(2026, 11, 1);
    final permit = await x.addApproval(projectId: 'p1', authority: 'ghmc', title: ' Building permission ', by: 'u1', now: t0);
    final fire = await x.addApproval(
        projectId: 'p1', authority: 'fire', title: 'Fire NOC', by: 'u1', expectedBy: '2026-11-10', waitingOn: 'authority', now: DateTime(2026, 11, 5));
    expect(permit.title, 'Building permission');
    expect(permit.status, 'not_started');

    final now = DateTime(2026, 11, 12);
    var all = await x.approvalsFor('p1');
    var s = summariseApprovals(all, now);
    expect((s.total, s.open, s.approved), (2, 2, 0));
    expect(s.stuck, 2, reason: '11 and 7 days idle');
    expect(s.late, 1, reason: 'Fire NOC was expected by the 10th');
    expect(s.bottleneck!.id, permit.id);
    expect(s.byWaitingOn, {'us': 1, 'authority': 1});

    await expectLater(x.moveApproval(permit.id, status: 'query_raised', waitingOn: 'consultant', note: ' '), throwsA(isA<ExecutionRefused>()),
        reason: 'a query needs the authority\'s words');
    final applied = await x.moveApproval(permit.id, status: 'applied', waitingOn: 'authority', referenceNo: 'GHMC/2026/118', now: DateTime(2026, 11, 8));
    expect(applied.appliedOn, '2026-11-08');
    expect(applied.referenceNo, 'GHMC/2026/118');
    final query = await x.moveApproval(permit.id, status: 'query_raised', waitingOn: 'consultant', note: 'Setback | query', now: DateTime(2026, 11, 11));
    expect(query.waitingOn, 'consultant');
    final lines = query.history.split('\n');
    expect(lines, hasLength(2));
    final h = parseApprovalHistory(lines.last)!;
    expect((h.day, h.status, h.waitingOn, h.note), ('2026-11-11', 'query_raised', 'consultant', 'Setback | query'));
    expect(parseApprovalHistory('nope'), isNull);

    final done = await x.moveApproval(permit.id, status: 'approved', waitingOn: 'consultant', validUntil: '2026-12-01', now: DateTime(2026, 11, 20));
    expect(done.approvedOn, '2026-11-20');
    expect(done.waitingOn, 'us', reason: 'nobody is waiting once approved');
    expect(approvalDaysInProcess(done, DateTime(2026, 12, 30)), 12, reason: 'applied the 8th, approved the 20th');
    expect(approvalDaysToExpiry(done, DateTime(2026, 11, 25)), 6);
    expect(approvalExpiring(done, DateTime(2026, 11, 25)), isTrue);
    expect(approvalDaysToExpiry(done, DateTime(2026, 12, 5)), -4);
    await expectLater(x.moveApproval(permit.id, status: 'applied', waitingOn: 'us'), throwsA(isA<ExecutionRefused>()), reason: 'closed');

    all = await x.approvalsFor('p1');
    s = summariseApprovals(all, DateTime(2026, 11, 21));
    expect((s.open, s.approved, s.bottleneck!.id), (1, 1, fire.id));

    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'site_approvals') e.operation];
    expect(queued, ['insert', 'insert', 'update', 'update', 'update']);
    expect(siteExecutionProjectScoped, containsAll(['site_approvals', 'site_liaison_logs']));
    final remote = executionToRemote('site_approvals', done);
    expect(remote.keys, containsAll(['reference_no', 'waiting_on', 'applied_on', 'approved_on', 'valid_until', 'liaison_by', 'raised_by']));
    expect(executionFromRemote('site_approvals', {...remote, 'synced_at': 'x'}), isNotNull);
  });

  test('every authority, status and waiting-on has a label', () {
    for (final a in approvalAuthorities) {
      expect(authorityLabel(a), isNot(a));
    }
    for (final s in approvalStatuses) {
      expect(approvalStatusLabel(s), isNot(s));
    }
    for (final w in approvalWaitingOn) {
      expect(waitingOnLabel(w), isNot(w));
    }
    for (final p in lifecyclePhases) {
      expect(lifecyclePhaseLabel(p), isNot(p));
    }
  });

  test('a project is pre-project while planning, post-project once handed over', () {
    expect(lifecyclePhaseOf('planning'), 'pre_project');
    expect(lifecyclePhaseOf('active'), 'execution');
    expect(lifecyclePhaseOf('on_hold'), 'execution');
    expect(lifecyclePhaseOf('completed'), 'post_project');
  });

  test('liaison time and cost add up per approval and per person', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.preConstructionDao;
    await expectLater(x.logLiaison(projectId: 'p1', by: 'u1', minutes: 0), throwsA(isA<ExecutionRefused>()));
    await expectLater(x.logLiaison(projectId: 'p1', by: 'u1', minutes: 2000), throwsA(isA<ExecutionRefused>()));
    await expectLater(x.logLiaison(projectId: 'p1', by: 'u1', minutes: 30, cost: -5), throwsA(isA<ExecutionRefused>()));
    final a = await x.addApproval(projectId: 'p1', authority: 'ghmc', title: 'Permit', by: 'u1');
    await x.logLiaison(projectId: 'p1', by: 'u1', minutes: 90, person: 'Director', cost: 4500, approvalId: a.id, onDay: '2026-11-03');
    await x.logLiaison(projectId: 'p1', by: 'u1', minutes: 150, person: 'Director', cost: 7500, approvalId: a.id, onDay: '2026-11-04');
    await x.logLiaison(projectId: 'p1', by: 'u1', minutes: 60, person: 'Liaison officer', cost: 600, onDay: '2026-11-05');
    final logs = await x.liaisonFor('p1');
    expect(logs.first.onDay, '2026-11-05', reason: 'newest first');
    final t = liaisonTotal(logs);
    expect((t.minutes, t.cost, t.entries), (300, 12600.0, 3));
    expect(t.hours, 5);
    final by = liaisonByApproval(logs);
    expect(by[a.id]!.minutes, 240);
    expect(by['']!.cost, 600);
    final people = liaisonByPerson(logs);
    expect(people.first.key, 'Director');
    expect(people.first.value.cost, 12000);
    expect(durationLabel(200), '3 h 20 min');
    expect(durationLabel(45), '45 min');
    expect(durationLabel(120), '2 h');
    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'site_liaison_logs') e.operation];
    expect(queued, ['insert', 'insert', 'insert']);
  });

  test('a drawing is Good for Construction once its GFC revision is approved', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect(isGfcRevision('GFC'), isTrue);
    expect(isGfcRevision(' gfc '), isTrue);
    expect(isGfcRevision('G.F.C'), isTrue, reason: 'dots are ignored');
    expect(isGfcRevision('Rev 2'), isFalse);
    expect(revisionPresets(0), ['Rev 1', 'GFC']);
    expect(revisionPresets(2), ['Rev 3', 'GFC']);
    final x = db.siteExecutionDao;
    final dr = await x.addDrawing(projectId: 'p1', number: 'A-01', title: 'Plan', by: 'u1');
    final r1 = await x.addRevision(drawingId: dr.id, rev: 'Rev 1', filePath: '/tmp/a.png', by: 'u1');
    await x.decideRevision(r1.id, approve: true, by: 'pm', now: DateTime(2026, 11, 1));
    final g = await x.addRevision(drawingId: dr.id, rev: 'GFC', filePath: '/tmp/b.png', by: 'u1');
    var d = await _load(db);
    expect(d.hasGfc(dr.id), isFalse, reason: 'GFC waits for approval');
    await x.decideRevision(g.id, approve: true, by: 'pm', now: DateTime(2026, 11, 5));
    d = await _load(db);
    expect(d.hasGfc(dr.id), isTrue);
    expect(d.currentRevision(dr.id)!.rev, 'GFC');
  });

  testWidgets('a manager adds an approval, moves it and logs time (Hindi, small phone)', (tester) async {
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
          status: const Value('planning')));
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
        home: PreConstructionScreen(project: site),
      ),
    ));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(lifecyclePhaseLabel('pre_project')), findsOneWidget);
    expect(find.text(tr('No approvals tracked yet')), findsOneWidget);

    await tester.tap(find.text(tr('Add approval')).last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('approval-title')), 'Building permission');
    await tester.tap(find.byKey(const Key('approval-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final a = (await tester.runAsync(() => db.preConstructionDao.approvalsFor(site.id)))!.single;
    expect(a.title, 'Building permission');
    expect(find.byKey(Key('approval-${a.id}')), findsOneWidget);
    expect(find.byKey(const Key('approvals-bottleneck')), findsOneWidget);

    await tester.ensureVisible(find.byKey(Key('approval-move-${a.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('approval-move-${a.id}')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('approval-note')), 'File submitted at the counter');
    await tester.tap(find.byKey(const Key('approval-status')));
    await settle(tester);
    await tester.tap(find.text(approvalStatusLabel('applied')).last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('approval-move-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final moved = (await tester.runAsync(() => db.preConstructionDao.approvalById(a.id)))!;
    expect(moved.status, 'applied');
    expect(moved.note, 'File submitted at the counter');

    await tester.ensureVisible(find.text(tr('Liaison time and cost')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tr('Liaison time and cost')));
    await settle(tester);
    await tester.tap(find.text(tr('Log time')).last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('liaison-hours')), '2');
    await tester.enterText(find.byKey(const Key('liaison-minutes')), '30');
    await tester.enterText(find.byKey(const Key('liaison-cost')), '3500');
    await tester.tap(find.byKey(const Key('liaison-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final logs = (await tester.runAsync(() => db.preConstructionDao.liaisonFor(site.id)))!;
    expect((logs.single.minutes, logs.single.cost), (150, 3500.0));
    expect(find.byKey(const Key('liaison-total')), findsOneWidget);
  });
}

Future<ExecutionData> _load(AppDatabase db) async {
  final x = db.siteExecutionDao;
  return ExecutionData(
    projectId: 'p1',
    tasks: const [],
    constraints: const [],
    drawings: await x.drawingsFor('p1'),
    revisions: await x.revisionsFor('p1'),
    rfis: const [],
    holdPoints: const [],
    defects: const [],
    photos: const [],
    units: const [],
    checks: const [],
  );
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}
