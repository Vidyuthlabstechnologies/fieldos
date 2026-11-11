/// FOS-205 to FOS-209 on two phones against the local Supabase stack
/// (skips itself when the stack is not running). The site engineer plans
/// the slab, asks the consultant, uploads the drawing, raises a hold point
/// and a defect; the project manager answers, approves and releases on
/// their own phone; the defect is fixed and checked by different people;
/// and the flat is handed over only when the server agrees nothing is
/// left. At every step the server refuses what the phone would refuse.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<void> pushAll(CloudPhone p) async {
    final r = await p.engine.pushPending();
    final errors = [for (final e in await p.db.select(p.db.syncOutbox).get()) '${e.targetTable}: ${e.lastError}'];
    expect(r.failed, 0, reason: '$errors');
  }

  String jpg(CloudPhone p, String name) => (File('${p.filesDir.path}/$name.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)..clear(img.ColorRgb8(180, 170, 160)))))
      .path;

  test('lookahead, drawings, RFIs, hold points, defects and handover across two phones', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final pm = await CloudPhone.signUp('exec-pm');
    final engineer = await CloudPhone.signUp('exec-engineer');
    addTearDown(() async {
      await pm.close();
      await engineer.close();
    });

    final company = await pm.db.companyDao.create('Sai Constructions');
    final cloud = await pm.service.registerCompany(companyId: company.id, name: company.name);
    final site = await pm.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final now = DateTime.now();
    final slab = await pm.db.taskDao.create(TasksCompanion.insert(
        id: uuid.v4(), projectId: site.id, title: 'Slab casting, 3rd floor',
        startDate: Value(now.add(const Duration(days: 2))), dueDate: Value(now.add(const Duration(days: 3)))));
    await pm.db.siteExecutionDao.addStandard(companyId: company.id, kind: 'handover_check', item: 'Keys and manuals', by: pm.localUserId);
    await pushAll(pm);

    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();
    final e = engineer.db.siteExecutionDao;
    final me = engineer.localUserId;
    expect((await e.standardsFor(company.id)).map((s) => s.item), ['Keys and manuals'], reason: 'company standards reach every phone');

    // --- The engineer plans the slab ---------------------------------------
    final rfi = await e.raiseRfi(projectId: site.id, question: 'Beam B12 depth: 450 or 600?', by: me, taskId: slab.id,
        askedOf: 'Structural consultant', photos: [jpg(engineer, 'b12')]);
    final s12 = await e.addDrawing(projectId: site.id, number: 'S-12', title: '3rd floor beams', discipline: 'structural', by: me);
    final r0 = await e.addRevision(drawingId: s12.id, rev: 'R0', filePath: jpg(engineer, 's12-r0'), by: me);
    final hold = await e.addHoldPoint(projectId: site.id, title: 'Reinforcement check before pour', by: me, taskId: slab.id);
    final flat = await e.addUnit(projectId: site.id, block: 'A', floor: '3', name: 'Flat 304', by: me,
        checklist: [for (final s in await e.standardsFor(company.id)) s.item]);
    final crack = await e.raiseDefect(projectId: site.id, unitId: flat.id, description: 'Hairline crack above window',
        severity: 'major', by: me, photos: [jpg(engineer, 'crack')]);
    await pushAll(engineer);

    // The engineer can't make the PM's decisions by going round the phone.
    final eid = engineer.remoteUserId;
    await expectLater(
        engineer.client.from('site_drawing_revisions').update({'status': 'approved', 'decided_by': eid}).eq('id', r0.id).select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('approves a drawing'))));
    await expectLater(
        engineer.client.from('site_hold_points').update({'status': 'released', 'decided_by': eid}).eq('id', hold.id).select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('releases a hold point'))));
    await expectLater(
        engineer.client.from('company_standards').insert({
          'id': uuid.v4(), 'company_id': company.id, 'kind': 'hold_point', 'item': 'Mine', 'created_by': eid,
        }),
        throwsA(isA<PostgrestException>()));
    await expectLater(
        engineer.client.from('site_drawing_revisions').update({'file_path': '${site.id}/drawings/other.jpg'}).eq('id', r0.id).select(),
        throwsA(isA<PostgrestException>()), reason: 'an uploaded revision is never swapped');

    // --- The PM answers, approves and releases on their own phone ----------
    await pm.engine.pullAll();
    final p = pm.db.siteExecutionDao;
    var d = await loadExecutionData(pm.db, site.id);
    expect(d.lookahead(now).single.open.map((c) => c.kind), unorderedEquals(['rfi', 'hold_point']));
    expect(d.photosOf(rfi.id, 'rfi'), hasLength(1));
    expect(File(d.revisions.single.filePath).existsSync(), isTrue, reason: 'the drawing file is on the PM\'s phone');
    await p.answerRfi(rfi.id, answer: '600 deep; see S-12 R0', by: pm.localUserId);
    await p.decideRevision(r0.id, approve: true, by: pm.localUserId);
    await p.decideHoldPoint(hold.id, release: true, by: pm.localUserId, note: 'Cover blocks fixed');
    await pushAll(pm);

    await engineer.engine.pullAll();
    d = await loadExecutionData(engineer.db, site.id);
    expect(d.lookahead(now).single.ready, isTrue, reason: 'answered, approved and released: the slab can go');
    expect(d.currentRevision(s12.id)?.rev, 'R0');

    // --- The defect: fixed by one, checked by another ---------------------------
    await e.markFixed(crack.id, by: me, note: 'Filled and painted', photos: [jpg(engineer, 'fixed')]);
    await pushAll(engineer);
    await expectLater(
        engineer.client.from('site_defects').update({'status': 'closed', 'closed_by': eid}).eq('id', crack.id).select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('Someone other than'))));

    // The server won't hand over a flat with a defect still open, whatever
    // the phone thinks.
    await pm.engine.pullAll();
    final pid = pm.remoteUserId;
    await expectLater(
        pm.client.from('site_handover_units')
            .update({'handed_over_at': DateTime.now().toUtc().toIso8601String(), 'handed_over_by': pid, 'handed_to': 'Mr. Reddy'})
            .eq('id', flat.id)
            .select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('defects not closed'))));
    await p.verifyFix(crack.id, accept: true, by: pm.localUserId);
    await pushAll(pm);
    await expectLater(
        pm.client.from('site_handover_units')
            .update({'handed_over_at': DateTime.now().toUtc().toIso8601String(), 'handed_over_by': pid, 'handed_to': 'Mr. Reddy'})
            .eq('id', flat.id)
            .select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('checklist lines not done'))));

    // The engineer ticks the checklist; the PM hands over.
    await engineer.engine.pullAll();
    for (final c in (await loadExecutionData(engineer.db, site.id)).checksOf(flat.id)) {
      await e.setCheck(c.id, done: true, by: me);
    }
    await pushAll(engineer);
    await pm.engine.pullAll();
    d = await loadExecutionData(pm.db, site.id);
    final unit = d.units.single;
    expect(d.handoverBlockers(unit), isEmpty);
    await p.handOver(unit.id, handedTo: 'Mr. Reddy', by: pm.localUserId, blockers: d.handoverBlockers(unit), note: 'Keys given');
    await pushAll(pm);

    await engineer.engine.pullAll();
    d = await loadExecutionData(engineer.db, site.id);
    expect(d.unitState(d.units.single), UnitState.handedOver);
    expect(d.defects.single.status, 'closed');
    expect(d.photosOf(crack.id, 'defect_fix'), hasLength(1));
    final s = d.summary(now);
    expect((s.openRfis, s.pendingRevisions, s.pendingHoldPoints, s.openDefects, s.unitsHandedOver), (0, 0, 0, 0, 1));
  });
}
