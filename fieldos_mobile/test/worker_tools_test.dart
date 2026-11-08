import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/workers/worker_tools.dart';
import 'package:fieldos_mobile/features/workers/workers_screen.dart';
import 'package:fieldos_mobile/providers.dart';

/// A gang of 30 had to be typed in one by one, the same person could be
/// added twice, and a long list had no search.
void main() {
  Worker w(String id, String name, {String? role, String? phone, String status = 'active'}) => Worker(
        id: id,
        projectId: 'p',
        name: name,
        role: role,
        phone: phone,
        dailyWage: null,
        status: status,
        createdAt: DateTime(2026, 11, 1),
      );

  final list = [
    w('1', 'Ramesh Kumar', role: 'Mason', phone: '+91 98480 12345'),
    w('2', 'Suresh', role: 'helper', phone: '9000011111'),
    w('3', 'Lakshmi', role: 'Helper', status: 'inactive'),
  ];

  test('phones match however they are written', () {
    expect(normalizePhone('+91 98480 12345'), '9848012345');
    expect(normalizePhone('098480-12345'), '9848012345');
    expect(normalizePhone(null), '');
  });

  test('a look-alike is found by phone first, then by name', () {
    expect(findDuplicate(list, name: 'Someone', phone: '09848012345')?.id, '1');
    expect(findDuplicate(list, name: '  ramesh   kumar ')?.id, '1');
    expect(findDuplicate(list, name: 'Ramesh'), isNull);
    expect(findDuplicate(list, name: 'New', phone: '12345'), isNull, reason: 'a short number is not a phone');
    expect(findDuplicate(list, name: ''), isNull);
  });

  test('search and filters', () {
    expect(filterWorkers(list, query: 'ram').map((x) => x.id), ['1']);
    expect(filterWorkers(list, query: '98480').map((x) => x.id), ['1']);
    expect(filterWorkers(list, query: 'helper').map((x) => x.id), ['2', '3']);
    expect(filterWorkers(list, role: 'HELPER', activeOnly: true).map((x) => x.id), ['2']);
    expect(rolesOf(list), ['helper', 'Mason']);
  });

  test('a pasted list becomes workers', () {
    final r = parseWorkerLines('1. Ramesh, Mason, 98480 12345, 900\n\n'
        '- Suresh\tHelper\t₹600/-\n'
        'Lakshmi; 700 per day; Helper\n'
        '   \n'
        'Raju');
    expect(r.map((x) => x.name), ['Ramesh', 'Suresh', 'Lakshmi', 'Raju']);
    expect(r[0].role, 'Mason');
    expect(r[0].phone, '98480 12345');
    expect(r[0].dailyWage, 900);
    expect(r[1].role, 'Helper');
    expect(r[1].dailyWage, 600);
    expect(r[2].dailyWage, 700);
    expect(r[2].role, 'Helper');
    expect(r[3].role, isNull);
    expect(r[3].phone, isNull);
  });

  testWidgets('add many skips people already on the list', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() => db.workerDao.create(WorkersCompanion.insert(id: 'a', projectId: 'p', name: 'Ramesh')));
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFieldOsTheme(Brightness.light),
        home: const Scaffold(body: WorkersView(projectId: 'p', userId: 'u')),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Ramesh'), findsOneWidget);

    await tester.tap(find.text('Add many'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'ramesh\nSuresh, Helper, 600\nRaju');
    await tester.tap(find.text('Add'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 workers added. Already on the list: ramesh'), findsOneWidget);
    final rows = await tester.runAsync(() => db.workerDao.forProject('p'));
    expect(rows!.map((x) => x.name), ['Raju', 'Ramesh', 'Suresh']);
    expect(rows.firstWhere((x) => x.name == 'Suresh').dailyWage, 600);
  });
}
