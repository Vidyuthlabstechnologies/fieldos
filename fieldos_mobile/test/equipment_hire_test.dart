import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/equipment/hire_register.dart';
import 'package:fieldos_mobile/features/equipment/hire_register_screen.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

/// Machines by the hour, the hire register and opening stock, from
/// Onsite's Play reviews ("JCB hourly", "machinery on rent", "opening
/// stock").
EquipmentData _e(
  String id, {
  double? hourly,
  double? daily,
  bool hired = true,
  DateTime? on,
  DateTime? due,
  DateTime? back,
}) =>
    EquipmentData(
      id: id,
      projectId: 'p',
      name: id,
      status: 'in_use',
      dailyRate: daily,
      createdAt: DateTime(2026, 11),
      hourlyRate: hourly,
      ownership: hired ? 'hired' : 'own',
      hiredFrom: hired ? 'Sri Balaji Earthmovers' : null,
      hiredOn: on,
      returnDueOn: due,
      returnedOn: back,
    );

EquipmentLog _log(String equipmentId, DateTime on, double hours, {String type = 'usage'}) => EquipmentLog(
    id: '$equipmentId$on$type', equipmentId: equipmentId, logDate: on, logType: type, hoursUsed: hours, createdBy: 'u',
    createdAt: on);

void main() {
  final now = DateTime(2026, 11, 9, 15);

  group('hire money', () {
    test('a JCB at an hourly rate costs the hours logged while on hire', () {
      final jcb = _e('jcb', hourly: 1200, on: DateTime(2026, 11, 3));
      final logs = [
        _log('jcb', DateTime(2026, 11, 2), 5), // before it came: not ours to pay
        _log('jcb', DateTime(2026, 11, 3, 18), 6.5),
        _log('jcb', DateTime(2026, 11, 5), 4),
        _log('jcb', DateTime(2026, 11, 6), 3, type: 'repair'), // not working hours
        _log('other', DateTime(2026, 11, 6), 9),
      ];
      final c = hireCharge(jcb, logs, now);
      expect(c.byHour, isTrue);
      expect(c.hours, 10.5);
      expect(c.amount, 12600);
      expect(c.days, 7);
      expect(costAtHourlyRate(jcb, 2.25), 2700);
      expect(costAtHourlyRate(_e('x'), 2), isNull);
      expect(costAtHourlyRate(jcb, 0), isNull);
    });

    test('a machine without an hourly rate is charged by the day, both ends counted, up to its return', () {
      final mixer = _e('mixer', daily: 800, on: DateTime(2026, 11, 1), back: DateTime(2026, 11, 4));
      final c = hireCharge(mixer, const [], now);
      expect(c.byHour, isFalse);
      expect(c.days, 4);
      expect(c.amount, 3200);
      expect(daysOnHire(_e('x'), now), 0);
    });

    test('on hire, due soon, late and returned', () {
      expect(hireState(_e('a', on: DateTime(2026, 11, 1)), now), HireState.onHire);
      expect(hireState(_e('a', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 20)), now), HireState.onHire);
      expect(hireState(_e('a', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 11)), now), HireState.dueSoon);
      final late = _e('a', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 6));
      expect(hireState(late, now), HireState.overdue);
      expect(daysOverdue(late, now), 3);
      final back = _e('a', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 6), back: DateTime(2026, 11, 8));
      expect(hireState(back, now), HireState.returned);
      expect(daysOverdue(back, now), 2);
    });

    test('the register: late first, then by return date, returned last, own machines left out', () {
      final rows = hireRegister([
        _e('returned', on: DateTime(2026, 10, 1), back: DateTime(2026, 10, 5)),
        _e('later', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 30)),
        _e('own', hired: false),
        _e('late', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 2)),
        _e('no date', on: DateTime(2026, 11, 1)),
        _e('soon', on: DateTime(2026, 11, 1), due: DateTime(2026, 11, 10)),
      ], now);
      expect(rows.map((e) => e.id), ['late', 'soon', 'later', 'no date', 'returned']);
    });
  });

  group('on the phone and in sync', () {
    test('hire details are saved, a return can\'t come before the hire, and both go to the cloud', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final e = await db.equipmentDao.create(EquipmentCompanion.insert(
        id: 'e1',
        projectId: 'p',
        name: 'JCB 3DX',
        hourlyRate: const Value(1200),
        ownership: const Value('hired'),
        hiredFrom: const Value('Sri Balaji Earthmovers'),
        hiredOn: Value(DateTime(2026, 11, 3)),
        returnDueOn: Value(DateTime(2026, 11, 10)),
      ));
      final json = siteJson(await db.syncOutboxDao.pending());
      expect(json['hourly_rate'], 1200);
      expect(json['ownership'], 'hired');
      expect(json['hired_on'], '2026-11-03');
      expect(json['return_due_on'], '2026-11-10');
      expect(json['returned_on'], isNull);

      final back = await db.equipmentDao.markReturned(e.id, DateTime(2026, 11, 1, 10));
      expect(back.returnedOn, DateTime(2026, 11, 3)); // clamped to the hire date
      expect(back.status, 'available');
      final edited = await db.equipmentDao.edit(e.id, const EquipmentCompanion(projectId: Value('elsewhere'), name: Value('JCB')));
      expect(edited.projectId, 'p');
      expect(edited.name, 'JCB');
      expect((await db.syncOutboxDao.pending()).map((o) => o.operation), ['insert', 'update', 'update']);
    });

    test('own machines with no hourly rate send only the old columns; pulls without them keep ours', () async {
      final own = _e('own', hired: false);
      expect(equipmentToSupabaseJson(own).containsKey('ownership'), isFalse);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db.equipmentDao.create(EquipmentCompanion.insert(
          id: 'e2', projectId: 'p', name: 'Mixer', ownership: const Value('hired'), hiredOn: Value(DateTime(2026, 11, 1))));
      await db.equipmentDao.upsertFromRemote(
          equipmentFromSupabaseJson({'id': 'e2', 'project_id': 'p', 'name': 'Mixer (renamed)', 'status': 'in_use'}));
      final row = (await db.equipmentDao.forProject('p')).single;
      expect(row.name, 'Mixer (renamed)');
      expect(row.ownership, 'hired');
      expect(row.hiredOn, DateTime(2026, 11, 1));
      await db.equipmentDao.upsertFromRemote(equipmentFromSupabaseJson(
          {'id': 'e2', 'project_id': 'p', 'name': 'Mixer', 'ownership': 'hired', 'returned_on': '2026-11-05'}));
      expect((await db.equipmentDao.forProject('p')).single.returnedOn, DateTime(2026, 11, 5));
    });

    test('logs of every machine of the site, for the register', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      for (final (id, p) in [('a', 'p'), ('b', 'p'), ('c', 'other')]) {
        await db.equipmentDao.create(EquipmentCompanion.insert(id: id, projectId: p, name: id));
        await db.equipmentDao.addLog(EquipmentLogsCompanion.insert(
            id: 'l$id', equipmentId: id, logDate: DateTime(2026, 11, 5), logType: 'usage', createdBy: 'u'));
      }
      expect((await db.equipmentDao.logsForProject('p')).map((l) => l.id).toSet(), {'la', 'lb'});
    });
  });

  test('opening stock adds to the store but not to the spending', () {
    MaterialReceipt r(String id, double qty, double amount, {String? notes}) => MaterialReceipt(
        id: id, projectId: 'p', materialName: 'Cement', quantity: qty, unit: 'bags', amount: amount, receivedBy: 'u',
        receivedOn: DateTime(2026, 11, 1), createdAt: DateTime(2026, 11, 1), notes: notes);
    final lines = buildSiteStock([r('o', 40, 0, notes: openingStockNote), r('g', 100, 38000)], const []);
    expect(lines.single.received, 140);
    expect(lines.single.opening, 40);
    // A real GRN that happens to say "Opening stock" but cost money is a GRN.
    expect(isOpeningStock(r('x', 1, 50, notes: openingStockNote)), isFalse);
  });

  testWidgets('the hire register shows what is late and what the hire has cost, and marks a return', (tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    await tester.runAsync(() async {
      await db.equipmentDao.create(EquipmentCompanion.insert(
          id: 'jcb', projectId: 'p', name: 'JCB 3DX', hourlyRate: const Value(1200), ownership: const Value('hired'),
          hiredFrom: const Value('Sri Balaji'), hiredOn: Value(DateTime(2026, 11, 3)), returnDueOn: Value(DateTime(2026, 11, 6))));
      await db.equipmentDao.addLog(EquipmentLogsCompanion.insert(
          id: 'l1', equipmentId: 'jcb', logDate: DateTime(2026, 11, 4), logType: 'usage', hoursUsed: const Value(8),
          createdBy: 'u'));
      await db.equipmentDao.create(EquipmentCompanion.insert(
          id: 'mixer', projectId: 'p', name: 'Mixer', dailyRate: const Value(500), ownership: const Value('hired'),
          hiredOn: Value(DateTime(2026, 11, 8))));
      await db.equipmentDao.create(EquipmentCompanion.insert(id: 'own', projectId: 'p', name: 'Own vibrator'));
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: HireRegisterScreen(projectId: 'p', now: now)),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
    }

    await settle();
    expect(find.text('Hire so far: ₹10,600'), findsOneWidget);
    expect(find.text('8.0 h × ₹1,200 = ₹9,600'), findsOneWidget);
    expect(find.text('2 days × ₹500 = ₹1,000'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);
    expect(find.textContaining('3 days late to go back'), findsOneWidget);
    expect(find.text('Own vibrator'), findsNothing);
    expect(tester.getTopLeft(find.text('JCB 3DX')).dy, lessThan(tester.getTopLeft(find.text('Mixer')).dy));

    await tester.tap(find.byKey(const Key('return-jcb')));
    await settle();
    final jcb = (await tester.runAsync(() => db.equipmentDao.forProject('p')))!.firstWhere((e) => e.id == 'jcb');
    expect(jcb.returnedOn, DateTime(2026, 11, 9));
    expect(find.text('Returned'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> siteJson(List<SyncOutboxData> q) => jsonDecode(q.last.payload) as Map<String, dynamic>;
