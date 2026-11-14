/// Pins and markup on drawings on two phones against the local Supabase
/// stack (skips itself when the stack is not running): the engineer pins a
/// defect and draws on the approved drawing, the PM sees both on their
/// phone, and the server refuses changing a pin or removing someone else's
/// as a non-manager.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';

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
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)..clear(img.ColorRgb8(200, 200, 200)))))
      .path;

  test('pins and markup sync between phones, and the server keeps them as placed', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final pm = await CloudPhone.signUp('pins-pm');
    final engineer = await CloudPhone.signUp('pins-engineer');
    addTearDown(() async {
      await pm.close();
      await engineer.close();
    });

    final company = await pm.db.companyDao.create('Sai Constructions');
    final cloud = await pm.service.registerCompany(companyId: company.id, name: company.name);
    final site = await pm.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final p = pm.db.siteExecutionDao;
    final a101 = await p.addDrawing(projectId: site.id, number: 'A-101', title: 'Ground floor', discipline: 'architectural', by: pm.localUserId);
    final r1 = await p.addRevision(drawingId: a101.id, rev: 'R1', filePath: jpg(pm, 'a101'), by: pm.localUserId);
    await p.decideRevision(r1.id, approve: true, by: pm.localUserId);
    final pmPin = await p.addPin(projectId: site.id, revisionId: r1.id, kind: 'note', label: 'Client wants a wider door', x: 0.2, y: 0.3, by: pm.localUserId);
    await pushAll(pm);

    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();
    final e = engineer.db.siteExecutionDao;
    final me = engineer.localUserId;
    expect((await e.pinsFor(site.id)).single.label, 'Client wants a wider door');

    final defect = await e.raiseDefect(projectId: site.id, description: 'Skirting cracked', by: me);
    final pin = await e.addPin(projectId: site.id, revisionId: r1.id, kind: 'defect', label: 'Skirting cracked', x: 0.6, y: 0.4,
        linkId: defect.id, by: me);
    final markup = await e.addPin(projectId: site.id, revisionId: r1.id, kind: 'markup', label: 'Move wall', x: 0.1, y: 0.1,
        strokes: '[[0.1,0.1,0.2,0.2]]', color: 'blue', by: me);
    await pushAll(engineer);

    // A pin stays as it was placed; only its removal changes it.
    await expectLater(engineer.client.from('site_drawing_pins').update({'x': 0.9}).eq('id', pin.id).select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('only removed'))));
    // The engineer is not a manager: the PM's pin is not theirs to remove.
    final eid = engineer.remoteUserId;
    await expectLater(
        engineer.client
            .from('site_drawing_pins')
            .update({'removed_at': DateTime.now().toUtc().toIso8601String(), 'removed_by': eid})
            .eq('id', pmPin.id)
            .select(),
        throwsA(isA<PostgrestException>().having((x) => x.message, 'message', contains('Only whoever placed'))));
    // Nor placed as someone else.
    await expectLater(
        engineer.client.from('site_drawing_pins').insert({
          'id': uuid.v4(), 'project_id': site.id, 'drawing_id': a101.id, 'revision_id': r1.id, 'x': 0.5, 'y': 0.5,
          'kind': 'note', 'label': 'x', 'created_by': pm.remoteUserId,
        }),
        throwsA(isA<PostgrestException>()));

    await e.removePin(markup.id, by: me, manager: false);
    await pushAll(engineer);

    await pm.engine.pullAll();
    final d = await loadExecutionData(pm.db, site.id);
    final showing = d.pinsOn(a101.id);
    expect(showing.map((x) => x.label), unorderedEquals(['Client wants a wider door', 'Skirting cracked']));
    final synced = showing.firstWhere((x) => x.kind == 'defect');
    expect(synced.linkId, defect.id);
    expect(d.pins.firstWhere((x) => x.id == markup.id).removedAt, isNotNull, reason: 'removed, not deleted');
  });
}
