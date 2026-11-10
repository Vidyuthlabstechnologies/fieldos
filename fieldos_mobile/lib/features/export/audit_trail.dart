/// The audit trail: every recorded decision and change of money on the
/// company's sites, in time order, for an auditor or the owner. It is read
/// from the records themselves (which are insert-only where it matters:
/// weekly-close reviews, approval signatures, measurement decisions, bill
/// allocations), so it can't drift from what happened.
///
/// One CSV row per event: when, site, who, what, the item, the amount and
/// the note, and the record's id to trace it.
library;

import 'package:drift/drift.dart';

import 'package:fieldos_mobile/data/app_database.dart';

class AuditEvent {
  const AuditEvent({
    required this.at,
    required this.projectId,
    required this.by,
    required this.action,
    required this.item,
    this.amount,
    this.note = '',
    required this.recordId,
  });
  final DateTime at;
  final String? projectId;

  /// A user id; names are filled in when written.
  final String by;
  final String action;
  final String item;
  final double? amount;
  final String note;
  final String recordId;
}

bool _inRange(DateTime d, DateTime? from, DateTime? to) =>
    (from == null || !d.isBefore(from)) && (to == null || d.isBefore(to));

String _decision(String d) => switch (d) {
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'sent_back' => 'Sent back',
      'fixed' => 'Marked fixed',
      'closed' => 'Week closed',
      'reopened' => 'Week reopened',
      _ => d,
    };

String _kind(String k) => switch (k) {
      'expense' => 'expense',
      'receipt' => 'delivery',
      'wages' => 'wages',
      'attendance' => 'attendance',
      'purchase_request' => 'purchase request',
      'purchase_order' => 'purchase order',
      'week' => 'week',
      _ => k.replaceAll('_', ' '),
    };

/// Everything on the company's sites between [from] and [to]. [moneyIn]:
/// whether client bills, payments received and allocations are included
/// (the same rule as the rest of the app: owners and managers only).
Future<List<AuditEvent>> buildAuditTrail(AppDatabase db, String companyId,
    {DateTime? from, DateTime? to, bool moneyIn = true}) async {
  final sites = await db.projectDao.forCompany(companyId);
  final ids = [for (final s in sites) s.id];
  final out = <AuditEvent>[];
  void add(AuditEvent e) {
    if (_inRange(e.at, from, to)) out.add(e);
  }

  if (ids.isEmpty) return out;

  for (final e in await (db.select(db.siteExpenses)..where((x) => x.projectId.isIn(ids))).get()) {
    final what = [e.category, if ((e.paidTo ?? '').trim().isNotEmpty) 'to ${e.paidTo!.trim()}'].join(' ');
    add(AuditEvent(at: e.createdAt, projectId: e.projectId, by: e.recordedBy, action: 'Expense recorded', item: what, amount: e.amount, recordId: e.id));
    if (e.editedAt != null) {
      add(AuditEvent(
          at: e.editedAt!,
          projectId: e.projectId,
          by: e.editedBy ?? '',
          action: e.voided ? 'Expense cancelled' : 'Expense changed',
          item: what,
          amount: e.amount,
          note: e.voidReason ?? '',
          recordId: e.id));
    }
  }
  for (final r in await (db.select(db.materialReceipts)..where((x) => x.projectId.isIn(ids))).get()) {
    add(AuditEvent(
        at: r.createdAt, projectId: r.projectId, by: r.receivedBy, action: 'Delivery recorded', item: r.materialName, amount: r.amount, recordId: r.id));
  }
  for (final r in await (db.select(db.purchaseRequests)..where((x) => x.projectId.isIn(ids))).get()) {
    add(AuditEvent(
        at: r.createdAt, projectId: r.projectId, by: r.raisedBy, action: 'Purchase request raised', item: r.materialName, amount: r.estimatedAmount, recordId: r.id));
  }
  for (final o in await (db.select(db.purchaseOrders)..where((x) => x.projectId.isIn(ids))).get()) {
    add(AuditEvent(
        at: o.createdAt, projectId: o.projectId, by: o.raisedBy, action: 'Purchase order raised', item: o.poNumber ?? '', amount: o.totalAmount, recordId: o.id));
  }
  for (final c in await (db.select(db.closeReviews)..where((x) => x.projectId.isIn(ids))).get()) {
    add(AuditEvent(
        at: c.createdAt,
        projectId: c.projectId,
        by: c.decidedBy,
        action: '${_decision(c.decision)} (${_kind(c.itemKind)}, weekly close)',
        item: 'Week of ${c.weekStart}',
        amount: c.amount,
        note: [if (c.acceptedQty != null) 'accepted ${c.acceptedQty}', if ((c.note ?? '').isNotEmpty) c.note!].join('; '),
        recordId: c.itemId));
  }
  for (final s in await (db.select(db.approvalSteps)..where((x) => x.projectId.isIn(ids))).get()) {
    add(AuditEvent(
        at: s.createdAt,
        projectId: s.projectId,
        by: s.decidedBy,
        action: '${_decision(s.decision)} as ${s.level == 'owner' ? 'owner' : 'project manager'} (${_kind(s.kind)})',
        item: '',
        amount: s.amount,
        note: s.note ?? '',
        recordId: s.itemId));
  }
  final measured = {
    for (final m in await (db.select(db.workMeasurements)..where((x) => x.projectId.isIn(ids))).get()) m.id: m,
  };
  for (final m in measured.values) {
    add(AuditEvent(
        at: m.createdAt, projectId: m.projectId, by: m.measuredBy, action: 'Work measured', item: '${m.description}: ${m.qty} ${m.unit}', recordId: m.id));
  }
  for (final d in await (db.select(db.workMeasurementDecisions)..where((x) => x.projectId.isIn(ids))).get()) {
    final m = measured[d.measurementId];
    add(AuditEvent(
        at: d.createdAt,
        projectId: d.projectId,
        by: d.decidedBy,
        action: '${_decision(d.decision)} (measurement)',
        item: m == null ? '' : '${m.description}: ${d.approvedQty ?? 0} of ${m.qty} ${m.unit}',
        note: d.note ?? '',
        recordId: d.measurementId));
  }
  for (final i in await (db.select(db.supplierInvoices)..where((x) => x.projectId.isIn(ids))).get()) {
    add(AuditEvent(
        at: i.createdAt,
        projectId: i.projectId,
        by: i.recordedBy,
        action: i.voided ? 'Supplier invoice recorded (since cancelled)' : 'Supplier invoice recorded',
        item: i.invoiceNumber,
        amount: i.amount,
        note: i.voidReason ?? '',
        recordId: i.id));
  }
  for (final a in await (db.select(db.approvals)..where((x) => x.projectId.isIn(ids) & x.decidedAt.isNotNull())).get()) {
    add(AuditEvent(
        at: a.decidedAt!,
        projectId: a.projectId,
        by: a.approverId ?? '',
        action: '${_decision(a.status)} (${_kind(a.entityType)})',
        item: '',
        note: a.decisionNote ?? '',
        recordId: a.entityId));
  }
  if (moneyIn) {
    for (final p in await (db.select(db.paymentsReceived)..where((x) => x.projectId.isIn(ids))).get()) {
      add(AuditEvent(at: p.createdAt, projectId: p.projectId, by: p.recordedBy, action: 'Payment received', item: p.fromParty, amount: p.amount, recordId: p.id));
      if (p.editedAt != null) {
        add(AuditEvent(
            at: p.editedAt!,
            projectId: p.projectId,
            by: p.editedBy ?? '',
            action: p.voided ? 'Payment cancelled' : 'Payment changed',
            item: p.fromParty,
            amount: p.amount,
            note: p.voidReason ?? '',
            recordId: p.id));
      }
    }
    for (final b in await (db.select(db.clientBills)..where((x) => x.projectId.isIn(ids))).get()) {
      add(AuditEvent(
          at: b.createdAt, projectId: b.projectId, by: b.recordedBy, action: 'Client bill raised', item: b.billNumber, amount: b.netPayable, recordId: b.id));
    }
    for (final a in await (db.select(db.billAllocations)..where((x) => x.projectId.isIn(ids))).get()) {
      add(AuditEvent(
          at: a.createdAt,
          projectId: a.projectId,
          by: a.createdBy,
          action: a.kind == 'retention' ? 'Retention released' : 'Payment put against a bill',
          item: '',
          amount: a.amount,
          note: a.note ?? '',
          recordId: a.billId));
    }
  }
  final rules = await (db.select(db.approvalRules)..where((r) => r.companyId.equals(companyId))).get();
  for (final r in rules) {
    final what = '${_kind(r.kind)}: ${r.role == 'owner' ? 'owner' : 'project manager'} above ${r.aboveAmount}';
    add(AuditEvent(at: r.createdAt, projectId: null, by: r.createdBy, action: 'Approval rule set', item: what, recordId: r.id));
    if (r.updatedAt.isAfter(r.createdAt.add(const Duration(seconds: 1)))) {
      add(AuditEvent(
          at: r.updatedAt, projectId: null, by: r.createdBy, action: r.voided ? 'Approval rule removed' : 'Approval rule changed', item: what, recordId: r.id));
    }
  }
  // Same time: the order they were read in (records before decisions).
  final order = {for (final (i, e) in out.indexed) e: i};
  out.sort((a, b) {
    final c = a.at.compareTo(b.at);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return out;
}

String _csv(String s) => s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;

String _time(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// The trail as CSV. [nameOf] turns a user id into a name or email;
/// [siteName] a project id into the site's name.
String auditCsv(List<AuditEvent> events, {required String Function(String id) nameOf, required Map<String, String> siteName}) {
  final rows = ['When,Site,Who,What,Item,Amount (₹),Note,Record'];
  for (final e in events) {
    rows.add([
      _time(e.at),
      _csv(e.projectId == null ? 'All sites' : siteName[e.projectId] ?? ''),
      _csv(e.by.isEmpty ? '' : nameOf(e.by)),
      _csv(e.action),
      _csv(e.item),
      e.amount == null ? '' : e.amount!.toStringAsFixed(2),
      _csv(e.note),
      e.recordId,
    ].join(','));
  }
  return '${rows.join('\n')}\n';
}
