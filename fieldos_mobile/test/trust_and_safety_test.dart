/// App lock, search and larger text.
library;

import 'package:drift/drift.dart' hide isNull, Column;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/text_size.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/search/search.dart';
import 'package:fieldos_mobile/features/search/search_screen.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

ProviderContainer _container(AppDatabase db) => ProviderContainer(
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

Future<void> _enterPin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.widgetWithText(TextButton, d));
    await tester.pump();
  }
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pumpAndSettle();
}

void main() {
  group('app lock', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('keeps only a hash of the PIN and checks it', () async {
      final lock = AppLock(db);
      expect(await lock.isOn(), isFalse);
      expect(await lock.check('0000'), isTrue, reason: 'no lock, nothing to check');
      await lock.setPin('4821');
      expect(await lock.isOn(), isTrue);
      expect(await db.settingsDao.get(appLockPinKey), isNot(contains('4821')));
      expect(await lock.check('4821'), isTrue);
      expect(await lock.check('1234'), isFalse);
      await lock.turnOff();
      expect(await lock.isOn(), isFalse);
    });

    test('a PIN is exactly four digits', () async {
      for (final bad in ['123', '12345', 'abcd', '12 4']) {
        expect(isValidPin(bad), isFalse, reason: bad);
        expect(() => AppLock(db).setPin(bad), throwsArgumentError);
      }
      expect(isValidPin('0007'), isTrue);
    });

    test('locks again only after a minute away', () {
      final t = DateTime(2026, 11, 6, 10);
      expect(shouldLockOnResume(null, t), isFalse);
      expect(shouldLockOnResume(t, t.add(const Duration(seconds: 59))), isFalse);
      expect(shouldLockOnResume(t, t.add(const Duration(minutes: 1))), isTrue);
    });
  });

  testWidgets('with the lock on, the app opens behind the PIN pad; a wrong PIN is refused', (tester) async {
    final db = AppDatabase.memory();
    final container = _container(db);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() => AppLock(db).setPin('2580'));
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFieldOsTheme(Brightness.light),
          builder: (context, child) => AppLockGate(child: child!),
          home: const Scaffold(body: Center(child: Text('Wages: secret'))),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Wages: secret').hitTestable(), findsNothing);

    await _enterPin(tester, '1111');
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    expect(find.text('Wages: secret').hitTestable(), findsNothing);

    await _enterPin(tester, '2580');
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('Wages: secret').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a lock the app shows straight away', (tester) async {
    final db = AppDatabase.memory();
    final container = _container(db);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => AppLockGate(child: child!),
          home: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Home').hitTestable(), findsOneWidget);
    expect(find.text('Enter your PIN'), findsNothing);
  });

  testWidgets('choosing a PIN asks twice and starts over when they differ', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () async => result = await askNewPin(context), child: const Text('go')),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a 4-digit PIN'), findsOneWidget);
    await _enterPin(tester, '1234');
    expect(find.text('Enter the same PIN again'), findsOneWidget);
    await _enterPin(tester, '9999');
    expect(find.text('The PINs did not match. Choose again.'), findsOneWidget);
    await _enterPin(tester, '1357');
    await _enterPin(tester, '1357');
    expect(result, '1357');
  });

  group('search', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: 'c', name: 'Kondapur villa'));
      await db.projectDao.create(ProjectsCompanion.insert(id: 'other', companyId: 'c2', name: 'Kondapur mall'));
      await db.taskDao.create(TasksCompanion.insert(id: 't1', projectId: 'p1', title: 'Plinth beam casting'));
      await db.issueDao.create(
        IssuesCompanion.insert(id: 'i1', projectId: 'p1', description: 'Beam crack near column C4'),
      );
      await db.workerDao.create(
        WorkersCompanion.insert(id: 'w1', projectId: 'p1', name: 'Ramesh', role: const Value('Mason')),
      );
      await db.dprDao.create(
        DprEntriesCompanion.insert(
          id: 'd1',
          projectId: 'p1',
          createdBy: 'u',
          entryDate: DateTime(2026, 11, 5),
          workSummary: 'Beam shuttering 60% done',
        ),
      );
      await db.supplierDao.create(SuppliersCompanion.insert(id: 's1', companyId: 'c', name: 'Sri Balaji Cement'));
    });
    tearDown(() => db.close());

    test('finds a word in tasks, issues and reports of this company only', () async {
      final hits = await searchCompany(db, 'c', 'beam');
      expect(hits.map((h) => h.kind), [SearchKind.task, SearchKind.issue, SearchKind.report]);
      expect(hits.every((h) => h.projectName == 'Kondapur villa'), isTrue);
      expect((await searchCompany(db, 'c', 'kondapur')).map((h) => h.title), ['Kondapur villa']);
    });

    test('finds workers by role, suppliers by name, ignoring case', () async {
      expect((await searchCompany(db, 'c', 'MASON')).single.title, 'Ramesh');
      expect((await searchCompany(db, 'c', 'balaji')).single.kind, SearchKind.supplier);
    });

    test('one letter finds nothing, and % or _ are taken literally', () async {
      expect(await searchCompany(db, 'c', 'b'), isEmpty);
      expect(await searchCompany(db, 'c', '%%'), isEmpty);
      expect(await searchCompany(db, 'c', '60%'), hasLength(1));
      expect(likePattern(r'a_b%c\'), r'%a\_b\%c\\%');
    });
  });

  testWidgets('a search hit opens its project on the right tab', (tester) async {
    final db = AppDatabase.memory();
    final container = _container(db);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: 'c', name: 'Kondapur villa'));
      await db.issueDao.create(IssuesCompanion.insert(id: 'i1', projectId: 'p1', description: 'Beam crack near C4'));
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFieldOsTheme(Brightness.light),
          home: const SearchScreen(companyId: 'c'),
        ),
      ),
    );
    expect(find.text('Find anything'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'crack');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.text('Beam crack near C4'), findsOneWidget);
    await tester.tap(find.text('Beam crack near C4'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    // The Issues tab is open: its list shows the issue.
    expect(find.text('Kondapur villa'), findsOneWidget);
    expect(find.text('Beam crack near C4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('larger text multiplies the phone setting and stays within 2x', () {
    expect(combinedTextScaler(TextScaler.noScaling, 'normal'), TextScaler.noScaling);
    expect(combinedTextScaler(TextScaler.noScaling, 'large').scale(10), closeTo(11.5, 1e-9));
    expect(combinedTextScaler(const TextScaler.linear(1.8), 'larger').scale(10), closeTo(20, 1e-9));
  });

  test('the text size choice is saved', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(c.dispose);
    await c.read(textSizeProvider.notifier).choose('larger');
    expect(await db.settingsDao.get(textSizeKey), 'larger');
    await c.read(textSizeProvider.notifier).choose('huge');
    expect(c.read(textSizeProvider), 'larger');
  });
}
