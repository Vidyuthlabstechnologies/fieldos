/// The submittals register: a task waits for a submittal's approval, a
/// review other than a plain approval needs the reviewer's words, only a
/// submittal sent back goes round again (its last review kept in history),
/// everything is queued for the cloud; and on a small phone in Hindi a
/// manager raises one and records the review.
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
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/features/execution/execution_screens.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('a task waits for the approval, reviews need words, and only a sent-back submittal goes round again', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final x = db.siteExecutionDao;
    final tiling = await db.taskDao.create(TasksCompanion.insert(id: const Uuid().v4(), projectId: 'p1', title: 'Floor tiling'));
    await expectLater(x.raiseSubmittal(projectId: 'p1', title: '  ', by: 'u1'), throwsA(isA<ExecutionRefused>()));
    final sub = await x.raiseSubmittal(
        projectId: 'p1', title: ' Floor tiles 600 x 600 ', kind: 'sample', reviewer: 'Architect', requiredBy: '2026-11-01',
        taskId: tiling.id, by: 'u1', now: DateTime(2026, 10, 20));
    expect(sub.title, 'Floor tiles 600 x 600');
    expect(sub.status, 'submitted');
    expect(sub.round, 1);

    var d = await loadExecutionData(db, 'p1');
    final waits = d.openConstraintsOf(tiling.id).single;
    expect(waits.linkId, sub.id);
    expect(waits.description, contains('Floor tiles 600 x 600'));
    expect(d.submittalNo(sub), 'SUB-1');
    expect(d.submittalOverdue(sub, DateTime(2026, 11, 2)), isTrue);
    expect(d.submittalOverdue(sub, DateTime(2026, 10, 30)), isFalse);

    await expectLater(x.decideSubmittal(sub.id, status: 'revise_resubmit', note: ' ', by: 'pm'), throwsA(isA<ExecutionRefused>()));
    await expectLater(x.resubmitSubmittal(sub.id, by: 'u1'), throwsA(isA<ExecutionRefused>()), reason: 'not sent back yet');
    final back = await x.decideSubmittal(sub.id, status: 'revise_resubmit', note: 'Show the skirting | joint detail', by: 'pm',
        now: DateTime(2026, 10, 25));
    expect(back.decidedBy, 'pm');
    await expectLater(x.decideSubmittal(sub.id, status: 'approved', by: 'pm'), throwsA(isA<ExecutionRefused>()),
        reason: 'already reviewed');
    d = await loadExecutionData(db, 'p1');
    expect(d.openConstraintsOf(tiling.id), hasLength(1), reason: 'sent back is not approved');

    final again = await x.resubmitSubmittal(back.id, by: 'u1', now: DateTime(2026, 10, 27));
    expect(again.round, 2);
    expect(again.status, 'submitted');
    expect(again.decisionNote, isNull);
    expect(again.decidedBy, isNull);
    final h = parseSubmittalHistory(again.history.split('\n').single)!;
    expect((h.round, h.status, h.decidedBy, h.day, h.note),
        (1, 'revise_resubmit', 'pm', '2026-10-25', 'Show the skirting | joint detail'));

    final ok = await x.decideSubmittal(again.id, status: 'approved', by: 'pm');
    expect(ok.decisionNote, isNull, reason: 'a plain approval needs no words');
    d = await loadExecutionData(db, 'p1');
    expect(d.openConstraintsOf(tiling.id), isEmpty, reason: 'approval clears the wait');
    expect(submittalCleared('approved_as_noted'), isTrue);
    expect(submittalCleared('rejected'), isFalse);
    expect(parseSubmittalHistory('not a line'), isNull);

    final queued = [for (final e in await db.select(db.syncOutbox).get()) if (e.targetTable == 'site_submittals') e.operation];
    expect(queued, ['insert', 'update', 'update', 'update']);
    expect(siteExecutionProjectScoped, contains('site_submittals'));
    final remote = executionToRemote('site_submittals', ok);
    expect(remote.keys, containsAll(['spec_section', 'from_party', 'required_by', 'task_id', 'decided_by', 'decided_at', 'raised_by']));
    expect(executionFromRemote('site_submittals', {...remote, 'synced_at': 'x'}), isNotNull);
    for (final k in submittalKinds) {
      expect(submittalKindLabel(k), isNot(k), reason: 'every kind has a label');
    }
  });

  testWidgets('a manager raises a submittal and records the review (Hindi, small phone)', (tester) async {
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
          id: const Uuid().v4(), companyId: container.read(sessionProvider).activeCompany!.id, name: 'Kompally Villas',
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
        home: SiteExecutionScreen(project: site, initialTab: 5),
      ),
    ));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(tr('No submittals yet')), findsOneWidget);

    await tester.tap(find.text(tr('New submittal')).last);
    await settle(tester);
    await tester.enterText(find.byKey(const Key('submittal-title')), 'Waterproofing method statement');
    await tester.tap(find.byKey(const Key('submittal-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final sub = (await tester.runAsync(() => db.siteExecutionDao.submittalsFor(site.id)))!.single;
    expect(sub.title, 'Waterproofing method statement');
    expect(find.byKey(Key('submittal-${sub.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('submittal-review-${sub.id}')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('submittal-outcome-revise_resubmit')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('submittal-note')), 'Add the membrane overlap detail');
    await tester.tap(find.byKey(const Key('submittal-review-save')));
    await settle(tester);
    expect(tester.takeException(), isNull);
    final reviewed = (await tester.runAsync(() => db.siteExecutionDao.submittalById(sub.id)))!;
    expect(reviewed.status, 'revise_resubmit');
    expect(reviewed.decisionNote, 'Add the membrane overlap detail');
    expect(find.byKey(Key('submittal-resubmit-${sub.id}')), findsOneWidget);
    expect(find.text(submittalStatusLabel('revise_resubmit')), findsWidgets);
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pumpAndSettle();
}
