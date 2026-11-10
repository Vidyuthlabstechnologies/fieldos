/// The commercial rules, as plain functions over the synced rows, so the
/// screens, the certificate PDF and the tests all count the same way:
///
///  - What did we agree to pay? A work order's baseline (agreed quantity
///    and rate) plus approved variations.
///  - What work was actually accepted? Certified quantities, never more
///    than was claimed and never more than the order now allows.
///  - What will the project cost to finish? Per budget line: actual cost,
///    plus what is committed and not yet spent, plus what is not yet
///    committed. A commitment becomes an actual cost when work is
///    certified or material is received, and leaves the open commitment
///    in the same step, so no rupee is counted twice.
///
/// The server checks the two quantity rules again
/// (20261110100000_commercial_controls.sql), so a phone that was offline
/// or out of date can't certify the same quantity twice either.
library;

import 'dart:math' as math;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

const _eps = 0.0005;

double _r2(double v) => (v * 100).roundToDouble() / 100;
double _r3(double v) => (v * 1000).roundToDouble() / 1000;

/// Rate per unit: the order's own rate, else agreed amount over quantity.
double? workOrderRate(WorkOrder o) {
  if (o.rate != null) return o.rate;
  final q = o.contractQty;
  if (q != null && q > 0 && o.agreedAmount != null) return o.agreedAmount! / q;
  return null;
}

/// Decisions by variation id.
Map<String, VariationDecision> decisionsById(Iterable<VariationDecision> decisions) =>
    {for (final d in decisions) d.variationId: d};

enum VariationState { pending, approved, rejected }

VariationState variationState(Variation v, Map<String, VariationDecision> decisions) =>
    switch (decisions[v.id]?.decision) {
      'approved' => VariationState.approved,
      'rejected' => VariationState.rejected,
      _ => VariationState.pending,
    };

/// One work order's contract position.
class WorkOrderPosition {
  WorkOrderPosition({
    required this.order,
    required this.baselineQty,
    required this.approvedVariationQty,
    required this.certifiedQty,
    required this.rate,
    required this.baselineValue,
    required this.approvedVariationValue,
    required this.pendingVariationQty,
  });

  final WorkOrder order;
  final double baselineQty;
  final double approvedVariationQty;
  final double pendingVariationQty;
  final double certifiedQty;
  final double rate;
  final double baselineValue;
  final double approvedVariationValue;

  double get currentQty => _r3(baselineQty + approvedVariationQty);
  double get remainingQty => _r3(math.max(0, currentQty - certifiedQty));
  double get currentValue => _r2(baselineValue + approvedVariationValue);
  double get certifiedValue => _r2(certifiedQty * rate);

  /// Agreed and not yet certified: the open commitment.
  double get openCommitment => _r2(math.max(0, currentValue - certifiedValue));
  bool get hasBaseline => order.contractQty != null;
}

WorkOrderPosition workOrderPosition({
  required WorkOrder order,
  required Iterable<WorkCertification> certifications,
  required Iterable<Variation> variations,
  required Iterable<VariationDecision> decisions,
}) {
  final byId = decisionsById(decisions);
  var approvedQty = 0.0, approvedValue = 0.0, pendingQty = 0.0;
  for (final v in variations.where((v) => v.workOrderId == order.id)) {
    final d = byId[v.id];
    if (d == null) {
      pendingQty += v.qty ?? 0;
    } else if (d.decision == 'approved') {
      approvedQty += d.approvedQty ?? 0;
      approvedValue += d.approvedCost ?? 0;
    }
  }
  final certified = certifications.where((c) => c.workOrderId == order.id).fold(0.0, (s, c) => s + c.acceptedQty);
  final rate = workOrderRate(order) ?? 0;
  return WorkOrderPosition(
    order: order,
    baselineQty: order.contractQty ?? 0,
    approvedVariationQty: _r3(approvedQty),
    pendingVariationQty: _r3(pendingQty),
    certifiedQty: _r3(certified),
    rate: rate,
    baselineValue: order.agreedAmount ?? _r2((order.contractQty ?? 0) * rate),
    approvedVariationValue: _r2(approvedValue),
  );
}

/// Where one claim stands.
class ClaimPosition {
  ClaimPosition({
    required this.claim,
    required this.accepted,
    required this.rejected,
    required this.certifications,
    required this.variation,
    required this.variationState,
  });

  final WorkClaim claim;
  final double accepted;
  final double rejected;
  final List<WorkCertification> certifications;

  /// The variation raised for what the claim had beyond the order.
  final Variation? variation;
  final VariationState? variationState;

  /// Claimed and not yet accepted or rejected.
  double get open => _r3(math.max(0, claim.qty - accepted - rejected));
  bool get untouched => certifications.isEmpty;
  bool get settled => open <= _eps;

  /// Waiting for a variation decision.
  bool get heldForVariation => !settled && variation != null && variationState == VariationState.pending;

  /// The variation was approved and the held quantity can be certified.
  bool get eligibleAfterApproval => !settled && variation != null && variationState == VariationState.approved;
}

ClaimPosition claimPosition({
  required WorkClaim claim,
  required Iterable<WorkCertification> certifications,
  required Iterable<Variation> variations,
  required Iterable<VariationDecision> decisions,
}) {
  final mine = certifications.where((c) => c.claimId == claim.id).toList();
  final variation = variations.where((v) => v.sourceClaimId == claim.id).lastOrNull ??
      () {
        final id = mine.map((c) => c.variationId).whereType<String>().lastOrNull;
        return id == null ? null : variations.where((v) => v.id == id).firstOrNull;
      }();
  return ClaimPosition(
    claim: claim,
    accepted: _r3(mine.fold(0.0, (s, c) => s + c.acceptedQty)),
    rejected: _r3(mine.fold(0.0, (s, c) => s + c.rejectedQty)),
    certifications: mine,
    variation: variation,
    variationState: variation == null ? null : variationState(variation, decisionsById(decisions)),
  );
}

double claimHeldAfter(WorkClaim claim, Iterable<WorkCertification> certifications,
    {required double accepted, required double rejected}) {
  final done = certifications.where((c) => c.claimId == claim.id).fold(0.0, (s, c) => s + c.acceptedQty + c.rejectedQty);
  return _r3(math.max(0, claim.qty - done - accepted - rejected));
}

/// Why a certification can't be recorded, or null when it can.
String? certificationRefusal({
  required WorkOrder order,
  required WorkClaim claim,
  required Iterable<WorkCertification> certifications,
  required Iterable<Variation> variations,
  required Iterable<VariationDecision> decisions,
  required double accepted,
  required double rejected,
}) {
  if (accepted < 0 || rejected < 0) return tr('Quantities cannot be negative.');
  if (order.contractQty == null) return tr('This work order has no agreed quantity. Add one before certifying.');
  final claimPos = claimPosition(claim: claim, certifications: certifications, variations: variations, decisions: decisions);
  if (accepted + rejected > claimPos.open + _eps) {
    return trf('Only {open} of this claim is still to decide. The rest is already certified or rejected.',
        {'open': fmtQty(claimPos.open)});
  }
  final pos = workOrderPosition(order: order, certifications: certifications, variations: variations, decisions: decisions);
  if (accepted > pos.remainingQty + _eps) {
    return trf('Only {left} {unit} is left on this order. Send the rest to the variation register.',
        {'left': fmtQty(pos.remainingQty), 'unit': order.unit ?? ''});
  }
  return null;
}

/// What to suggest when a claim is opened: accept what the order still
/// allows, hold the rest for a variation.
({double accept, double hold}) suggestedSplit(WorkOrderPosition pos, ClaimPosition claim) {
  final accept = math.min(claim.open, pos.remainingQty);
  return (accept: _r3(accept), hold: _r3(claim.open - accept));
}


// --- Budget, commitments and cost to complete (FOS-203) ---------------------

/// One budget line. [costCode] is null for the "not coded" line, which
/// carries costs not yet put on a line so the totals stay honest.
class CostLine {
  CostLine({
    required this.costCode,
    required this.originalBudget,
    required this.approvedChanges,
    required this.pendingChanges,
    required this.poCommitted,
    required this.workOrderCommitted,
    required this.actual,
    required this.uncommitted,
    required this.sources,
  });

  final CostCode? costCode;
  final double originalBudget;
  final double approvedChanges;
  final double pendingChanges;
  final double poCommitted;
  final double workOrderCommitted;
  final double actual;
  final double uncommitted;

  /// The records behind the numbers, for drilling down.
  final List<CostSource> sources;

  double get revisedBudget => _r2(originalBudget + approvedChanges);
  double get openCommitments => _r2(poCommitted + workOrderCommitted);
  double get estimatedRemaining => _r2(openCommitments + uncommitted);
  double get projectedFinal => _r2(actual + estimatedRemaining);

  /// Positive: over budget.
  double get overrun => _r2(projectedFinal - revisedBudget);
  bool get isOver => overrun > 0.5;

  /// What the pending variations would add if approved.
  double get projectedIfPendingApproved => _r2(projectedFinal + pendingChanges);
}

enum CostSourceKind { workOrder, purchaseOrder, expense, variation }

class CostSource {
  CostSource(this.kind, this.id, this.label, {this.committed = 0, this.actual = 0, this.change = 0});
  final CostSourceKind kind;
  final String id;
  final String label;
  final double committed;
  final double actual;
  final double change;
}

class CostReport {
  CostReport(this.lines);
  final List<CostLine> lines;

  CostLine get total => CostLine(
        costCode: null,
        originalBudget: _sum((l) => l.originalBudget),
        approvedChanges: _sum((l) => l.approvedChanges),
        pendingChanges: _sum((l) => l.pendingChanges),
        poCommitted: _sum((l) => l.poCommitted),
        workOrderCommitted: _sum((l) => l.workOrderCommitted),
        actual: _sum((l) => l.actual),
        uncommitted: _sum((l) => l.uncommitted),
        sources: const [],
      );

  double _sum(double Function(CostLine) f) => _r2(lines.fold(0.0, (s, l) => s + f(l)));
}

/// Everything one site's budget lines are built from.
class CommercialData {
  CommercialData({
    required this.projectId,
    required this.costCodes,
    required this.workOrders,
    required this.claims,
    required this.certifications,
    required this.variations,
    required this.decisions,
    required this.attachments,
    required this.actions,
    required this.purchaseOrders,
    required this.receipts,
    required this.expenses,
    this.subcontractorNames = const {},
  });

  final String projectId;
  final List<CostCode> costCodes;
  final List<WorkOrder> workOrders;
  final List<WorkClaim> claims;
  final List<WorkCertification> certifications;
  final List<Variation> variations;
  final List<VariationDecision> decisions;
  final List<CommercialAttachment> attachments;
  final List<ExceptionAction> actions;
  final List<PurchaseOrder> purchaseOrders;
  final List<MaterialReceipt> receipts;
  final List<SiteExpense> expenses;
  final Map<String, String> subcontractorNames;

  late final Map<String, VariationDecision> decisionByVariation = decisionsById(decisions);

  WorkOrderPosition position(WorkOrder o) =>
      workOrderPosition(order: o, certifications: certifications, variations: variations, decisions: decisions);

  ClaimPosition claim(WorkClaim c) =>
      claimPosition(claim: c, certifications: certifications, variations: variations, decisions: decisions);

  List<CommercialAttachment> photosOf(String parentId) => attachments.where((a) => a.parentId == parentId).toList();

  WorkOrder? orderById(String? id) => id == null ? null : workOrders.where((o) => o.id == id).firstOrNull;
  WorkClaim? claimById(String? id) => id == null ? null : claims.where((c) => c.id == id).firstOrNull;
  Variation? variationById(String? id) => id == null ? null : variations.where((v) => v.id == id).firstOrNull;
  CostCode? costCodeById(String? id) => id == null ? null : costCodes.where((c) => c.id == id).firstOrNull;

  /// V-1, V-2... in the order they were raised on the site.
  String variationNo(Variation v) => 'V-${variations.indexWhere((x) => x.id == v.id) + 1}';

  /// C-1, C-2... certificates of one work order, in order.
  String certificateNo(WorkCertification c) {
    final mine = certifications.where((x) => x.workOrderId == c.workOrderId).toList();
    return 'C-${mine.indexWhere((x) => x.id == c.id) + 1}';
  }

  String? variationCostCode(Variation v) => v.costCodeId ?? orderById(v.workOrderId)?.costCodeId;

  CostReport costReport() {
    final lines = <String?, _LineBuilder>{for (final c in costCodes) c.id: _LineBuilder(c)};
    _LineBuilder line(String? id) => lines[lines.containsKey(id) ? id : null] ??= _LineBuilder(null);

    for (final o in workOrders.where((o) => o.status != 'cancelled')) {
      final p = position(o);
      final l = line(o.costCodeId);
      l.workOrderCommitted += p.openCommitment;
      l.actual += p.certifiedValue;
      l.sources.add(CostSource(CostSourceKind.workOrder, o.id,
          '${subcontractorNames[o.subcontractorId] ?? tr('Subcontractor')}: ${o.description}',
          committed: p.openCommitment, actual: p.certifiedValue));
    }
    for (final o in workOrders.where((o) => o.status == 'cancelled')) {
      // Work certified before the order was cancelled is still a cost.
      final p = position(o);
      if (p.certifiedValue > 0) {
        final l = line(o.costCodeId);
        l.actual += p.certifiedValue;
        l.sources.add(CostSource(CostSourceKind.workOrder, o.id, o.description, actual: p.certifiedValue));
      }
    }
    for (final po in purchaseOrders) {
      final received = receipts.where((r) => r.poId == po.id).fold(0.0, (s, r) => s + r.amount);
      final closed = po.status == 'delivered' || po.status == 'cancelled';
      final open = closed ? 0.0 : math.max(0.0, (po.totalAmount ?? 0) - received);
      final l = line(po.costCodeId);
      l.poCommitted += open;
      l.actual += received;
      l.sources.add(CostSource(CostSourceKind.purchaseOrder, po.id, po.poNumber ?? tr('Purchase order'),
          committed: _r2(open), actual: _r2(received)));
    }
    for (final e in expenses.where((e) => !e.voided && e.costCodeId != null)) {
      final l = line(e.costCodeId);
      l.actual += e.amount;
      l.sources.add(CostSource(CostSourceKind.expense, e.id, e.paidTo ?? e.category, actual: e.amount));
    }
    for (final v in variations) {
      final d = decisionByVariation[v.id];
      final l = line(variationCostCode(v));
      if (d == null) {
        l.pending += v.estimatedCost;
        l.sources.add(CostSource(CostSourceKind.variation, v.id, '${variationNo(v)} ${v.title}', change: 0));
      } else if (d.decision == 'approved') {
        l.approved += d.approvedCost ?? 0;
        l.sources.add(CostSource(CostSourceKind.variation, v.id, '${variationNo(v)} ${v.title}',
            change: d.approvedCost ?? 0));
      }
    }
    final ordered = [
      for (final c in costCodes) lines[c.id]!,
      if (lines[null] != null && !lines[null]!.isEmpty) lines[null]!,
    ];
    return CostReport([for (final b in ordered) b.build()]);
  }
}

class _LineBuilder {
  _LineBuilder(this.code);
  final CostCode? code;
  double approved = 0, pending = 0, poCommitted = 0, workOrderCommitted = 0, actual = 0;
  final sources = <CostSource>[];
  bool get isEmpty => sources.isEmpty;

  CostLine build() => CostLine(
        costCode: code,
        originalBudget: code?.originalBudget ?? 0,
        approvedChanges: _r2(approved),
        pendingChanges: _r2(pending),
        poCommitted: _r2(poCommitted),
        workOrderCommitted: _r2(workOrderCommitted),
        actual: _r2(actual),
        uncommitted: code?.uncommittedEstimate ?? 0,
        sources: sources,
      );
}

// --- Commercial exceptions inbox (FOS-204) ----------------------------------

enum ExceptionKind { beyondScope, aboveContract, overdueCertification, forecastOverrun, missingDayReport }

String exceptionKindLabel(ExceptionKind k) => switch (k) {
      ExceptionKind.beyondScope => tr('Work beyond approved scope'),
      ExceptionKind.aboveContract => tr('Quantity above contract'),
      ExceptionKind.overdueCertification => tr('Certification overdue'),
      ExceptionKind.forecastOverrun => tr('Forecast overrun'),
      // From the daily site close (features/daily/day_close_exceptions.dart).
      ExceptionKind.missingDayReport => tr('Daily report missing'),
    };

/// Which source record an exception points at.
enum ExceptionSource { claim, variation, costCode, dayClose }

class CommercialException {
  CommercialException({
    required this.key,
    required this.kind,
    required this.projectId,
    required this.title,
    required this.detail,
    required this.source,
    required this.sourceId,
    required this.defaultOwnerRole,
    required this.defaultDue,
    required this.fingerprint,
    this.amount,
  });

  final String key;
  final ExceptionKind kind;
  final String projectId;
  final String title;
  final String detail;
  final ExceptionSource source;
  final String sourceId;

  /// Who it belongs to until someone takes it: 'engineer' or 'manager'.
  final String defaultOwnerRole;
  final DateTime defaultDue;
  final String fingerprint;
  final double? amount;

  /// Filled in from the action trail by [withActions].
  String? ownerId;
  DateTime? due;
  ExceptionAction? resolution;
  List<ExceptionAction> trail = const [];

  DateTime get dueDate => due ?? defaultDue;
  bool get isResolved => resolution != null;
  bool isOverdue(DateTime now) => !isResolved && dueDate.isBefore(DateTime(now.year, now.month, now.day));
}

/// Days a claim may wait for the engineer before it is overdue.
const certificationDays = 7;

/// Days a variation may wait for a decision.
const variationDecisionDays = 7;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

List<CommercialException> commercialExceptions(CommercialData d, {required DateTime now}) {
  final out = <CommercialException>[];
  final today = _day(now);

  for (final c in d.claims) {
    final order = d.orderById(c.workOrderId);
    if (order == null) continue;
    final cp = d.claim(c);
    if (cp.settled) continue;
    final pos = d.position(order);
    final unit = order.unit ?? '';
    final who = d.subcontractorNames[order.subcontractorId] ?? tr('Subcontractor');
    if (cp.untouched && cp.open > pos.remainingQty + _eps) {
      out.add(CommercialException(
        key: 'above_contract:${c.id}',
        kind: ExceptionKind.aboveContract,
        projectId: d.projectId,
        title: trf('{who} claims {claimed} {unit}; {left} {unit} left on the order',
            {'who': who, 'claimed': fmtQty(cp.open), 'left': fmtQty(pos.remainingQty), 'unit': unit}),
        detail: order.description,
        source: ExceptionSource.claim,
        sourceId: c.id,
        defaultOwnerRole: 'engineer',
        defaultDue: _day(c.createdAt).add(const Duration(days: 3)),
        fingerprint: '${fmtQty(cp.open)}/${fmtQty(pos.remainingQty)}',
        amount: _r2((cp.open - pos.remainingQty) * pos.rate),
      ));
    }
    final waitingSince = cp.eligibleAfterApproval
        ? d.decisionByVariation[cp.variation!.id]!.createdAt
        : (cp.heldForVariation ? null : c.createdAt);
    if (waitingSince != null) {
      final due = _day(waitingSince).add(Duration(days: cp.eligibleAfterApproval ? 3 : certificationDays));
      if (!due.isAfter(today)) {
        out.add(CommercialException(
          key: 'overdue_certification:${c.id}',
          kind: ExceptionKind.overdueCertification,
          projectId: d.projectId,
          title: cp.eligibleAfterApproval
              ? trf('{qty} {unit} approved in {v} and not yet certified',
                  {'qty': fmtQty(cp.open), 'unit': unit, 'v': d.variationNo(cp.variation!)})
              : trf('{who}\'s claim of {qty} {unit} is waiting for certification', {'who': who, 'qty': fmtQty(cp.open), 'unit': unit}),
          detail: order.description,
          source: ExceptionSource.claim,
          sourceId: c.id,
          defaultOwnerRole: 'engineer',
          defaultDue: due,
          fingerprint: fmtQty(cp.open),
          amount: _r2(cp.open * pos.rate),
        ));
      }
    }
  }

  for (final v in d.variations) {
    if (d.decisionByVariation.containsKey(v.id)) continue;
    out.add(CommercialException(
      key: 'beyond_scope:${v.id}',
      kind: ExceptionKind.beyondScope,
      projectId: d.projectId,
      title: '${d.variationNo(v)} ${v.title}',
      detail: v.scheduleDays == 0
          ? tr('Waiting for a decision')
          : trf('Waiting for a decision. {days} days on the programme', {'days': v.scheduleDays}),
      source: ExceptionSource.variation,
      sourceId: v.id,
      defaultOwnerRole: 'manager',
      defaultDue: _day(v.createdAt).add(const Duration(days: variationDecisionDays)),
      fingerprint: v.id,
      amount: v.estimatedCost,
    ));
  }

  for (final line in d.costReport().lines) {
    final code = line.costCode;
    if (code == null || !line.isOver) continue;
    final touched = [
      code.updatedAt,
      ...d.certifications.where((c) => d.orderById(c.workOrderId)?.costCodeId == code.id).map((c) => c.createdAt),
      ...d.decisions.where((x) {
        final v = d.variationById(x.variationId);
        return v != null && d.variationCostCode(v) == code.id;
      }).map((x) => x.createdAt),
    ]..sort();
    out.add(CommercialException(
      key: 'forecast_overrun:${code.id}',
      kind: ExceptionKind.forecastOverrun,
      projectId: d.projectId,
      title: trf('{code} {name} is heading over budget', {'code': code.code, 'name': code.name}),
      detail: trf('Projected {projected} against {budget}', {
        'projected': rupees(line.projectedFinal),
        'budget': rupees(line.revisedBudget),
      }),
      source: ExceptionSource.costCode,
      sourceId: code.id,
      defaultOwnerRole: 'manager',
      defaultDue: _day(touched.last).add(const Duration(days: 7)),
      // A bigger overrun than the one that was accepted comes back.
      fingerprint: '${(line.overrun / 1000).ceil()}k',
      amount: line.overrun,
    ));
  }
  return withActions(out, d.actions);
}

/// Applies the trail: the latest assignment sets owner and due date; a
/// resolution counts while the exception still looks as it did then.
List<CommercialException> withActions(List<CommercialException> list, List<ExceptionAction> actions) {
  for (final e in list) {
    final trail = actions.where((a) => a.exceptionKey == e.key).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    e.trail = trail;
    for (final a in trail) {
      switch (a.action) {
        case 'assigned':
          e.ownerId = a.ownerId ?? e.ownerId;
          if (a.dueOn != null) e.due = DateTime.tryParse(a.dueOn!) ?? e.due;
        case 'resolved':
          e.resolution = a.fingerprint == null || a.fingerprint == e.fingerprint ? a : null;
        case 'reopened':
          e.resolution = null;
      }
    }
  }
  return list;
}
