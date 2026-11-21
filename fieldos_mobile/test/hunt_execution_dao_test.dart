/// Bug hunt on the site execution records: submittals sent round many
/// times, overdue on the boundary day, registers that already hold a
/// duplicate from two phones, and rows that stay on their own site.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.memory());
  tearDown(() => db.close());

  test('after many rounds the history keeps the latest reviews, whole', () async {
    final x = db.siteExecutionDao;
    var s = await x.raiseSubmittal(projectId: 'p1', title: 'Floor tiles', by: 'u1');
    for (var i = 1; i <= 9; i++) {
      s = await x.decideSubmittal(s.id, status: 'revise_resubmit', note: 'Round $i: ${'x' * 990}', by: 'pm');
      s = await x.resubmitSubmittal(s.id, by: 'u1');
    }
    expect(s.round, 10);
    expect(s.history.length, lessThanOrEqualTo(8000));
    final lines = s.history.split('\n');
    final parsed = [for (final l in lines) parseSubmittalHistory(l)];
    expect(parsed, everyElement(isNotNull), reason: 'no line cut in half');
    expect(parsed.last!.round, 9, reason: 'the review just sent back is kept');
    expect(parsed.last!.note, startsWith('Round 9:'));
    expect(parsed.last!.note.length, 'Round 9: '.length + 990);
  });

  test('a rejected submittal goes round again, and only a submitted one can be reviewed', () async {
    final x = db.siteExecutionDao;
    var s = await x.raiseSubmittal(projectId: 'p1', title: 'Door hardware', by: 'u1');
    s = await x.decideSubmittal(s.id, status: 'rejected', note: 'Wrong finish', by: 'pm');
    await expectLater(x.decideSubmittal(s.id, status: 'approved', by: 'pm'), throwsA(isA<ExecutionRefused>()));
    s = await x.resubmitSubmittal(s.id, by: 'u1');
    expect((s.status, s.round, s.decidedAt, s.decisionNote), ('submitted', 2, null, null));
    s = await x.decideSubmittal(s.id, status: 'approved', by: 'pm');
    await expectLater(x.resubmitSubmittal(s.id, by: 'u1'), throwsA(isA<ExecutionRefused>()));
    expect(parseSubmittalHistory(s.history)!.status, 'rejected');
  });

  test('a submittal needed today is not overdue; needed yesterday it is', () async {
    final x = db.siteExecutionDao;
    final today = await x.raiseSubmittal(projectId: 'p1', title: 'A', requiredBy: '2026-11-10', by: 'u1');
    final past = await x.raiseSubmittal(projectId: 'p1', title: 'B', requiredBy: '2026-11-09', by: 'u1');
    final d = await loadExecutionData(db, 'p1');
    final now = DateTime(2026, 11, 10, 23, 59);
    expect(d.submittalOverdue(today, now), isFalse);
    expect(d.submittalOverdue(past, now), isTrue);
    expect([d.submittalNo(today), d.submittalNo(past)], ['SUB-1', 'SUB-2']);
  });

  test('adding a drawing number or revision the register already holds twice is refused, not a crash', () async {
    final x = db.siteExecutionDao;
    final t = DateTime(2026, 11, 1);
    // Two phones each added A-101 offline; both rows came back from sync.
    for (final id in ['d1', 'd2']) {
      await x.upsertFromRemote(
          'site_drawings',
          DrawingsCompanion.insert(
              id: id, projectId: 'p1', number: 'A-101', title: 'Plan', createdBy: 'u1', createdAt: Value(t), updatedAt: Value(t)));
    }
    for (final id in ['r1', 'r2']) {
      await x.upsertFromRemote(
          'site_drawing_revisions',
          DrawingRevisionsCompanion.insert(
              id: id, projectId: 'p1', drawingId: 'd1', rev: 'R1', filePath: '/x.pdf', mimeType: 'application/pdf', uploadedBy: 'u1',
              createdAt: Value(t), updatedAt: Value(t)));
    }
    await expectLater(x.addDrawing(projectId: 'p1', number: 'a-101', title: 'Plan', by: 'u1'), throwsA(isA<ExecutionRefused>()));
    await expectLater(x.addRevision(drawingId: 'd1', rev: 'r1', filePath: '/y.pdf', by: 'u1'), throwsA(isA<ExecutionRefused>()));
    // Another site may use the same number.
    expect((await x.addDrawing(projectId: 'p2', number: 'A-101', title: 'Plan', by: 'u1')).projectId, 'p2');
  });

  test('records stay on their own site, removed pins included only where asked', () async {
    final x = db.siteExecutionDao;
    final dr = await x.addDrawing(projectId: 'p1', number: 'S-1', title: 'Footings', by: 'u1');
    final rev = await x.addRevision(drawingId: dr.id, rev: 'R1', filePath: '/s1.png', by: 'u1');
    final pin = await x.addPin(projectId: 'p1', revisionId: rev.id, kind: 'note', label: 'Here', x: 0, y: 1, by: 'u1');
    final gone = await x.addPin(projectId: 'p1', revisionId: rev.id, kind: 'note', label: 'Old', x: 0.5, y: 0.5, by: 'u1');
    await x.removePin(gone.id, by: 'u1', manager: false);
    await x.raiseSubmittal(projectId: 'p2', title: 'Other site', by: 'u1');
    await x.raiseRfi(projectId: 'p2', question: 'Other site?', by: 'u1');
    final d = await loadExecutionData(db, 'p1');
    expect(d.submittals, isEmpty);
    expect(d.rfis, isEmpty);
    expect(d.pins, hasLength(2));
    expect(d.pinsOn(dr.id).map((p) => p.id), [pin.id]);
    expect((pin.x, pin.y), (0.0, 1.0), reason: 'a pin on the sheet edge stays on it');
    expect(d.pinsOn(dr.id, page: 1), isEmpty);
  });
}
