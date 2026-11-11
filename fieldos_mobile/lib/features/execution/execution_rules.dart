/// The rules behind site execution (FOS-205 to FOS-209), kept free of
/// Flutter so they can be tested on their own:
///
/// - a task in the two-week lookahead is ready only when nothing it waits
///   for is still open; a constraint linked to an RFI, a drawing or a hold
///   point clears itself when that record does;
/// - a drawing on site is its latest approved revision, never a pending or
///   superseded one;
/// - a unit can be handed over only with every defect closed, every hold
///   point released and every checklist line done;
/// - the portfolio view counts the same things for every site.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

const lookaheadDays = 14;
const constraintKinds = ['material', 'drawing', 'rfi', 'hold_point', 'labour', 'equipment', 'permit', 'predecessor', 'other'];
const drawingDisciplines = ['architectural', 'structural', 'mep', 'landscape', 'other'];
const defectSeverities = ['minor', 'major', 'critical'];

/// Days a defect may stay open before it counts as ageing.
const defectAgeingDays = 7;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime? parseDay(String? ymd) => ymd == null ? null : DateTime.tryParse(ymd);
String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ExecutionData {
  ExecutionData({
    required this.projectId,
    required this.tasks,
    required this.constraints,
    required this.drawings,
    required this.revisions,
    required this.rfis,
    required this.holdPoints,
    required this.defects,
    required this.photos,
    required this.units,
    required this.checks,
  });

  final String projectId;
  final List<Task> tasks;
  final List<TaskConstraint> constraints;
  final List<Drawing> drawings;
  final List<DrawingRevision> revisions;
  final List<Rfi> rfis;
  final List<HoldPoint> holdPoints;
  final List<Defect> defects;
  final List<ExecutionPhoto> photos;
  final List<HandoverUnit> units;
  final List<HandoverCheck> checks;

  late final Map<String, Rfi> _rfiById = {for (final r in rfis) r.id: r};
  late final Map<String, HoldPoint> _holdById = {for (final h in holdPoints) h.id: h};
  late final Map<String, Drawing> drawingById = {for (final d in drawings) d.id: d};

  // --- Constraints and the lookahead -----------------------------------------

  /// Open until cleared by hand, or until the record it waits on is done.
  bool isOpen(TaskConstraint c) {
    if (c.clearedAt != null) return false;
    final link = c.linkId;
    if (link == null) return true;
    final rfi = _rfiById[link];
    if (rfi != null) return rfi.status == 'open';
    final hold = _holdById[link];
    if (hold != null) return hold.status != 'released';
    if (drawingById.containsKey(link)) return currentRevision(link) == null;
    return true;
  }

  List<TaskConstraint> openConstraintsOf(String taskId) =>
      [for (final c in constraints) if (c.taskId == taskId && isOpen(c)) c];

  /// Tasks not done that start (or are due) by [lookaheadDays] days from
  /// [now], late ones included, earliest first.
  List<LookaheadItem> lookahead(DateTime now) {
    final today = _day(now);
    final end = today.add(const Duration(days: lookaheadDays));
    final out = <LookaheadItem>[];
    for (final t in tasks) {
      if (t.status == 'done') continue;
      final start = t.startDate == null ? null : _day(t.startDate!);
      final due = t.dueDate == null ? null : _day(t.dueDate!);
      final from = start ?? due;
      if (from == null) continue;
      // Late tasks stay in: they still have to be done.
      if (from.isAfter(end)) continue;
      final open = openConstraintsOf(t.id);
      final late = [
        for (final c in open)
          if (parseDay(c.needBy) != null && parseDay(c.needBy)!.isBefore(today)) c,
      ];
      out.add(LookaheadItem(task: t, start: from, open: open, late: late));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  // --- Drawings ----------------------------------------------------------------

  List<DrawingRevision> revisionsOf(String drawingId) =>
      [for (final r in revisions) if (r.drawingId == drawingId) r];

  /// The revision the site builds to: the approved one decided last.
  DrawingRevision? currentRevision(String drawingId) {
    DrawingRevision? best;
    for (final r in revisionsOf(drawingId)) {
      if (r.status != 'approved') continue;
      if (best == null || (r.decidedAt ?? r.createdAt).isAfter(best.decidedAt ?? best.createdAt)) best = r;
    }
    return best;
  }

  /// Approved revisions that a later approved one replaced.
  bool isSuperseded(DrawingRevision r) =>
      r.status == 'approved' && currentRevision(r.drawingId)?.id != r.id;

  List<DrawingRevision> get pendingRevisions => [for (final r in revisions) if (r.status == 'pending') r];

  /// "RFI-3": by the order raised.
  String rfiNo(Rfi r) => 'RFI-${rfis.indexWhere((x) => x.id == r.id) + 1}';

  bool rfiOverdue(Rfi r, DateTime now) =>
      r.status == 'open' && parseDay(r.dueOn) != null && parseDay(r.dueOn)!.isBefore(_day(now));

  // --- Quality -----------------------------------------------------------------

  List<ExecutionPhoto> photosOf(String parentId, [String? kind]) =>
      [for (final p in photos) if (p.parentId == parentId && (kind == null || p.parentKind == kind)) p];

  bool defectAgeing(Defect d, DateTime now) =>
      d.status != 'closed' && now.difference(d.createdAt).inDays >= defectAgeingDays;

  bool defectOverdue(Defect d, DateTime now) =>
      d.status != 'closed' && parseDay(d.dueOn) != null && parseDay(d.dueOn)!.isBefore(_day(now));

  // --- Handover ----------------------------------------------------------------

  List<HandoverCheck> checksOf(String unitId) => [for (final c in checks) if (c.unitId == unitId) c];

  /// Why [u] can't be handed over yet; empty when it can.
  List<String> handoverBlockers(HandoverUnit u) {
    final defectsLeft = defects.where((d) => d.unitId == u.id && d.status != 'closed').length;
    final holdsLeft = holdPoints.where((h) => h.unitId == u.id && h.status != 'released').length;
    final checksLeft = checksOf(u.id).where((c) => !c.done).length;
    return [
      if (defectsLeft > 0) trf('{n} defects not closed', {'n': defectsLeft}),
      if (holdsLeft > 0) trf('{n} hold points not released', {'n': holdsLeft}),
      if (checksLeft > 0) trf('{n} checklist lines not done', {'n': checksLeft}),
    ];
  }

  UnitState unitState(HandoverUnit u) {
    if (u.handedOverAt != null) return UnitState.handedOver;
    return handoverBlockers(u).isEmpty ? UnitState.ready : UnitState.notReady;
  }

  /// Units grouped by block, then floor, for the handover board.
  Map<String, List<HandoverUnit>> unitsByFloor() {
    final out = <String, List<HandoverUnit>>{};
    for (final u in units) {
      final key = [if ((u.block ?? '').isNotEmpty) u.block!, if ((u.floor ?? '').isNotEmpty) u.floor!].join(' · ');
      (out[key] ??= []).add(u);
    }
    return out;
  }

  // --- Portfolio ---------------------------------------------------------------

  SiteExecutionSummary summary(DateTime now) {
    final look = lookahead(now);
    return SiteExecutionSummary(
      lookaheadTasks: look.length,
      blockedTasks: look.where((i) => !i.ready).length,
      lateConstraints: look.fold<int>(0, (n, i) => n + i.late.length),
      openRfis: rfis.where((r) => r.status == 'open').length,
      overdueRfis: rfis.where((r) => rfiOverdue(r, now)).length,
      pendingRevisions: pendingRevisions.length,
      pendingHoldPoints: holdPoints.where((h) => h.status != 'released').length,
      openDefects: defects.where((d) => d.status != 'closed').length,
      ageingDefects: defects.where((d) => defectAgeing(d, now)).length,
      units: units.length,
      unitsReady: units.where((u) => unitState(u) == UnitState.ready).length,
      unitsHandedOver: units.where((u) => u.handedOverAt != null).length,
    );
  }
}

class LookaheadItem {
  const LookaheadItem({required this.task, required this.start, required this.open, required this.late});
  final Task task;
  final DateTime start;
  final List<TaskConstraint> open;

  /// Open constraints already past the day they were needed by.
  final List<TaskConstraint> late;
  bool get ready => open.isEmpty;
}

enum UnitState { notReady, ready, handedOver }

class SiteExecutionSummary {
  const SiteExecutionSummary({
    required this.lookaheadTasks,
    required this.blockedTasks,
    required this.lateConstraints,
    required this.openRfis,
    required this.overdueRfis,
    required this.pendingRevisions,
    required this.pendingHoldPoints,
    required this.openDefects,
    required this.ageingDefects,
    required this.units,
    required this.unitsReady,
    required this.unitsHandedOver,
  });

  final int lookaheadTasks;
  final int blockedTasks;
  final int lateConstraints;
  final int openRfis;
  final int overdueRfis;
  final int pendingRevisions;
  final int pendingHoldPoints;
  final int openDefects;
  final int ageingDefects;
  final int units;
  final int unitsReady;
  final int unitsHandedOver;

  /// Something on this site needs a decision or a push this week.
  bool get needsAttention => blockedTasks > 0 || overdueRfis > 0 || ageingDefects > 0 || pendingRevisions > 0;
}

/// The portfolio report as CSV, one row per site.
String portfolioCsv(List<(String site, SiteExecutionSummary s)> rows) {
  String cell(Object v) {
    final s = '$v';
    return s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final head = [
    tr('Site'), tr('Tasks in the next two weeks'), tr('Blocked'), tr('Constraints past need-by'), tr('Open RFIs'),
    tr('Overdue RFIs'), tr('Drawings to approve'), tr('Hold points not released'), tr('Open defects'),
    tr('Defects open a week or more'), tr('Units'), tr('Ready to hand over'), tr('Handed over'),
  ];
  final lines = [head.map(cell).join(',')];
  for (final (site, s) in rows) {
    lines.add([
      site, s.lookaheadTasks, s.blockedTasks, s.lateConstraints, s.openRfis, s.overdueRfis, s.pendingRevisions,
      s.pendingHoldPoints, s.openDefects, s.ageingDefects, s.units, s.unitsReady, s.unitsHandedOver,
    ].map(cell).join(','));
  }
  return '${lines.join('\n')}\n';
}

String constraintKindLabel(String k) => switch (k) {
      'material' => tr('Material'),
      'drawing' => tr('Drawing'),
      'rfi' => tr('RFI answer'),
      'hold_point' => tr('Hold point'),
      'labour' => tr('Labour'),
      'equipment' => tr('Equipment'),
      'permit' => tr('Permit'),
      'predecessor' => tr('Earlier work'),
      _ => tr('Other'),
    };

String disciplineLabel(String d) => switch (d) {
      'architectural' => tr('Architectural'),
      'structural' => tr('Structural'),
      'mep' => tr('MEP'),
      'landscape' => tr('Landscape'),
      _ => tr('Other'),
    };

String severityLabel(String s) => switch (s) {
      'critical' => tr('Critical'),
      'major' => tr('Major'),
      _ => tr('Minor'),
    };
