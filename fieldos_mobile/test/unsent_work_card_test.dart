/// Home says so when work saved on the phone has not reached the cloud for a
/// while, and is quiet otherwise (customer review: an engineer could not tell
/// sync was failing, and the owner then saw "report not received").
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/home/unsent_work_card.dart';
import 'package:fieldos_mobile/providers.dart';

void main() {
  const companyId = 'c1';

  Future<void> queue(AppDatabase db, String id, {Duration age = Duration.zero, int retries = 0}) =>
      db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
            targetTable: 'tasks',
            recordId: id,
            operation: 'insert',
            payload: '{"id":"$id"}',
            createdAt: Value(DateTime.now().subtract(age)),
            retryCount: Value(retries),
          ));

  Future<void> pumpCard(WidgetTester tester, AppDatabase db, {required bool linked}) async {
    await tester.runAsync(() async {
      await db.settingsDao.set('cloud_linked_companies', jsonEncode(linked ? [companyId] : <String>[]));
    });
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: const Scaffold(body: UnsentWorkCard(companyId: companyId)),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
  }

  Future<void> leave(WidgetTester tester) async {
    // Dispose the card so its once-a-minute timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('nothing waiting: no card', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await pumpCard(tester, db, linked: true);
    expect(find.byKey(const Key('unsent-work-card')), findsNothing);
    await leave(tester);
  });

  testWidgets('a save a minute ago is the next sync\'s job: no card', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() => queue(db, 't1', age: const Duration(minutes: 1)));
    await pumpCard(tester, db, linked: true);
    expect(find.byKey(const Key('unsent-work-card')), findsNothing);
    await leave(tester);
  });

  testWidgets('work waiting for two hours is reported, with how many', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() async {
      await queue(db, 't1', age: const Duration(hours: 2));
      await queue(db, 't2', age: const Duration(minutes: 5));
      await queue(db, 't3');
    });
    await pumpCard(tester, db, linked: true);
    expect(find.byKey(const Key('unsent-work-card')), findsOneWidget);
    expect(find.text('3 waiting to send. They will retry.'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('a write that keeps failing is reported at once', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() => queue(db, 't1', retries: syncOutboxMaxRetries));
    await pumpCard(tester, db, linked: true);
    expect(find.text('1 waiting to send. They will retry.'), findsOneWidget);
    await leave(tester);
  });

  testWidgets('a company that was never linked to the cloud keeps its work on the phone: no card', (tester) async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    await tester.runAsync(() => queue(db, 't1', age: const Duration(days: 3)));
    await pumpCard(tester, db, linked: false);
    expect(find.byKey(const Key('unsent-work-card')), findsNothing);
    await leave(tester);
  });

  test('needsAttention: the 30 minute line, and parked work', () {
    final now = DateTime(2026, 11, 26, 12);
    UnsentWork w(int total, int parked, Duration? age) =>
        UnsentWork(total: total, parked: parked, oldest: age == null ? null : now.subtract(age));
    expect(w(0, 0, null).needsAttention(now), isFalse);
    expect(w(3, 0, const Duration(minutes: 29)).needsAttention(now), isFalse);
    expect(w(3, 0, const Duration(minutes: 30)).needsAttention(now), isTrue);
    expect(w(1, 1, const Duration(minutes: 1)).needsAttention(now), isTrue);
  });
}
