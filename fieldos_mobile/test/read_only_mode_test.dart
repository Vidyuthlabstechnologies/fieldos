/// Read-only mode (lib/data/write_guard.dart) and the server's site limit
/// (supabase/migrations/20261114130000_site_limit_enforced.sql):
///  - read-only refuses every change to the person's data, with the plain
///    message, while settings and server sync still write;
///  - the banner shows on every screen while read-only;
///  - the server's site-limit refusal is recognised as permanent, with the
///    site-limit message (end to end: test/site_limit_cloud_test.dart).
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/subscription/subscription_gate.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/sync_engine.dart';

const _offlineMessage =
    'Offline for over 7 days. Connect to the internet to keep making changes. You can still view everything.';

void main() {
  group('WriteGuard', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    Future<Project> addSite(String id) => db.projectDao.create(
      ProjectsCompanion.insert(id: id, companyId: 'c1', name: 'Site $id', status: const Value('active')),
    );

    test('off: everything writes as before', () async {
      await addSite('a');
      expect(await db.projectDao.forCompany('c1'), hasLength(1));
    });

    test('read-only: changes are refused with the plain message, nothing is half-written', () async {
      await addSite('a');
      final queued = await db.syncOutboxDao.pendingCount();
      db.writeGuard.reason = ReadOnlyReason.offlineTooLong;

      Object? error;
      try {
        await addSite('b');
      } catch (e) {
        error = e;
      }
      expect(error, isA<ReadOnlyModeException>());
      expect(friendlyError(error!), _offlineMessage);
      await expectLater(db.projectDao.setStatus('a', 'completed'), throwsA(isA<ReadOnlyModeException>()));
      await expectLater(db.customStatement('DELETE FROM projects'), throwsA(isA<ReadOnlyModeException>()));
      await expectLater(db.syncOutboxDao.retryParked(), throwsA(isA<ReadOnlyModeException>()));

      // Viewing still works, and nothing changed.
      final sites = await db.projectDao.forCompany('c1');
      expect(sites.map((p) => p.id), ['a']);
      expect(sites.single.status, 'active');
      expect(await db.syncOutboxDao.pendingCount(), queued);
    });

    test('read-only: settings and server sync bookkeeping still write', () async {
      await addSite('a');
      db.writeGuard.reason = ReadOnlyReason.planEnded;
      await db.settingsDao.set('sync_cursor:u1', '42');
      expect(await db.settingsDao.get('sync_cursor:u1'), '42');
      await db.settingsDao.remove('sync_cursor:u1');

      // What the sync engine does: write the server's rows, clear sent
      // entries.
      await WriteGuard.serverSync(() async {
        await db.projectDao.upsertFromRemote(
          ProjectsCompanion.insert(id: 'from-server', companyId: 'c1', name: 'Tower B', status: const Value('active')),
        );
        await db.transaction(() async {
          for (final e in await db.syncOutboxDao.pending()) {
            await db.syncOutboxDao.markSynced(e.id);
          }
        });
      });
      expect((await db.projectDao.forCompany('c1')).map((p) => p.id), containsAll(['a', 'from-server']));
      expect(await db.syncOutboxDao.pendingCount(), 0);

      // Outside serverSync the same write is refused again.
      await expectLater(
        db.projectDao.upsertFromRemote(ProjectsCompanion.insert(id: 'x', companyId: 'c1', name: 'X')),
        throwsA(isA<ReadOnlyModeException>()),
      );

      // Back online: writes work again.
      db.writeGuard.reason = null;
      await addSite('c');
    });

    test('which statements change data', () {
      expect(WriteGuard.changesData('INSERT INTO "projects" ("id") VALUES (?)'), isTrue);
      expect(WriteGuard.changesData('insert or replace into tasks values (?)'), isTrue);
      expect(WriteGuard.changesData('UPDATE "tasks" SET "title" = ?'), isTrue);
      expect(WriteGuard.changesData('DELETE FROM "issues" WHERE id = ?'), isTrue);
      expect(WriteGuard.changesData('INSERT INTO "app_settings" ("key", "value") VALUES (?, ?)'), isFalse);
      expect(WriteGuard.changesData('DELETE FROM "app_settings" WHERE key = ?'), isFalse);
      expect(WriteGuard.changesData('SELECT * FROM projects'), isFalse);
      expect(WriteGuard.changesData('PRAGMA user_version = 40'), isFalse);
    });
  });

  testWidgets('the banner shows on every screen while read-only, and goes when it ends', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          navigatorKey: nav,
          builder: (context, child) => ReadOnlyBanner(child: child!),
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('read-only-banner')), findsNothing);

    db.writeGuard.reason = ReadOnlyReason.offlineTooLong;
    await tester.pump();
    expect(find.text(_offlineMessage), findsOneWidget);

    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('A site'))));
    await tester.pumpAndSettle();
    expect(find.text('A site'), findsOneWidget);
    expect(find.text(_offlineMessage), findsOneWidget);
    expect(tester.takeException(), isNull);

    db.writeGuard.reason = ReadOnlyReason.planEnded;
    await tester.pump();
    expect(find.textContaining('Your company plan has ended'), findsOneWidget);

    db.writeGuard.reason = null;
    await tester.pump();
    expect(find.byKey(const ValueKey('read-only-banner')), findsNothing);
  });

  testWidgets('the gate opens a company plan offline for over 7 days read-only, and recovers online', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final company = _FakeCompanyPlans(db);
    final plan = CompanyPlan(companyId: 'c1', plan: 'site_pro', siteLimit: 3, endsOn: DateTime(2099, 1, 1));
    await company.remember([plan], checkedAt: DateTime.now().subtract(const Duration(days: 10)));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        billingServiceProvider.overrideWithValue(_OfflineBilling(db)),
        companyPlanServiceProvider.overrideWithValue(company),
      ],
      child: MaterialApp(
        builder: (context, child) => ReadOnlyBanner(child: child!),
        home: const SubscriptionGate(child: Scaffold(body: Text('Home'))),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.text('Home'), findsOneWidget, reason: 'read-only still opens the app');
    expect(find.text(_offlineMessage), findsOneWidget);
    expect(db.writeGuard.readOnly, isTrue);

    // Back online: the next check (on resume, or the minute timer) lifts it.
    company.live = [plan];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(db.writeGuard.readOnly, isFalse);
    expect(find.text(_offlineMessage), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  group('the server refusing a site for the limit', () {
    test('is recognised, with its numbers, and is not transient', () {
      const e = PostgrestException(message: 'site_limit_reached: limit 3, active 3', code: 'P0001');
      final refused = siteLimitOf(e)!;
      expect(refused.limit, 3);
      expect(refused.active, 3);
      expect(siteLimitRefusal(refused), contains('covers 3 active sites, and 3 are open'));
      expect(isTransientSyncError(e), isFalse);
      expect(isAuthSyncError(e), isFalse);

      expect(siteLimitOf(const PostgrestException(message: 'site_limit_reached', code: 'P0001'))!.limit, isNull);
      expect(
        siteLimitRefusal(siteLimitOf(const PostgrestException(message: 'site_limit_reached', code: 'P0001'))!),
        'site_limit_reached',
      );
      expect(siteLimitOf(const PostgrestException(message: 'other trigger', code: 'P0001')), isNull);
      expect(siteLimitOf(const PostgrestException(message: 'site_limit_reached: x', code: '23505')), isNull);
      expect(siteLimitOf(StateError('site_limit_reached')), isNull);

      expect(
        siteLimitReasonOf('$siteLimitErrorPrefix Your company plan covers 1 active site'),
        'Your company plan covers 1 active site',
      );
      expect(siteLimitReasonOf('PostgrestException(...)'), isNull);
      expect(siteLimitReasonOf(null), isNull);
    });
  });
}


/// A store build whose store can't be reached (offline), never paid.
class _OfflineBilling extends BillingService {
  _OfflineBilling(super.db) : super(apiKey: 'test');

  @override
  Future<SubscriptionState?> current({bool fresh = false}) async => null;

  @override
  Future<DateTime?> lastPaidUntil() async => null;

  @override
  Future<VoidCallback> listen(void Function(SubscriptionState state) onChange) async => () {};
}

/// Company plans with the server offline ([live] null) or answering.
class _FakeCompanyPlans extends CompanyPlanService {
  _FakeCompanyPlans(AppDatabase db) : super(db: db, cloud: null);

  List<CompanyPlan>? live;

  @override
  Future<List<CompanyPlan>?> current() async {
    final answer = live;
    if (answer != null) await remember(answer, checkedAt: DateTime.now());
    return answer;
  }
}
