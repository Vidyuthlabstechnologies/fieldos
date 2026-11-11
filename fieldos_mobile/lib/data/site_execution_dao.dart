/// Site execution records (FOS-205 to FOS-209): lookahead constraints,
/// drawings and RFIs, hold points and defects, handover, and company
/// standards. Every write is queued for the cloud in the same transaction.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

const _uuid = Uuid();

String? _clip(String? s, int max) {
  final v = s?.trim();
  if (v == null || v.isEmpty) return null;
  return v.length > max ? v.substring(0, max) : v;
}

/// A step the rules refuse (handing over a flat with open defects). The
/// message is shown as is.
class ExecutionRefused implements Exception {
  ExecutionRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

class SiteExecutionDao {
  SiteExecutionDao(this.db);
  final AppDatabase db;

  Future<void> _queue(String serverTable, String op, DataClass row) => db.syncOutboxDao.enqueue(
        targetTable: serverTable,
        recordId: (row.toJson()['id']) as String,
        operation: op,
        payloadJson: jsonEncode(executionToRemote(serverTable, row)),
      );

  /// Applies a teammate's row from the cloud.
  Future<void> upsertFromRemote(String serverTable, Insertable<DataClass> row) =>
      db.into(executionTable(db, serverTable)).insertOnConflictUpdate(row);

  // --- FOS-205: constraints ---------------------------------------------------

  Future<List<TaskConstraint>> constraintsFor(String projectId) => (db.select(db.taskConstraints)
        ..where((c) => c.projectId.equals(projectId))
        ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
      .get();

  Future<TaskConstraint> addConstraint({
    required String projectId,
    required String taskId,
    required String kind,
    required String description,
    required String by,
    String? ownerId,
    String? needBy,
    String? linkId,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final d = _clip(description, 300);
        if (d == null) throw ExecutionRefused(tr('Say what the task is waiting for.'));
        final row = await db.into(db.taskConstraints).insertReturning(TaskConstraintsCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              taskId: taskId,
              kind: kind,
              description: d,
              ownerId: Value(ownerId),
              needBy: Value(needBy),
              linkId: Value(linkId),
              raisedBy: by,
              createdAt: Value(now ?? DateTime.now()),
              updatedAt: Value(now ?? DateTime.now()),
            ));
        await _queue('site_task_constraints', 'insert', row);
        return row;
      });

  Future<TaskConstraint> clearConstraint(String id, {required String by, String? note, DateTime? now}) =>
      db.transaction(() async {
        final t = now ?? DateTime.now();
        await (db.update(db.taskConstraints)..where((c) => c.id.equals(id))).write(TaskConstraintsCompanion(
            clearedAt: Value(t), clearedBy: Value(by), clearNote: Value(_clip(note, 300)), updatedAt: Value(t)));
        final row = await (db.select(db.taskConstraints)..where((c) => c.id.equals(id))).getSingle();
        await _queue('site_task_constraints', 'update', row);
        return row;
      });

  // --- FOS-206: drawings and RFIs --------------------------------------------

  Future<List<Drawing>> drawingsFor(String projectId) => (db.select(db.drawings)
        ..where((d) => d.projectId.equals(projectId))
        ..orderBy([(d) => OrderingTerm.asc(d.number)]))
      .get();

  Future<List<DrawingRevision>> revisionsFor(String projectId) => (db.select(db.drawingRevisions)
        ..where((r) => r.projectId.equals(projectId))
        ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
      .get();

  Future<DrawingRevision?> revisionById(String id) =>
      (db.select(db.drawingRevisions)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<Drawing> addDrawing({
    required String projectId,
    required String number,
    required String title,
    String discipline = 'architectural',
    required String by,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final n = _clip(number, 40);
        final ti = _clip(title, 200);
        if (n == null || ti == null) throw ExecutionRefused(tr('Enter the drawing number and title.'));
        final same = await (db.select(db.drawings)
              ..where((d) => d.projectId.equals(projectId) & d.number.lower().equals(n.toLowerCase())))
            .getSingleOrNull();
        if (same != null) throw ExecutionRefused(trf('Drawing {number} is already in the register.', {'number': n}));
        final t = now ?? DateTime.now();
        final row = await db.into(db.drawings).insertReturning(DrawingsCompanion.insert(
            id: _uuid.v4(), projectId: projectId, number: n, title: ti, discipline: Value(discipline), createdBy: by,
            createdAt: Value(t), updatedAt: Value(t)));
        await _queue('site_drawings', 'insert', row);
        return row;
      });

  Future<DrawingRevision> addRevision({
    required String drawingId,
    required String rev,
    required String filePath,
    required String by,
    String? note,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final drawing = await (db.select(db.drawings)..where((d) => d.id.equals(drawingId))).getSingleOrNull();
        if (drawing == null) throw ExecutionRefused(tr('This drawing is no longer on the phone.'));
        final r = _clip(rev, 10);
        if (r == null) throw ExecutionRefused(tr('Enter the revision (e.g. R1 or B).'));
        final dup = await (db.select(db.drawingRevisions)
              ..where((x) => x.drawingId.equals(drawingId) & x.rev.lower().equals(r.toLowerCase())))
            .getSingleOrNull();
        if (dup != null) throw ExecutionRefused(trf('Revision {rev} is already in the register.', {'rev': r}));
        final t = now ?? DateTime.now();
        final row = await db.into(db.drawingRevisions).insertReturning(DrawingRevisionsCompanion.insert(
            id: _uuid.v4(),
            projectId: drawing.projectId,
            drawingId: drawingId,
            rev: r,
            filePath: filePath,
            mimeType: attachmentMimeType(filePath),
            note: Value(_clip(note, 300)),
            uploadedBy: by,
            createdAt: Value(t),
            updatedAt: Value(t)));
        await _queue('site_drawing_revisions', 'insert', row);
        return row;
      });

  /// The owner or a project manager approves a revision for construction
  /// (it becomes the one on site) or rejects it.
  Future<DrawingRevision> decideRevision(String id, {required bool approve, required String by, String? note, DateTime? now}) =>
      db.transaction(() async {
        final r = await revisionById(id);
        if (r == null) throw ExecutionRefused(tr('This revision is no longer on the phone.'));
        if (r.status != 'pending') throw ExecutionRefused(tr('This revision has already been decided.'));
        final t = now ?? DateTime.now();
        await (db.update(db.drawingRevisions)..where((x) => x.id.equals(id))).write(DrawingRevisionsCompanion(
            status: Value(approve ? 'approved' : 'rejected'),
            decidedBy: Value(by),
            decidedAt: Value(t),
            decisionNote: Value(_clip(note, 300)),
            updatedAt: Value(t)));
        final row = (await revisionById(id))!;
        await _queue('site_drawing_revisions', 'update', row);
        return row;
      });

  Future<List<Rfi>> rfisFor(String projectId) => (db.select(db.rfis)
        ..where((r) => r.projectId.equals(projectId))
        ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
      .get();

  Future<Rfi?> rfiById(String id) => (db.select(db.rfis)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<Rfi> raiseRfi({
    required String projectId,
    required String question,
    required String by,
    String? drawingId,
    String? taskId,
    String? assigneeId,
    String? askedOf,
    String? dueOn,
    List<String> photos = const [],
    DateTime? now,
  }) =>
      db.transaction(() async {
        final q = _clip(question, 1000);
        if (q == null) throw ExecutionRefused(tr('Write the question.'));
        final t = now ?? DateTime.now();
        final row = await db.into(db.rfis).insertReturning(RfisCompanion.insert(
            id: _uuid.v4(),
            projectId: projectId,
            question: q,
            drawingId: Value(drawingId),
            taskId: Value(taskId),
            assigneeId: Value(assigneeId),
            askedOf: Value(_clip(askedOf, 120)),
            dueOn: Value(dueOn),
            raisedBy: by,
            createdAt: Value(t),
            updatedAt: Value(t)));
        await _queue('site_rfis', 'insert', row);
        for (final p in photos) {
          await addPhoto(projectId: projectId, parentKind: 'rfi', parentId: row.id, filePath: p, now: t);
        }
        // The task waits for the answer.
        if (taskId != null) {
          await addConstraint(
              projectId: projectId, taskId: taskId, kind: 'rfi', description: q, by: by, needBy: dueOn, linkId: row.id, now: t);
        }
        return row;
      });

  Future<Rfi> answerRfi(String id, {required String answer, required String by, DateTime? now}) =>
      db.transaction(() async {
        final a = _clip(answer, 1000);
        if (a == null) throw ExecutionRefused(tr('Write the answer.'));
        final r = await rfiById(id);
        if (r == null) throw ExecutionRefused(tr('This RFI is no longer on the phone.'));
        if (r.status == 'closed') throw ExecutionRefused(tr('This RFI is closed.'));
        final t = now ?? DateTime.now();
        await (db.update(db.rfis)..where((x) => x.id.equals(id))).write(RfisCompanion(
            answer: Value(a), answeredBy: Value(by), answeredAt: Value(t), status: const Value('answered'), updatedAt: Value(t)));
        final row = (await rfiById(id))!;
        await _queue('site_rfis', 'update', row);
        return row;
      });

  Future<Rfi> closeRfi(String id, {required String by, DateTime? now}) => db.transaction(() async {
        final r = await rfiById(id);
        if (r == null) throw ExecutionRefused(tr('This RFI is no longer on the phone.'));
        final t = now ?? DateTime.now();
        await (db.update(db.rfis)..where((x) => x.id.equals(id)))
            .write(RfisCompanion(status: const Value('closed'), updatedAt: Value(t)));
        final row = (await rfiById(id))!;
        await _queue('site_rfis', 'update', row);
        return row;
      });

  // --- FOS-207: hold points and defects ---------------------------------------

  Future<List<HoldPoint>> holdPointsFor(String projectId) => (db.select(db.holdPoints)
        ..where((h) => h.projectId.equals(projectId))
        ..orderBy([(h) => OrderingTerm.asc(h.createdAt)]))
      .get();

  Future<HoldPoint?> holdPointById(String id) =>
      (db.select(db.holdPoints)..where((h) => h.id.equals(id))).getSingleOrNull();

  Future<HoldPoint> addHoldPoint({
    required String projectId,
    required String title,
    required String by,
    String? taskId,
    String? unitId,
    String? location,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final ti = _clip(title, 200);
        if (ti == null) throw ExecutionRefused(tr('Say what is inspected.'));
        final t = now ?? DateTime.now();
        final row = await db.into(db.holdPoints).insertReturning(HoldPointsCompanion.insert(
            id: _uuid.v4(),
            projectId: projectId,
            title: ti,
            taskId: Value(taskId),
            unitId: Value(unitId),
            location: Value(_clip(location, 120)),
            raisedBy: by,
            createdAt: Value(t),
            updatedAt: Value(t)));
        await _queue('site_hold_points', 'insert', row);
        if (taskId != null) {
          await addConstraint(
              projectId: projectId, taskId: taskId, kind: 'hold_point', description: ti, by: by, linkId: row.id, now: t);
        }
        return row;
      });

  /// Release lets the work go on; reject keeps it held (it can be
  /// inspected again after the fix).
  Future<HoldPoint> decideHoldPoint(String id,
          {required bool release, required String by, String? note, List<String> photos = const [], DateTime? now}) =>
      db.transaction(() async {
        final h = await holdPointById(id);
        if (h == null) throw ExecutionRefused(tr('This hold point is no longer on the phone.'));
        if (h.status == 'released') throw ExecutionRefused(tr('This hold point is already released.'));
        final t = now ?? DateTime.now();
        await (db.update(db.holdPoints)..where((x) => x.id.equals(id))).write(HoldPointsCompanion(
            status: Value(release ? 'released' : 'rejected'),
            decidedBy: Value(by),
            decidedAt: Value(t),
            note: Value(_clip(note, 300)),
            updatedAt: Value(t)));
        for (final p in photos) {
          await addPhoto(projectId: h.projectId, parentKind: 'hold_point', parentId: id, filePath: p, now: t);
        }
        final row = (await holdPointById(id))!;
        await _queue('site_hold_points', 'update', row);
        return row;
      });

  Future<List<Defect>> defectsFor(String projectId) => (db.select(db.defects)
        ..where((d) => d.projectId.equals(projectId))
        ..orderBy([(d) => OrderingTerm.asc(d.createdAt)]))
      .get();

  Future<Defect?> defectById(String id) => (db.select(db.defects)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<Defect> raiseDefect({
    required String projectId,
    required String description,
    required String by,
    String severity = 'minor',
    String? unitId,
    String? location,
    String? assigneeId,
    String? subcontractorId,
    String? dueOn,
    List<String> photos = const [],
    DateTime? now,
  }) =>
      db.transaction(() async {
        final d = _clip(description, 500);
        if (d == null) throw ExecutionRefused(tr('Describe the defect.'));
        final t = now ?? DateTime.now();
        final row = await db.into(db.defects).insertReturning(DefectsCompanion.insert(
            id: _uuid.v4(),
            projectId: projectId,
            description: d,
            severity: Value(severity),
            unitId: Value(unitId),
            location: Value(_clip(location, 120)),
            assigneeId: Value(assigneeId),
            subcontractorId: Value(subcontractorId),
            dueOn: Value(dueOn),
            raisedBy: by,
            createdAt: Value(t),
            updatedAt: Value(t)));
        await _queue('site_defects', 'insert', row);
        for (final p in photos) {
          await addPhoto(projectId: projectId, parentKind: 'defect', parentId: row.id, filePath: p, now: t);
        }
        return row;
      });

  Future<Defect> _writeDefect(String id, DefectsCompanion c) async {
    await (db.update(db.defects)..where((x) => x.id.equals(id))).write(c);
    final row = (await defectById(id))!;
    await _queue('site_defects', 'update', row);
    return row;
  }

  /// The person who did the work says it is fixed, with an after photo.
  Future<Defect> markFixed(String id, {required String by, String? note, List<String> photos = const [], DateTime? now}) =>
      db.transaction(() async {
        final d = await defectById(id);
        if (d == null) throw ExecutionRefused(tr('This defect is no longer on the phone.'));
        if (d.status != 'open') throw ExecutionRefused(tr('Only an open defect can be marked fixed.'));
        if (photos.isEmpty) throw ExecutionRefused(tr('Add a photo of the fix.'));
        final t = now ?? DateTime.now();
        for (final p in photos) {
          await addPhoto(projectId: d.projectId, parentKind: 'defect_fix', parentId: id, filePath: p, now: t);
        }
        return _writeDefect(id, DefectsCompanion(
            status: const Value('fixed'), fixedBy: Value(by), fixedAt: Value(t), fixNote: Value(_clip(note, 300)), updatedAt: Value(t)));
      });

  /// Someone other than the fixer checks the fix and closes it, or sends
  /// it back.
  Future<Defect> verifyFix(String id, {required bool accept, required String by, String? note, DateTime? now}) =>
      db.transaction(() async {
        final d = await defectById(id);
        if (d == null) throw ExecutionRefused(tr('This defect is no longer on the phone.'));
        if (d.status != 'fixed') throw ExecutionRefused(tr('Only a fixed defect can be checked.'));
        if (d.fixedBy == by) throw ExecutionRefused(tr('Someone other than the person who fixed it checks the fix.'));
        final t = now ?? DateTime.now();
        return _writeDefect(
            id,
            accept
                ? DefectsCompanion(status: const Value('closed'), closedBy: Value(by), closedAt: Value(t), updatedAt: Value(t))
                : DefectsCompanion(
                    status: const Value('open'),
                    reopenCount: Value(d.reopenCount + 1),
                    fixNote: Value(_clip(note, 300) ?? d.fixNote),
                    updatedAt: Value(t)));
      });

  // --- Photos ------------------------------------------------------------------

  Future<ExecutionPhoto> addPhoto({
    required String projectId,
    required String parentKind,
    required String parentId,
    required String filePath,
    DateTime? now,
  }) async {
    final t = now ?? DateTime.now();
    final row = await db.into(db.executionPhotos).insertReturning(ExecutionPhotosCompanion.insert(
        id: _uuid.v4(),
        projectId: projectId,
        parentKind: parentKind,
        parentId: parentId,
        filePath: filePath,
        mimeType: attachmentMimeType(filePath),
        createdAt: Value(t),
        updatedAt: Value(t)));
    await _queue('site_execution_photos', 'insert', row);
    return row;
  }

  Future<List<ExecutionPhoto>> photosFor(String projectId) =>
      (db.select(db.executionPhotos)..where((p) => p.projectId.equals(projectId))).get();

  // --- FOS-208: handover ---------------------------------------------------------

  Future<List<HandoverUnit>> unitsFor(String projectId) => (db.select(db.handoverUnits)
        ..where((u) => u.projectId.equals(projectId))
        ..orderBy([(u) => OrderingTerm.asc(u.block), (u) => OrderingTerm.asc(u.floor), (u) => OrderingTerm.asc(u.name)]))
      .get();

  Future<HandoverUnit?> unitById(String id) =>
      (db.select(db.handoverUnits)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<List<HandoverCheck>> checksFor(String projectId) => (db.select(db.handoverChecks)
        ..where((c) => c.projectId.equals(projectId))
        ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
      .get();

  /// A unit, with the company's standard handover checklist.
  Future<HandoverUnit> addUnit({
    required String projectId,
    required String name,
    required String by,
    String? block,
    String? floor,
    List<String> checklist = const [],
    DateTime? now,
  }) =>
      db.transaction(() async {
        final n = _clip(name, 60);
        if (n == null) throw ExecutionRefused(tr('Name the unit (e.g. Flat 304).'));
        final t = now ?? DateTime.now();
        final row = await db.into(db.handoverUnits).insertReturning(HandoverUnitsCompanion.insert(
            id: _uuid.v4(),
            projectId: projectId,
            name: n,
            block: Value(_clip(block, 60)),
            floor: Value(_clip(floor, 30)),
            createdBy: by,
            createdAt: Value(t),
            updatedAt: Value(t)));
        await _queue('site_handover_units', 'insert', row);
        var i = 0;
        for (final item in checklist) {
          await addCheck(unitId: row.id, projectId: projectId, item: item, sortOrder: i++, now: t);
        }
        return row;
      });

  Future<HandoverCheck> addCheck(
      {required String unitId, required String projectId, required String item, int sortOrder = 0, DateTime? now}) async {
    final it = _clip(item, 200);
    if (it == null) throw ExecutionRefused(tr('Write the check.'));
    final t = now ?? DateTime.now();
    final row = await db.into(db.handoverChecks).insertReturning(HandoverChecksCompanion.insert(
        id: _uuid.v4(), projectId: projectId, unitId: unitId, item: it, sortOrder: Value(sortOrder), createdAt: Value(t), updatedAt: Value(t)));
    await _queue('site_handover_checks', 'insert', row);
    return row;
  }

  Future<HandoverCheck> setCheck(String id, {required bool done, required String by, DateTime? now}) =>
      db.transaction(() async {
        final t = now ?? DateTime.now();
        await (db.update(db.handoverChecks)..where((c) => c.id.equals(id))).write(HandoverChecksCompanion(
            done: Value(done), doneBy: Value(done ? by : null), doneAt: Value(done ? t : null), updatedAt: Value(t)));
        final row = await (db.select(db.handoverChecks)..where((c) => c.id.equals(id))).getSingle();
        await _queue('site_handover_checks', 'update', row);
        return row;
      });

  /// Hands the unit over. Refused while it has open defects, hold points
  /// not released, or checks not done (the reasons are in [blockers]).
  Future<HandoverUnit> handOver(String unitId,
          {required String handedTo, required String by, required List<String> blockers, String? note, DateTime? now}) =>
      db.transaction(() async {
        final u = await unitById(unitId);
        if (u == null) throw ExecutionRefused(tr('This unit is no longer on the phone.'));
        if (u.handedOverAt != null) throw ExecutionRefused(tr('This unit is already handed over.'));
        if (blockers.isNotEmpty) throw ExecutionRefused(blockers.join('\n'));
        final to = _clip(handedTo, 120);
        if (to == null) throw ExecutionRefused(tr('Who is it handed to?'));
        final t = now ?? DateTime.now();
        await (db.update(db.handoverUnits)..where((x) => x.id.equals(unitId))).write(HandoverUnitsCompanion(
            handedTo: Value(to), handedOverAt: Value(t), handedOverBy: Value(by), handoverNote: Value(_clip(note, 300)), updatedAt: Value(t)));
        final row = (await unitById(unitId))!;
        await _queue('site_handover_units', 'update', row);
        return row;
      });

  // --- FOS-209: company standards ---------------------------------------------

  Future<List<CompanyStandard>> standardsFor(String companyId) => (db.select(db.companyStandards)
        ..where((s) => s.companyId.equals(companyId))
        ..orderBy([(s) => OrderingTerm.asc(s.kind), (s) => OrderingTerm.asc(s.sortOrder)]))
      .get();

  Future<CompanyStandard> addStandard(
          {required String companyId, required String kind, required String item, required String by, DateTime? now}) =>
      db.transaction(() async {
        final it = _clip(item, 200);
        if (it == null) throw ExecutionRefused(tr('Write the item.'));
        final existing = await standardsFor(companyId);
        final t = now ?? DateTime.now();
        final row = await db.into(db.companyStandards).insertReturning(CompanyStandardsCompanion.insert(
            id: _uuid.v4(),
            companyId: companyId,
            kind: kind,
            item: it,
            sortOrder: Value(existing.where((s) => s.kind == kind).length),
            createdBy: by,
            createdAt: Value(t),
            updatedAt: Value(t)));
        await _queue('company_standards', 'insert', row);
        return row;
      });

  Future<void> removeStandard(String id) => db.transaction(() async {
        final row = await (db.select(db.companyStandards)..where((s) => s.id.equals(id))).getSingleOrNull();
        if (row == null) return;
        await (db.delete(db.companyStandards)..where((s) => s.id.equals(id))).go();
        await _queue('company_standards', 'delete', row);
      });

  /// The company's standard hold points, raised at one place on a site.
  Future<List<HoldPoint>> applyHoldPointStandards({
    required String companyId,
    required String projectId,
    required String location,
    required String by,
    String? unitId,
    String? taskId,
  }) async {
    final out = <HoldPoint>[];
    for (final s in (await standardsFor(companyId)).where((s) => s.kind == 'hold_point')) {
      out.add(await addHoldPoint(projectId: projectId, title: s.item, by: by, location: location, unitId: unitId, taskId: taskId));
    }
    return out;
  }
}
