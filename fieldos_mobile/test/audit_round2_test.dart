/// Audit round 2 (2026-11-14): date pickers that opened on a saved date
/// outside their range, late counts and reminders from members-only sites,
/// the server's "blocked" task status, alert ids running into reminder ids,
/// a failed checklist completing as passed, a blank transfer count taken as
/// everything, a site sending stock it does not hold, blank estimation
/// sizes saved as 0, equal quotes in no set order, and comma-typed numbers.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/date_pick.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/brief/owner_brief.dart';
import 'package:fieldos_mobile/features/brief/owner_brief_screen.dart' show todayBriefProvider;
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_widgets.dart';
import 'package:fieldos_mobile/features/estimation/estimation_screen.dart';
import 'package:fieldos_mobile/features/inspections/inspections_screen.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare.dart';
import 'package:fieldos_mobile/features/procurement/stock_view.dart';
import 'package:fieldos_mobile/features/project/tasks_tab.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/notification_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart' show notificationServiceProvider;

class _FakeNotifications extends NotificationService {
  List<PlannedReminder>? last;
  @override
  Future<void> init() async {}
  @override
  Future<void> replaceScheduled(List<PlannedReminder> plan) async => last = plan;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }
}

Future<void> _pump(WidgetTester tester, ProviderContainer container, Widget home) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: home),
  ));
  await _settle(tester);
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  group('1. date pickers', () {
    final today = DateTime(2026, 11, 14);

    test('a saved date before the range widens it; one after it too', () {
      final old = pickerBounds(DateTime(2024, 3, 5, 10), DateTime(2025, 1, 1), DateTime(2028, 1, 1));
      expect(old.initial, DateTime(2024, 3, 5));
      expect(old.first, DateTime(2024, 3, 5));
      expect(old.last, DateTime(2028, 1, 1));
      final late = pickerBounds(DateTime(2031, 1, 1), DateTime(2025, 1, 1), DateTime(2030, 1, 1));
      expect(late.last, DateTime(2031, 1, 1));
      final inside = pickerBounds(DateTime(2026, 5, 1), DateTime(2025, 1, 1), DateTime(2030, 1, 1));
      expect((inside.first, inside.last), (DateTime(2025, 1, 1), DateTime(2030, 1, 1)));
    });

    test('a range that is a rule keeps its bounds and moves the date into it', () {
      final expired = pickerBounds(DateTime(2026, 11, 1), today, today.add(const Duration(days: 90)), keepRange: true);
      expect(expired.initial, today);
      expect(expired.first, today);
      final future = pickerBounds(DateTime(2027, 6, 1), DateTime(2020), today, keepRange: true);
      expect(future.initial, today);
      expect(future.last, today);
    });

    testWidgets('an expired "Covers until" opens, and cancelling keeps the date', (tester) async {
      final db = AppDatabase.memory();
      final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      late Project p;
      late String me;
      await tester.runAsync(() async {
        final session = container.read(sessionProvider.notifier);
        await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
        final c = await session.createCompany('Sri Sai Constructions');
        me = container.read(sessionProvider).user!.id;
        p = await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: c.id, name: 'Tower B'));
      });
      final expired = dayOf(DateTime.now().subtract(const Duration(days: 20)));
      await _pump(
        tester,
        container,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCloseSetupSheet(context,
                  project: p, current: CloseSetup(backupId: me, backupUntil: expired)),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await _settle(tester);
      final shown = fmtDate(expired, short: true);
      expect(find.text(shown), findsOneWidget);
      await tester.tap(find.text('Covers until'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(shown), findsOneWidget, reason: 'cancel is not "until I change it"');
      expect(find.text('Until I change it'), findsNothing);
    });
  });

  group('2. members-only sites on home and in reminders', () {
    late AppDatabase db;
    late ProviderContainer container;
    late _FakeNotifications notifications;
    late String companyId;
    final morning = DateTime(2026, 11, 10, 7);

    setUp(() async {
      db = AppDatabase.memory();
      notifications = _FakeNotifications();
      container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        notificationServiceProvider.overrideWithValue(notifications),
      ]);
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      await session.setLocalRole(companyId, 'site_engineer');
      for (final (id, name) in [('a', 'Tower A'), ('b', 'Tower B')]) {
        await db.projectDao.create(
            ProjectsCompanion.insert(id: id, companyId: companyId, name: name, status: const Value('active')));
      }
      await db.taskDao.create(TasksCompanion.insert(
          id: 't-a', projectId: 'a', title: 'Slab', dueDate: Value(DateTime(2026, 11, 10))));
      await db.taskDao.create(TasksCompanion.insert(
          id: 't-b', projectId: 'b', title: 'Secret lift pit', dueDate: Value(DateTime(2026, 11, 10))));
      await db.taskDao.create(TasksCompanion.insert(
          id: 't-b2', projectId: 'b', title: 'Old shuttering', dueDate: Value(DateTime(2026, 11, 1))));
      await db.siteTeamDao.setMembersOnly('b', true);
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('open tasks leave out a members-only site the person is not on', () async {
      final tasks = await container.read(openTasksProvider(companyId).future);
      expect(tasks.map((t) => t.id), ['t-a']);
    });

    test("the day's brief on home leaves it out too", () async {
      final sub = container.listen(todayBriefProvider(companyId), (_, _) {});
      addTearDown(sub.close);
      final briefs = await container.read(todayBriefProvider(companyId).future);
      expect(briefs.map((b) => b.project.id), ['a']);
      final all = await buildOwnerBrief(db, companyId, day: morning, now: morning);
      expect(all, hasLength(2), reason: 'without a site list, every site');
    });

    test("the morning reminder does not name the hidden site's tasks", () async {
      await container.read(reminderSchedulerProvider).refresh(now: morning);
      final text = notifications.last!.map((r) => '${r.title} ${r.body}').join('\n');
      expect(text, contains('Slab'));
      expect(text, isNot(contains('Secret lift pit')));
      expect(text, isNot(contains('Old shuttering')));
      expect(text, isNot(contains('Tower B')));
    });
  });

  group('3. blocked tasks', () {
    test('blocked has its own label', () {
      expect(taskStatusLabels['blocked'], 'Blocked');
      setCurrentLanguage(AppLanguage.hi);
      expect(tr(taskStatusLabels['blocked']!), isNot('Blocked'));
    });

    testWidgets('the edit sheet shows and keeps a blocked status', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final t = Task(verifyRequired: false, 
          id: 't', projectId: 'p', title: 'Lift pit', status: 'blocked', createdAt: now, updatedAt: now,
          progress: 30, priority: 'normal');
      TasksCompanion? saved;
      await tester.pumpWidget(MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () async => saved = await showTaskSheet(context, existing: t), child: const Text('open')),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Blocked'), findsOneWidget);
      final seg = tester.widget<SegmentedButton<String>>(
          find.ancestor(of: find.text('Blocked'), matching: find.byType(SegmentedButton<String>)));
      expect(seg.selected, {'blocked'});
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.status.value, 'blocked');
    });

    for (final lang in [AppLanguage.en, AppLanguage.ta, AppLanguage.kn]) {
      testWidgets('four status choices fit a 320 dp phone in ${lang.name}', (tester) async {
        setCurrentLanguage(lang);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final now = DateTime.now();
        final t = Task(verifyRequired: false, 
            id: 't', projectId: 'p', title: 'Lift pit', status: 'blocked', createdAt: now, updatedAt: now,
            progress: 30, priority: 'normal');
        await tester.pumpWidget(MaterialApp(
          theme: buildFieldOsTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => showTaskSheet(context, existing: t), child: const Text('open')),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(tr('Blocked')), findsOneWidget);
      });
    }
  });

  group('4. alert ids', () {
    test('never run into the reminder range', () {
      var id = 0;
      final seen = <int>{};
      for (var i = 0; i < 3000; i++) {
        id = alertIdAfter(id);
        expect(id >= reminderIdBase && id < reminderIdBase + reminderIdCount, isFalse, reason: 'alert $i got $id');
        expect(id, greaterThan(0));
        seen.add(id);
      }
      expect(alertIdAfter(reminderIdBase - 1), 1);
    });
  });

  group('5. inspection result', () {
    test('a failed item makes the default result failed', () {
      expect(defaultInspectionResult(['pass', 'fail', 'na']), 'fail');
      expect(defaultInspectionResult(['pass', 'na', 'pending']), 'pass');
      expect(defaultInspectionResult(const []), 'pass');
    });
  });

  group('6 and 7. stock transfers', () {
    late AppDatabase db;
    late ProviderContainer container;
    late String companyId;
    late String me;
    late Store yard;

    Future<void> setUpSites() async {
      db = AppDatabase.memory();
      container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'meena', name: 'Meena', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      me = container.read(sessionProvider).user!.id;
      for (final id in ['p-1', 'p-2']) {
        await db.projectDao.create(
            ProjectsCompanion.insert(id: id, companyId: companyId, name: id, status: const Value('active')));
      }
      yard = await db.warehouseDao.addStore(companyId: companyId, name: 'Main yard', by: me);
    }

    test('7. a site cannot send more than it has on record', () async {
      await setUpSites();
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final dao = db.warehouseDao;
      Future<StockMove> send(double q, {String name = 'Cement'}) => dao.addMove(
          companyId: companyId, kind: 'transfer', materialName: name, unit: 'bags', quantity: q,
          fromProjectId: 'p-1', toProjectId: 'p-2', by: me);
      await expectLater(send(10), throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('only 0'))));
      await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
          id: 'g1', projectId: 'p-1', materialName: 'Cement', quantity: 100, unit: const Value('bags'), amount: 39000,
          receivedBy: me, receivedOn: DateTime(2026, 11, 1)));
      await db.materialDao.recordUsage(MaterialUsageCompanion.insert(
          id: 'u1', projectId: 'p-1', materialName: 'cement ', quantity: 30, unit: const Value('bags'), recordedBy: me,
          usedOn: DateTime(2026, 11, 2)));
      await expectLater(
          send(71),
          throwsA(isA<ArgumentError>()
              .having((e) => e.message, 'message', 'This site has only 70 bags on record.')));
      await send(50);
      await expectLater(send(21), throwsArgumentError, reason: '50 already sent');
      await send(20);
      // A store is still checked as before.
      await expectLater(
          dao.addMove(
              companyId: companyId, kind: 'transfer', materialName: 'Cement', unit: 'bags', quantity: 1,
              fromStoreId: yard.id, toProjectId: 'p-1', by: me),
          throwsArgumentError);
    });

    testWidgets('6. the count starts at what was sent; blank, unreadable or negative is refused; commas read',
        (tester) async {
      late StockMove m;
      await tester.runAsync(() async {
        await setUpSites();
        await db.warehouseDao.addMove(
            companyId: companyId, kind: 'inward', materialName: 'Bricks', unit: 'nos', quantity: 5000, rate: 8,
            toStoreId: yard.id, by: me);
        m = await db.warehouseDao.addMove(
            companyId: companyId, kind: 'transfer', materialName: 'Bricks', unit: 'nos', quantity: 1500,
            fromStoreId: yard.id, toProjectId: 'p-1', by: me);
      });
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      await _pump(tester, container, Scaffold(body: StockView(projectId: 'p-1', userId: me)));
      await tester.tap(find.byKey(Key('receive-${m.id}')));
      await _settle(tester);
      final field = find.byKey(const Key('receive-qty'));
      expect(tester.widget<TextField>(field).controller!.text, '1500');

      Future<String> statusAfter(String typed) async {
        await tester.enterText(field, typed);
        await tester.tap(find.byKey(const Key('receive-save')));
        await _settle(tester);
        return (await tester.runAsync(() => db.warehouseDao.moveById(m.id)))!.status;
      }

      for (final typed in ['', 'abc', '-5']) {
        expect(await statusAfter(typed), 'in_transit', reason: '"$typed" is not a count');
        expect(field, findsOneWidget, reason: 'the dialog stays open');
        expect(find.text('Enter what arrived, up to what was sent.'), findsOneWidget);
      }
      expect(await statusAfter('1,200'), 'received');
      final got = (await tester.runAsync(() => db.warehouseDao.moveById(m.id)))!;
      expect(got.receivedQty, 1200);
    });
  });

  group('8. estimation entries', () {
    test('a volume needs every size; area and count only theirs', () {
      String? vol(String l, String w, String d, [String n = '1']) =>
          measurementProblem('volume', length: l, width: w, depth: d, nos: n);
      expect(vol('10', '9', '0.75'), isNull);
      expect(vol('10', '9', ''), isNotNull, reason: 'a blank depth is not 0 cft of concrete');
      expect(vol('10', '9', '0'), isNotNull);
      expect(vol('10', '-9', '1'), isNotNull);
      expect(vol('Infinity', '9', '1'), isNotNull);
      expect(vol('10', 'NaN', '1'), isNotNull);
      expect(vol('10', '9', '1', ''), isNotNull);
      expect(vol('1,200', '9', '1'), isNull);
      expect(measurementProblem('area', length: '10', width: '12', depth: '', nos: '1'), isNull);
      expect(measurementProblem('area', length: '10', width: '', depth: '', nos: '1'), isNotNull);
      expect(measurementProblem('area', length: '10', width: '12', depth: 'abc', nos: '1'), isNotNull);
      expect(measurementProblem('count', length: '', width: '', depth: '', nos: '4'), isNull);
      expect(measurementProblem('count', length: '', width: '', depth: '', nos: '0'), isNotNull);
    });

    test('a steel entry needs its dia, nos and length', () {
      expect(steelProblem(barDia: '12', nos: '40', lengthFt: '20'), isNull);
      expect(steelProblem(barDia: '', nos: '40', lengthFt: '20'), isNotNull);
      expect(steelProblem(barDia: '12', nos: '0', lengthFt: '20'), isNotNull);
      expect(steelProblem(barDia: '12', nos: '40', lengthFt: 'Infinity'), isNotNull);
    });
  });

  group('9. equal quotes', () {
    test('tie broken by delivery days, then first received, then supplier name', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final r = await db.purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
          id: const Uuid().v4(), projectId: 'p', raisedBy: 'u', materialName: 'Cement', quantity: const Value(100)));
      Future<SupplierQuote> q(String supplier, {int? days, required DateTime at}) async =>
          (await db.supplierQuoteDao.addQuote(requestId: r.id, supplierId: supplier, rate: 370, deliveryDays: days, by: 'u'))
              .copyWith(createdAt: at);
      final t0 = DateTime(2026, 11, 10, 9);
      final slow = await q('s-slow', days: 5, at: t0);
      final fast = await q('s-fast', days: 2, at: t0.add(const Duration(hours: 3)));
      final later = await q('s-later', days: 2, at: t0.add(const Duration(hours: 5)));
      final zed = await q('s-zed', days: 2, at: t0.add(const Duration(hours: 3)));
      final names = {'s-slow': 'Balaji', 's-fast': 'Anand', 's-later': 'Lakshmi', 's-zed': 'Zenith'};
      for (final order in [
        [slow, fast, later, zed],
        [zed, later, fast, slow],
        [later, slow, zed, fast],
      ]) {
        final c = compareQuotes(r, order, DateTime(2026, 11, 11), supplierNames: names);
        expect([for (final l in c.lines) l.quote.supplierId], ['s-fast', 's-zed', 's-later', 's-slow']);
      }
    });
  });

  group('10. typed numbers', () {
    test('commas, rupee sign and spaces are read; blank, NaN and Infinity are not', () {
      expect(parseTypedNumber('1,200'), 1200);
      expect(parseTypedNumber(' ₹45,000.50 '), 45000.5);
      expect(parseTypedNumber('12,34,567'), 1234567);
      expect(parseTypedNumber(''), isNull);
      expect(parseTypedNumber('abc'), isNull);
      expect(parseTypedNumber('NaN'), isNull);
      expect(parseTypedNumber('Infinity'), isNull);
      expect(parseTypedNumber('-5'), -5);
    });
  });
}
