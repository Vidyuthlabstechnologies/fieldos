/// FOS-205 to FOS-209 on one phone: the two-week lookahead clears as RFIs
/// are answered, drawings approved and hold points released; only the
/// approved revision is on site; a defect is closed by someone other than
/// its fixer; a flat is handed over only when nothing is left; the
/// company's standard lists go to every site; and the portfolio report
/// counts it all.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

void main() {
  late AppDatabase db;
  late SiteExecutionDao x;
  late Company company;
  late Project site;
  late Directory files;
  const engineer = 'engineer-1';
  const pm = 'pm-1';
  const foreman = 'foreman-1';
  final now = DateTime(2026, 11, 11, 10);

  setUp(() async {
    db = AppDatabase.memory();
    x = db.siteExecutionDao;
    files = Directory.systemTemp.createTempSync('fieldos-exec-');
    company = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(
        id: const Uuid().v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
  });
  tearDown(() async {
    await db.close();
    files.deleteSync(recursive: true);
  });

  String photo(String name) => (File('${files.path}/$name.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9])).path;
  Future<Task> task(String title, DateTime start, DateTime due) => db.taskDao.create(TasksCompanion.insert(
      id: const Uuid().v4(), projectId: site.id, title: title, startDate: Value(start), dueDate: Value(due)));
  Future<ExecutionData> load() => loadExecutionData(db, site.id);

  test('the lookahead shows what each task waits for, and clears as the records do', () async {
    final slab = await task('Slab casting, 3rd floor', now.add(const Duration(days: 3)), now.add(const Duration(days: 4)));
    final far = await task('Terrace waterproofing', now.add(const Duration(days: 30)), now.add(const Duration(days: 33)));
    final late = await task('Block work, 2nd floor', now.subtract(const Duration(days: 5)), now.subtract(const Duration(days: 1)));

    final steel = await x.addConstraint(
        projectId: site.id, taskId: slab.id, kind: 'material', description: '12 mm steel, 2 t', by: engineer,
        needBy: ymd(now.subtract(const Duration(days: 1))), now: now);
    final rfi = await x.raiseRfi(
        projectId: site.id, question: 'Beam B12 depth: 450 or 600?', by: engineer, taskId: slab.id, askedOf: 'Structural consultant',
        dueOn: ymd(now.add(const Duration(days: 1))), now: now);
    final hold = await x.addHoldPoint(projectId: site.id, title: 'Reinforcement check before pour', by: engineer,
        taskId: slab.id, location: 'Block A, 3rd floor slab', now: now);

    var d = await load();
    var look = d.lookahead(now);
    expect(look.map((i) => i.task.id), [late.id, slab.id], reason: 'late work stays; work a month out does not');
    expect(look.any((i) => i.task.id == far.id), isFalse);
    final item = look.last;
    expect(item.ready, isFalse);
    expect(item.open.map((c) => c.kind), unorderedEquals(['material', 'rfi', 'hold_point']));
    expect(item.late.map((c) => c.id), [steel.id], reason: 'the steel was needed yesterday');

    await x.answerRfi(rfi.id, answer: '600 deep, see revised S-12', by: pm, now: now);
    await x.clearConstraint(steel.id, by: engineer, note: 'Delivered, GRN 118', now: now);
    d = await load();
    expect(d.lookahead(now).last.open.map((c) => c.kind), ['hold_point']);
    // The engineer can't release it here; the screen asks for the owner or
    // a PM, and the server refuses anyone else (site_execution_cycle_test).
    await x.decideHoldPoint(hold.id, release: true, by: pm, note: 'Cover blocks fixed', now: now);
    d = await load();
    expect(d.lookahead(now).last.ready, isTrue);
    await expectLater(x.decideHoldPoint(hold.id, release: true, by: pm), throwsA(isA<ExecutionRefused>()));
  });

  test('only the latest approved revision is on site; older ones stay in the register', () async {
    final s12 = await x.addDrawing(projectId: site.id, number: 'S-12', title: '3rd floor beams', discipline: 'structural', by: engineer);
    await expectLater(x.addDrawing(projectId: site.id, number: 's-12', title: 'Copy', by: engineer), throwsA(isA<ExecutionRefused>()));
    final r0 = await x.addRevision(drawingId: s12.id, rev: 'R0', filePath: photo('r0'), by: engineer, now: now);
    final t = await task('Beam shuttering', now, now.add(const Duration(days: 2)));
    await x.addConstraint(projectId: site.id, taskId: t.id, kind: 'drawing', description: 'S-12 for construction', by: engineer, linkId: s12.id);

    var d = await load();
    expect(d.currentRevision(s12.id), isNull, reason: 'nothing approved yet');
    expect(d.lookahead(now).single.ready, isFalse);
    await x.decideRevision(r0.id, approve: true, by: pm, now: now);
    final r1 = await x.addRevision(drawingId: s12.id, rev: 'R1', filePath: photo('r1'), by: engineer, note: 'B12 600 deep',
        now: now.add(const Duration(hours: 1)));
    d = await load();
    expect(d.currentRevision(s12.id)!.id, r0.id, reason: 'R1 is waiting for approval');
    expect(d.lookahead(now).single.ready, isTrue);
    await x.decideRevision(r1.id, approve: true, by: pm, now: now.add(const Duration(hours: 2)));
    d = await load();
    expect(d.currentRevision(s12.id)!.rev, 'R1');
    expect(d.isSuperseded(d.revisions.firstWhere((r) => r.id == r0.id)), isTrue);
    expect(d.revisionsOf(s12.id), hasLength(2), reason: 'the register keeps R0');
    await expectLater(x.decideRevision(r1.id, approve: false, by: pm), throwsA(isA<ExecutionRefused>()));
  });

  test('a defect is fixed with a photo and closed by someone else; a flat is handed over only when nothing is left', () async {
    await x.addStandard(companyId: company.id, kind: 'handover_check', item: 'Keys and manuals', by: pm);
    await x.addStandard(companyId: company.id, kind: 'handover_check', item: 'Meter readings noted', by: pm);
    await x.addStandard(companyId: company.id, kind: 'hold_point', item: 'Waterproofing flood test', by: pm);
    final standards = await x.standardsFor(company.id);
    final flat = await x.addUnit(
        projectId: site.id, block: 'A', floor: '3', name: 'Flat 304', by: engineer,
        checklist: [for (final s in standards) if (s.kind == 'handover_check') s.item]);
    final holds = await x.applyHoldPointStandards(
        companyId: company.id, projectId: site.id, location: 'Flat 304 toilets', unitId: flat.id, by: engineer);
    expect(holds.map((h) => h.title), ['Waterproofing flood test']);

    final defect = await x.raiseDefect(
        projectId: site.id, unitId: flat.id, location: 'Master bedroom', description: 'Hairline crack above window',
        severity: 'major', assigneeId: foreman, by: engineer, photos: [photo('crack')], now: now);
    var d = await load();
    expect(d.handoverBlockers(flat), hasLength(3));
    expect(d.unitState(flat), UnitState.notReady);
    await expectLater(
        x.handOver(flat.id, handedTo: 'Mr. Reddy', by: pm, blockers: d.handoverBlockers(flat)), throwsA(isA<ExecutionRefused>()));

    await expectLater(x.markFixed(defect.id, by: foreman), throwsA(isA<ExecutionRefused>()), reason: 'a fix needs a photo');
    await x.markFixed(defect.id, by: foreman, note: 'Filled and painted', photos: [photo('fixed')], now: now);
    await expectLater(x.verifyFix(defect.id, accept: true, by: foreman), throwsA(isA<ExecutionRefused>()),
        reason: 'the fixer does not check their own fix');
    await x.verifyFix(defect.id, accept: false, by: engineer, note: 'Crack shows through paint');
    d = await load();
    expect(d.defects.single.status, 'open');
    expect(d.defects.single.reopenCount, 1);
    await x.markFixed(defect.id, by: foreman, photos: [photo('fixed2')]);
    await x.verifyFix(defect.id, accept: true, by: engineer);
    await x.decideHoldPoint(holds.single.id, release: true, by: pm);
    for (final c in (await load()).checksOf(flat.id)) {
      await x.setCheck(c.id, done: true, by: engineer);
    }
    d = await load();
    expect(d.handoverBlockers(flat), isEmpty);
    expect(d.unitState(flat), UnitState.ready);
    expect(d.photosOf(defect.id, 'defect'), hasLength(1));
    expect(d.photosOf(defect.id, 'defect_fix'), hasLength(2));
    await x.handOver(flat.id, handedTo: 'Mr. Reddy', by: pm, blockers: d.handoverBlockers(flat), note: 'Keys given');
    d = await load();
    expect(d.unitState(d.units.single), UnitState.handedOver);
    await expectLater(x.handOver(flat.id, handedTo: 'Someone else', by: pm, blockers: const []), throwsA(isA<ExecutionRefused>()));
  });

  test('the portfolio report counts every site the same way', () async {
    final other = await db.projectDao.create(ProjectsCompanion.insert(
        id: const Uuid().v4(), companyId: company.id, name: 'Miyapur, Tower B', status: const Value('active')));
    final t = await task('Plaster, 1st floor', now, now.add(const Duration(days: 5)));
    await x.addConstraint(projectId: site.id, taskId: t.id, kind: 'labour', description: '6 masons', by: engineer);
    await x.raiseRfi(projectId: site.id, question: 'Skirting height?', by: engineer, dueOn: ymd(now.subtract(const Duration(days: 2))));
    await x.raiseDefect(projectId: other.id, description: 'Door hinge loose', by: engineer, now: now.subtract(const Duration(days: 9)));

    final rows = [
      for (final p in [site, other]) (p.name, (await loadExecutionData(db, p.id)).summary(now)),
    ];
    final kompally = rows.first.$2;
    expect((kompally.lookaheadTasks, kompally.blockedTasks, kompally.openRfis, kompally.overdueRfis), (1, 1, 1, 1));
    expect(kompally.needsAttention, isTrue);
    final miyapur = rows.last.$2;
    expect((miyapur.openDefects, miyapur.ageingDefects), (1, 1));
    final csv = portfolioCsv(rows);
    expect(csv.split('\n').where((l) => l.isNotEmpty), hasLength(3));
    expect(csv, contains('"Miyapur, Tower B"'));
  });

  test('every write is queued for the cloud with snake_case columns and files', () async {
    final s12 = await x.addDrawing(projectId: site.id, number: 'A-01', title: 'Ground floor plan', by: engineer);
    await x.addRevision(drawingId: s12.id, rev: 'R0', filePath: photo('a01'), by: engineer);
    final queued = [for (final q in await db.syncOutboxDao.pending()) if (q.targetTable.startsWith('site_')) q];
    expect(queued.map((q) => q.targetTable), ['site_drawings', 'site_drawing_revisions']);
    final rev = jsonDecode(queued.last.payload) as Map<String, dynamic>;
    expect(rev['drawing_id'], s12.id);
    expect(rev['file_path'], startsWith('${site.id}/drawings/'));
    expect(rev['_local_file_path'], endsWith('a01.jpg'));
    expect(DateTime.parse(rev['created_at'] as String).isUtc, isTrue);

    // A row from the cloud comes back as the phone's row.
    final back = executionFromRemote('site_drawings', jsonDecode(queued.first.payload) as Map<String, dynamic>);
    await x.upsertFromRemote('site_drawings', back);
    expect((await x.drawingsFor(site.id)).single.number, 'A-01');
  });
}
