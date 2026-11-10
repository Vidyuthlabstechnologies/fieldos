/// The RERA quarterly progress pack: quarters and their due dates, each
/// floor's stage at a date, the PDF, and the owner's quarterly reminder.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/reports/rera_pack.dart';

late AppDatabase db;
late Project site;
late File photo;

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas'));
    final dir = await Directory.systemTemp.createTemp('fieldos_rera');
    addTearDown(() => dir.delete(recursive: true));
    photo = File('${dir.path}/slab.jpg')..writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));
  });
  tearDown(() => db.close());

  test('quarters, their labels and the 15 days to upload', () {
    final q = Quarter.of(DateTime(2026, 8, 20));
    expect(q.startDay, '2026-07-01');
    expect(q.endDay, '2026-09-30');
    expect(q.label, 'Jul to Sep 2026');
    expect(q.dueBy, DateTime(2026, 10, 15));
    expect(q.previous.label, 'Apr to Jun 2026');
    expect(Quarter.of(DateTime(2026, 12, 31)).next.label, 'Jan to Mar 2027');
    // Until the 15th, the report being written is the quarter just ended.
    expect(reportingQuarter(DateTime(2026, 10, 15)).label, 'Jul to Sep 2026');
    expect(reportingQuarter(DateTime(2026, 10, 16)).label, 'Oct to Dec 2026');
  });

  test('floors read the way a building does', () {
    final fs = ['3', 'Terrace', 'Ground', '1', 'Stilt', 'B1', '10', '2'];
    fs.sort(floorOrder);
    expect(fs, ['B1', 'Stilt', 'Ground', '1', '2', '3', '10', 'Terrace']);
  });

  test('each floor at a date is its latest update on or before it', () async {
    final dao = db.floorProgressDao;
    await dao.record(projectId: site.id, block: 'A', floor: 'Ground', stage: 'not_started', pct: 0, asOf: '2026-06-20', by: 'o');
    await dao.record(projectId: site.id, block: 'A', floor: '1', stage: 'not_started', pct: 0, asOf: '2026-06-20', by: 'o');
    await dao.record(projectId: site.id, block: 'A', floor: 'Ground', stage: 'slab', pct: 45, asOf: '2026-08-10', by: 'o');
    await dao.record(projectId: site.id, block: 'A', floor: 'Ground', stage: 'masonry', pct: 60, asOf: '2026-10-05', by: 'o');
    expect(() => dao.record(projectId: site.id, block: 'A', floor: '1', stage: 'roof', pct: 10, asOf: '2026-08-10', by: 'o'),
        throwsArgumentError);
    expect(() => dao.record(projectId: site.id, block: ' ', floor: '1', stage: 'slab', pct: 10, asOf: '2026-08-10', by: 'o'),
        throwsArgumentError);
    expect((await db.syncOutboxDao.pending()).where((o) => o.targetTable == 'site_floor_progress'), hasLength(4));

    final atEnd = progressAsOf(await dao.forProject(site.id), '2026-09-30');
    expect(atEnd.map((f) => '${f.floor}:${f.pct}'), ['Ground:45', '1:0']);
    expect(averagePct(atEnd), 22.5);
  });

  test('the pack takes the quarter\'s reports and photos, and makes a PDF', () async {
    final dao = db.floorProgressDao;
    await dao.record(projectId: site.id, block: 'A', floor: 'Ground', stage: 'foundation', pct: 15, asOf: '2026-06-25', by: 'o');
    await dao.record(projectId: site.id, block: 'A', floor: 'Ground', stage: 'slab', pct: 45, asOf: '2026-08-10', by: 'o');
    for (final (id, day) in [('d1', DateTime(2026, 6, 30, 18)), ('d2', DateTime(2026, 8, 10, 18)), ('d3', DateTime(2026, 9, 2, 18))]) {
      await db.dprDao.create(DprEntriesCompanion.insert(
          id: id, projectId: site.id, createdBy: 'sup', entryDate: day, workSummary: 'Slab shuttering and casting'));
    }
    await db.dprDao.addPhoto(DprPhotosCompanion.insert(id: 'ph1', dprEntryId: 'd2', photoPath: photo.path));
    await db.settingsDao.set(reraNumberKey(site.id), 'P02400001234');

    final q = Quarter.of(DateTime(2026, 8, 1));
    final pack = await buildReraPack(db, site, q);
    expect(pack.reraNumber, 'P02400001234');
    expect(pack.work.map((d) => d.id), ['d2', 'd3']);
    expect(pack.photos, hasLength(1));
    expect(pack.floors.single.pct, 45);
    expect(pack.floorsAtStart.single.pct, 15);

    final pdf = await buildReraPackPdf(pack, companyName: 'Sai Constructions', now: DateTime(2026, 10, 3));
    expect(String.fromCharCodes(pdf.take(4)), '%PDF');
  });

  test('spread keeps the first and spaces the rest', () {
    expect(spread(List.generate(24, (i) => i), 4), [0, 6, 12, 18]);
    expect(spread([1, 2], 12), [1, 2]);
  });

  test('owners are reminded when a quarter ends and 5 days before it is due', () {
    List<PlannedReminder> plan(DateTime now, {bool owner = true, List<String> sites = const ['Kompally Villas']}) =>
        planReminders(
          now: now,
          settings: const ReminderSettings(),
          runningSites: 1,
          reportedToday: true,
          openTasks: const [],
          isOwner: owner,
          reraSites: sites,
          followUps: [(name: 'Ravi', at: now)],
        ).where((r) => r.id >= reminderIdBase + 207).toList();

    final ended = plan(DateTime(2026, 9, 28, 8));
    expect(ended.map((r) => r.at), [DateTime(2026, 10, 1, 10)]);
    expect(plan(DateTime(2026, 10, 5, 8)).map((r) => r.at), [DateTime(2026, 10, 10, 10)]);
    expect(plan(DateTime(2026, 9, 28, 8), owner: false), isEmpty);
    expect(plan(DateTime(2026, 9, 28, 8), sites: const []), isEmpty);
    expect(plan(DateTime(2026, 11, 3, 8)), isEmpty);

    // Ids stay inside the reminder block and never repeat.
    final all = planReminders(
      now: DateTime(2026, 9, 28, 8),
      settings: const ReminderSettings(),
      runningSites: 1,
      reportedToday: false,
      openTasks: const [],
      isOwner: true,
      reraSites: const ['Kompally Villas'],
      followUps: [(name: 'Ravi', at: DateTime(2026, 9, 28, 8))],
      closeReminders: const [
        SiteCloseReminder(projectId: 'site-1', siteName: 'Kompally Villas', cutoffMinutes: 19 * 60, days: {0, 1, 2, 3, 4, 5, 6}),
      ],
    );
    final ids = all.map((r) => r.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids.every((id) => id >= reminderIdBase && id < reminderIdBase + reminderIdCount), isTrue);
  });
}
