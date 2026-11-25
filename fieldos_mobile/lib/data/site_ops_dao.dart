/// Quality tests, safety breaches and the security gate log. Every write
/// is queued for the cloud in the same transaction.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/data/pre_construction_dao.dart' show ymdOf;
import 'package:fieldos_mobile/core/geo.dart';
import 'package:fieldos_mobile/features/execution/activity_templates.dart';
import 'package:fieldos_mobile/features/execution/site_ops_rules.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/site_execution_sync.dart';

const _uuid = Uuid();

String? _clip(String? s, int max) {
  final v = s?.trim();
  if (v == null || v.isEmpty) return null;
  return v.length > max ? v.substring(0, max) : v;
}

class SiteOpsDao {
  SiteOpsDao(this.db);
  final AppDatabase db;

  Future<void> _queue(String serverTable, String op, DataClass row) => db.syncOutboxDao.enqueue(
        targetTable: serverTable,
        recordId: (row.toJson()['id']) as String,
        operation: op,
        payloadJson: jsonEncode(executionToRemote(serverTable, row)),
      );

  // --- Quality ---------------------------------------------------------------

  Future<List<QualityTest>> qualityFor(String projectId) => (db.select(db.qualityTests)
        ..where((t) => t.projectId.equals(projectId))
        ..orderBy([(t) => OrderingTerm.asc(t.dueOn), (t) => OrderingTerm.asc(t.createdAt)]))
      .get();

  Future<QualityTest?> qualityById(String id) =>
      (db.select(db.qualityTests)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// A pour of concrete: three cube tests, at 7, 14 and 28 days.
  Future<List<QualityTest>> addCubeSet({
    required String projectId,
    required String grade,
    required String castOn,
    required String by,
    String? batchNo,
    String? element,
    String? officer,
    DateTime? now,
  }) =>
      db.transaction(() async {
        if (gradeStrength(grade) == null) throw ExecutionRefused(tr('Pick the concrete grade.'));
        final t = now ?? DateTime.now();
        final out = <QualityTest>[];
        for (final due in cubeSchedule(castOn, grade)) {
          final row = await db.into(db.qualityTests).insertReturning(QualityTestsCompanion.insert(
                id: _uuid.v4(),
                projectId: projectId,
                kind: 'cube',
                parameter: '${tr('Compressive strength')} $grade',
                requiredValue: due.requiredValue,
                sampledOn: castOn,
                dueOn: due.dueOn,
                raisedBy: by,
                unit: const Value('N/mm²'),
                ageDays: Value(due.ageDays),
                batchNo: Value(_clip(batchNo, 60)),
                element: Value(_clip(element, 200)),
                officer: Value(_clip(officer, 120)),
                createdAt: Value(t),
                updatedAt: Value(t),
              ));
          await _queue('site_quality_tests', 'insert', row);
          out.add(row);
        }
        return out;
      });

  /// Any other test (plastering, painting, bitumen work): one row, with the
  /// value it must show.
  Future<QualityTest> addQualityTest({
    required String projectId,
    required String kind,
    required String parameter,
    required double requiredValue,
    required String by,
    String rule = 'min',
    String? unit,
    String? sampledOn,
    String? dueOn,
    String? batchNo,
    String? element,
    String? officer,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final p = _clip(parameter, 100);
        if (p == null) throw ExecutionRefused(tr('Say what is being tested.'));
        if (requiredValue <= 0) throw ExecutionRefused(tr('Enter the value the test must show.'));
        final t = now ?? DateTime.now();
        final day = sampledOn ?? ymdOf(t);
        final row = await db.into(db.qualityTests).insertReturning(QualityTestsCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              kind: kind,
              parameter: p,
              requiredValue: requiredValue,
              sampledOn: day,
              dueOn: dueOn ?? day,
              raisedBy: by,
              rule: Value(rule == 'max' ? 'max' : 'min'),
              unit: Value(_clip(unit, 20)),
              batchNo: Value(_clip(batchNo, 60)),
              element: Value(_clip(element, 200)),
              officer: Value(_clip(officer, 120)),
              createdAt: Value(t),
              updatedAt: Value(t),
            ));
        await _queue('site_quality_tests', 'insert', row);
        return row;
      });

  /// Records the test's actual value. The result is worked out here (and
  /// checked again by the server).
  Future<QualityTest> recordTest(String id, {required double actual, required String by, String? note, DateTime? now}) =>
      db.transaction(() async {
        final x = await qualityById(id);
        if (x == null) throw ExecutionRefused(tr('This test is no longer on the phone.'));
        if (x.result != 'pending') throw ExecutionRefused(tr('This test already has its result.'));
        if (actual < 0) throw ExecutionRefused(tr('The value cannot be negative.'));
        final t = now ?? DateTime.now();
        await (db.update(db.qualityTests)..where((r) => r.id.equals(id))).write(QualityTestsCompanion(
          actualValue: Value(actual),
          result: Value(testResult(rule: x.rule, required: x.requiredValue, actual: actual)),
          testedOn: Value(ymdOf(t)),
          testedBy: Value(by),
          note: Value(_clip(note, 300) ?? x.note),
          updatedAt: Value(t),
        ));
        final row = (await qualityById(id))!;
        await _queue('site_quality_tests', 'update', row);
        return row;
      });

  // --- Safety ------------------------------------------------------------------

  Future<List<SafetyBreach>> breachesFor(String projectId) => (db.select(db.safetyBreaches)
        ..where((b) => b.projectId.equals(projectId))
        ..orderBy([(b) => OrderingTerm.desc(b.onDay), (b) => OrderingTerm.desc(b.createdAt)]))
      .get();

  Future<SafetyBreach?> breachById(String id) =>
      (db.select(db.safetyBreaches)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<SafetyBreach> addBreach({
    required String projectId,
    required String department,
    required String description,
    required String by,
    String severity = 'minor',
    String? who,
    String? onDay,
    String? actionTaken,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final d = _clip(description, 500);
        if (d == null) throw ExecutionRefused(tr('Say what happened.'));
        if (!safetyDepartments.contains(department)) throw ArgumentError.value(department, 'department');
        if (!breachSeverities.contains(severity)) throw ArgumentError.value(severity, 'severity');
        final t = now ?? DateTime.now();
        final row = await db.into(db.safetyBreaches).insertReturning(SafetyBreachesCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              department: department,
              description: d,
              onDay: onDay ?? ymdOf(t),
              raisedBy: by,
              severity: Value(severity),
              who: Value(_clip(who, 120)),
              actionTaken: Value(_clip(actionTaken, 500)),
              createdAt: Value(t),
              updatedAt: Value(t),
            ));
        await _queue('site_safety_breaches', 'insert', row);
        return row;
      });

  /// Closes a breach with what was done about it.
  Future<SafetyBreach> closeBreach(String id, {required String action, required String by, DateTime? now}) =>
      db.transaction(() async {
        final b = await breachById(id);
        if (b == null) throw ExecutionRefused(tr('This breach is no longer on the phone.'));
        if (b.closedAt != null) throw ExecutionRefused(tr('This breach is already closed.'));
        final a = _clip(action, 500);
        if (a == null) throw ExecutionRefused(tr('Write what was done about it.'));
        final t = now ?? DateTime.now();
        await (db.update(db.safetyBreaches)..where((r) => r.id.equals(id)))
            .write(SafetyBreachesCompanion(actionTaken: Value(a), closedAt: Value(t), closedBy: Value(by), updatedAt: Value(t)));
        final row = (await breachById(id))!;
        await _queue('site_safety_breaches', 'update', row);
        return row;
      });

  // --- Security gate ---------------------------------------------------------------

  Future<List<GateCheck>> gateFor(String projectId, {int limit = 300}) => (db.select(db.gateChecks)
        ..where((g) => g.projectId.equals(projectId))
        ..orderBy([(g) => OrderingTerm.desc(g.createdAt)])
        ..limit(limit))
      .get();

  Future<GateCheck> addGateCheck({
    required String projectId,
    required String kind,
    required String personName,
    required String by,
    String? workerId,
    String? item,
    double? reading,
    String? note,
    DateTime? now,
  }) =>
      db.transaction(() async {
        if (!gateKinds.contains(kind)) throw ArgumentError.value(kind, 'kind');
        final name = _clip(personName, 120);
        if (name == null) throw ExecutionRefused(tr('Enter the person\'s name.'));
        if (kind == 'breath' && reading == null) throw ExecutionRefused(tr('Enter the breathalyser reading.'));
        if (reading != null && reading < 0) throw ExecutionRefused(tr('The reading cannot be negative.'));
        final t = now ?? DateTime.now();
        final row = await db.into(db.gateChecks).insertReturning(GateChecksCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              kind: kind,
              personName: name,
              checkedBy: by,
              workerId: Value(workerId),
              result: Value(gateResult(kind: kind, item: item, reading: reading)),
              item: Value(_clip(item, 120)),
              reading: Value(reading),
              note: Value(_clip(note, 300)),
              createdAt: Value(t),
              updatedAt: Value(t),
            ));
        await _queue('site_gate_checks', 'insert', row);
        return row;
      });

  // --- Stage checklists and on-site checks ------------------------------------------

  /// Adds a task for every step of the chosen stages, each needing an
  /// on-site check before 100%. Returns how many tasks were added.
  Future<int> addStageChecklist({
    required String projectId,
    required List<String> stageIds,
    required DateTime start,
    DateTime? now,
  }) =>
      db.transaction(() async {
        var n = 0;
        final day = DateTime(start.year, start.month, start.day);
        for (final id in stageIds) {
          final stage = stageById(id);
          if (stage == null) throw ArgumentError.value(id, 'stageId');
          for (final step in stage.steps) {
            await db.taskDao.create(TasksCompanion.insert(
              id: _uuid.v4(),
              projectId: projectId,
              title: activityTaskTitle(stage, step),
              startDate: Value(day),
              dueDate: Value(stage.minDays > 0 ? DateTime(day.year, day.month, day.day + stage.minDays) : null),
              verifyRequired: const Value(true),
            ));
            n++;
          }
        }
        if (n == 0) throw ExecutionRefused(tr('Pick at least one stage.'));
        return n;
      });

  Future<List<TaskCheck>> checksFor(String projectId) =>
      (db.select(db.taskChecks)..where((c) => c.projectId.equals(projectId))).get();

  /// Records that [by] stood at the site when marking the task done. When
  /// the site has a location, the phone must be within its radius.
  Future<TaskCheck> verifyTask(
    String taskId, {
    required double lat,
    required double lng,
    required String by,
    double? accuracyM,
    String? note,
    DateTime? now,
  }) =>
      db.transaction(() async {
        final task = await (db.select(db.tasks)..where((t) => t.id.equals(taskId))).getSingleOrNull();
        if (task == null) throw ExecutionRefused(tr('This task is no longer on the phone.'));
        final fence = await db.geofenceDao.effectiveFor(task.projectId);
        double? distance;
        if (fence != null) {
          distance = haversineMeters(lat, lng, fence.centerLat, fence.centerLng);
          final allowed = fence.radiusMeters > 0 ? fence.radiusMeters : defaultSiteRadiusM;
          if (distance > allowed + (accuracyM ?? 0).clamp(0, 50)) {
            throw ExecutionRefused(trf('You are {n} m from the site. Go to the site to verify.', {'n': distance.round()}));
          }
        }
        final t = now ?? DateTime.now();
        final row = await db.into(db.taskChecks).insertReturning(TaskChecksCompanion.insert(
              id: _uuid.v4(),
              projectId: task.projectId,
              taskId: taskId,
              lat: lat,
              lng: lng,
              checkedBy: by,
              accuracyM: Value(accuracyM),
              distanceM: Value(distance),
              note: Value(_clip(note, 300)),
              createdAt: Value(t),
              updatedAt: Value(t),
            ));
        await _queue('site_task_checks', 'insert', row);
        return row;
      });
}
