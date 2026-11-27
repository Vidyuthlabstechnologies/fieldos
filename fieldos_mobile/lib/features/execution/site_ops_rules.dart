/// Rules for the quality, safety and security consoles, kept free of
/// Flutter so they can be tested on their own:
///
/// - a test passes when the actual value reaches the required one (or stays
///   under it, for a limit); the result is worked out, never typed;
/// - a cube set is three tests: 7, 14 and 28 days after casting, each with
///   its own due date and its own required strength;
/// - a frisk that finds anything, or a breath reading above zero, is
///   flagged; who is inside the gate follows each person's last punch.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/cube_acceptance.dart' show GradeAcceptance, evaluateGrade, gradeOfTest, individualLimit;
import 'package:fieldos_mobile/features/execution/execution_rules.dart' show parseDay, ymd;
import 'package:fieldos_mobile/l10n/language.dart';

// --- Quality ---------------------------------------------------------------------

const qualityKinds = ['cube', 'plaster', 'paint', 'bitumen', 'other'];
const concreteGrades = ['M15', 'M20', 'M25', 'M30', 'M35', 'M40'];

/// Days after casting a cube is crushed, and the share of the 28-day
/// strength it should already show (working practice, not IS 456: a miss at 7
/// or 14 days is a warning). The 28-day cube's requirement is not a share of
/// fck: it is the least one sample may show under IS 456 Table 11 column 3
/// (fck - 4, or fck - 3 for M15), see [individualLimit]. Whether a group of
/// four samples is good enough is judged in cube_acceptance.dart.
const cubeAges = {7: 0.65, 14: 0.90, 28: 1.0};

/// Days ahead that a due test starts to show as "due soon".
const qualityDueSoonDays = 3;

String qualityKindLabel(String k) => switch (k) {
      'cube' => tr('Concrete cube'),
      'plaster' => tr('Plastering'),
      'paint' => tr('Painting'),
      'bitumen' => tr('Bitumen work'),
      _ => tr('Other test'),
    };

/// The parameter, unit and rule a kind of test usually has.
({String parameter, String unit, String rule}) qualityPreset(String kind) => switch (kind) {
      'cube' => (parameter: tr('Compressive strength'), unit: 'N/mm²', rule: 'min'),
      'plaster' => (parameter: tr('Thickness'), unit: 'mm', rule: 'min'),
      'paint' => (parameter: tr('Dry film thickness'), unit: 'micron', rule: 'min'),
      'bitumen' => (parameter: tr('Application rate'), unit: 'kg/m²', rule: 'min'),
      _ => (parameter: '', unit: '', rule: 'min'),
    };

/// The grade's strength in N/mm²: M25 is 25.
double? gradeStrength(String grade) {
  final m = RegExp(r'^M\s*(\d{2})$', caseSensitive: false).firstMatch(grade.trim());
  return m == null ? null : double.parse(m.group(1)!);
}

/// 'pass', 'fail' or 'pending' (no actual value yet).
String testResult({required String rule, required double required, double? actual}) {
  if (actual == null) return 'pending';
  const eps = 1e-9;
  return rule == 'max' ? (actual <= required + eps ? 'pass' : 'fail') : (actual + eps >= required ? 'pass' : 'fail');
}

class CubeDue {
  const CubeDue(this.ageDays, this.dueOn, this.requiredValue);
  final int ageDays;
  final String dueOn;
  final double requiredValue;
}

/// The 7, 14 and 28-day tests for a pour cast on [castOn].
List<CubeDue> cubeSchedule(String castOn, String grade) {
  final cast = parseDay(castOn);
  final strength = gradeStrength(grade);
  if (cast == null || strength == null) throw ArgumentError('cast day and grade');
  return [
    for (final e in cubeAges.entries)
      CubeDue(
        e.key,
        ymd(DateTime(cast.year, cast.month, cast.day + e.key)),
        double.parse((e.key == 28 ? individualLimit(strength) : strength * e.value).toStringAsFixed(2)),
      ),
  ];
}

/// overdue | soon | later | done
String qualityDueState(QualityTest t, DateTime now) {
  if (t.result != 'pending') return 'done';
  final due = parseDay(t.dueOn);
  if (due == null) return 'later';
  final today = DateTime(now.year, now.month, now.day);
  if (due.isBefore(today)) return 'overdue';
  final soon = DateTime(today.year, today.month, today.day + qualityDueSoonDays);
  return due.isAfter(soon) ? 'later' : 'soon';
}

String qualityResultLabel(String r) => switch (r) {
      'pass' => tr('Passed'),
      'fail' => tr('Failed'),
      _ => tr('Waiting for the test'),
    };

/// A 7 or 14 day cube under its early-age target. IS 456 accepts concrete on
/// the 28-day strength only; the early cubes are a warning to watch, never a
/// rejection. The stored result stays 'fail' because the server checks it
/// against the same target.
bool isEarlyCubeMiss({required String kind, required String result, int? ageDays}) =>
    kind == 'cube' && result == 'fail' && ageDays != null && ageDays < 28;

/// IS 456 acceptance of each grade of concrete poured, from the 28-day cube
/// samples tested so far, in the order they were sampled (cube_acceptance.dart).
List<GradeAcceptance> concreteAcceptance(List<QualityTest> all) {
  final byGrade = <String, List<QualityTest>>{};
  for (final t in all) {
    if (t.kind != 'cube' || t.ageDays != 28 || t.result == 'pending' || t.actualValue == null) continue;
    final grade = gradeOfTest(t.parameter);
    if (grade != null) (byGrade[grade] ??= []).add(t);
  }
  return [
    for (final grade in byGrade.keys.toList()..sort())
      evaluateGrade(
        grade,
        [
          for (final t in byGrade[grade]!
            ..sort((a, b) {
              final c = a.sampledOn.compareTo(b.sampledOn);
              return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
            }))
            t.actualValue!,
        ],
      ),
  ];
}

class QualitySummary {
  const QualitySummary({required this.passed, required this.failed, required this.overdue, required this.soon, this.early = 0});
  final int passed;
  final int failed;
  final int overdue;
  final int soon;
  final int early;
}

QualitySummary summariseQuality(List<QualityTest> all, DateTime now) {
  final early = all.where((t) => isEarlyCubeMiss(kind: t.kind, result: t.result, ageDays: t.ageDays)).length;
  return QualitySummary(
    passed: all.where((t) => t.result == 'pass').length,
    failed: all.where((t) => t.result == 'fail').length - early,
    overdue: all.where((t) => qualityDueState(t, now) == 'overdue').length,
    soon: all.where((t) => qualityDueState(t, now) == 'soon').length,
    early: early,
  );
}

// --- Safety ----------------------------------------------------------------------

const safetyDepartments = ['civil', 'electrical', 'plumbing', 'finishing', 'mep', 'security', 'other'];
const breachSeverities = ['minor', 'major', 'critical'];

String departmentLabel(String d) => switch (d) {
      'civil' => tr('Civil'),
      'electrical' => tr('Electrical'),
      'plumbing' => tr('Plumbing'),
      'finishing' => tr('Finishing'),
      'mep' => tr('MEP'),
      'security' => tr('Security'),
      _ => tr('Other department'),
    };

String severityLabel(String s) => switch (s) {
      'critical' => tr('Critical'),
      'major' => tr('Major'),
      _ => tr('Minor'),
    };

/// Open breaches per department, most first.
List<MapEntry<String, int>> breachesByDepartment(List<SafetyBreach> all) {
  final by = <String, int>{};
  for (final b in all) {
    by[b.department] = (by[b.department] ?? 0) + 1;
  }
  return by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

// --- Security gate ---------------------------------------------------------------

const gateKinds = ['punch_in', 'punch_out', 'frisk', 'breath'];

/// Things a frisk is looking for: they start fires and stain or damage
/// finished work.
const prohibitedItems = ['Paan parag', 'Gutka', 'Matches or lighter', 'Alcohol', 'Other'];

String gateKindLabel(String k) => switch (k) {
      'punch_in' => tr('Punch in'),
      'punch_out' => tr('Punch out'),
      'frisk' => tr('Gate frisk'),
      'breath' => tr('Breathalyser'),
      _ => k,
    };

/// A frisk is flagged when something was found; a breath check when the
/// reading is above zero.
String gateResult({required String kind, String? item, double? reading}) {
  if (kind == 'frisk' && (item ?? '').trim().isNotEmpty) return 'flagged';
  if (kind == 'breath' && (reading ?? 0) > 0) return 'flagged';
  return 'ok';
}

/// People whose last punch today was "in".
List<String> insideTheGate(List<GateCheck> checks, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final last = <String, GateCheck>{};
  final sorted = [...checks]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  for (final c in sorted) {
    if (c.kind != 'punch_in' && c.kind != 'punch_out') continue;
    if (c.createdAt.isBefore(today)) continue;
    last[c.personName.trim().toLowerCase()] = c;
  }
  return [for (final c in last.values) if (c.kind == 'punch_in') c.personName];
}
