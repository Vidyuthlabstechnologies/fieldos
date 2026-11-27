/// Days people were counted for wages with no roll-call photo go to the
/// owner's exceptions inbox, but only for a site that uses photos at all
/// (customer review: nothing flagged workers paid with no photo).
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart' hide Table;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/exceptions_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/daily/day_close_exceptions.dart';
import 'package:fieldos_mobile/l10n/language.dart';

// Friday 13 Nov 2026.
final _now = DateTime(2026, 11, 13, 10);
DateTime _day(int d) => DateTime(2026, 11, d);

late AppDatabase db;
late Project site;

Future<void> _punch(String worker, DateTime day, {String? photo}) => db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: '$worker-${day.toIso8601String()}',
      projectId: site.id,
      workerName: worker,
      workerId: Value('w-$worker'),
      recordedBy: 'sup',
      punchIn: day.add(const Duration(hours: 9)),
      photoId: Value(photo),
    ));

Future<void> _mark(String worker, DateTime day, double? units) => db.attendanceDao.setMark(
    projectId: site.id,
    workerId: 'w-$worker',
    day: '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    units: units,
    by: 'sup');

Future<List<CommercialException>> _found() async {
  final r = await SiteRecords.load(db, site);
  final actions = await db.commercialDao.exceptionActionsFor(site.id);
  return rollCallPhotoExceptions(r, actions, now: _now);
}

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(
        ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas', status: const Value('active')));
  });
  tearDown(() async {
    setCurrentLanguage(AppLanguage.en);
    await db.close();
  });

  test('a site that has never used photos is not flagged for every day', () async {
    await _punch('ramesh', _day(9));
    await _mark('suresh', _day(10), 1);
    expect(await _found(), isEmpty);
  });

  test('once photos are used, a counted day without one is flagged, and a photographed day is not', () async {
    await _punch('ramesh', _day(9), photo: 'ph-1');
    await _punch('ramesh', _day(10));
    await _mark('suresh', _day(10), 1);
    await _mark('mahesh', _day(11), 0.5);
    final found = await _found();
    expect(found.map((e) => e.key), ['no_roll_call_photo:2026-11-10', 'no_roll_call_photo:2026-11-11']);
    expect(found.first.title, contains('2 counted for wages'), reason: 'ramesh punched, suresh marked');
    expect(found.last.title, contains('1 counted for wages'));
    expect(found.every((e) => e.kind == ExceptionKind.noRollCallPhoto), isTrue);
  });

  test('one photographed punch covers the day, however many were punched without', () async {
    await _punch('ramesh', _day(9), photo: 'ph-1');
    await _punch('suresh', _day(9));
    await _punch('mahesh', _day(9));
    expect(await _found(), isEmpty);
  });

  test('marks of zero or cleared marks count nobody; a day nobody worked is not a finding', () async {
    await _punch('ramesh', _day(9), photo: 'ph-1');
    await _mark('suresh', _day(10), 0);
    await _mark('mahesh', _day(11), null);
    expect(await _found(), isEmpty);
  });

  test('today is not flagged yet, and a day older than a week is left alone', () async {
    await _punch('ramesh', _day(2), photo: 'ph-1');
    await _punch('ramesh', _day(13));
    await _punch('suresh', _day(3));
    expect(await _found(), isEmpty, reason: 'the 13th is today; the 3rd is ten days back');
  });

  test('a recorded decision clears it, until more people are counted without a photo', () async {
    await _punch('ramesh', _day(9), photo: 'ph-1');
    await _mark('suresh', _day(10), 1);
    var e = (await _found()).single;
    expect(e.isResolved, isFalse);
    await db.commercialDao.actOnException(
        projectId: site.id, exceptionKey: e.key, action: 'resolved', by: 'pm', note: 'Checked with the supervisor', fingerprint: e.fingerprint);
    e = (await _found()).single;
    expect(e.isResolved, isTrue);
    await _mark('mahesh', _day(10), 1);
    e = (await _found()).single;
    expect(e.isResolved, isFalse, reason: 'it no longer looks as it did when it was decided');
  });

  test('a finished site is left alone', () async {
    await _punch('ramesh', _day(9), photo: 'ph-1');
    await _mark('suresh', _day(10), 1);
    await db.projectDao.setStatus(site.id, 'completed');
    site = (await db.projectDao.byId(site.id))!;
    expect(await _found(), isEmpty);
  });

  testWidgets('the owner sees it in the inbox, with a follow-up but not the backup-supervisor action', (tester) async {
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(container.dispose);
    late String companyId;
    await tester.runAsync(() async {
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi Kumar', password: '123456');
      companyId = (await session.createCompany('Sri Sai Constructions')).id;
      site = await db.projectDao.create(
          ProjectsCompanion.insert(id: 'p-inbox', companyId: companyId, name: 'Narapally Villa', status: const Value('active')));
      final today = DateTime.now();
      final yesterday = DateTime(today.year, today.month, today.day - 1);
      final before = DateTime(today.year, today.month, today.day - 2);
      await _punch('ramesh', before, photo: 'ph-1');
      await _mark('suresh', yesterday, 1);
    });
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: CommercialExceptionsScreen(companyId: companyId)),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('1 counted for wages, no roll-call photo'), findsOneWidget);
    expect(find.text('Paid without a roll-call photo'), findsWidgets);
    expect(find.text('Record a follow-up'), findsOneWidget);
    expect(find.text('Assign a backup supervisor'), findsNothing, reason: 'that belongs to a missing report');
    expect(tester.takeException(), isNull);
  });
}
