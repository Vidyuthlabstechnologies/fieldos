/// The weekly site close: one review queue built from what the site already
/// recorded that week (the wage sheet, the money book, the deliveries and
/// the attendance), with every exception flagged, so a project manager can
/// approve what is payable, send back what is wrong, and hand accounts one
/// pack. Pure logic, so every rule can be tested.
///
/// Decisions are rows in CloseReviews, which are only ever added. An item's
/// state is its latest decision, checked against what the item looks like
/// now (its fingerprint): an approved expense that is edited afterwards
/// comes back to the queue instead of staying approved.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/money/money_book.dart' show voucherLabel;
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// What can be reviewed in a week.
enum CloseKind { wages, expense, receipt, attendance }

extension CloseKindName on CloseKind {
  String get key => name;
  static CloseKind? parse(String s) => CloseKind.values.where((k) => k.name == s).firstOrNull;
}

/// Where an item stands.
enum ItemState {
  /// Nobody has decided it yet.
  waiting,

  /// Approved, and unchanged since.
  approved,

  /// Sent back to the site with a note.
  sentBack,

  /// Sent back, then corrected (edited, or marked fixed): needs a look.
  fixed,

  /// Approved, then edited: needs a look again.
  changed,
}

/// Why an item needs a closer look.
enum CloseFlag {
  missingPunchOut,
  noWageRate,
  advance,
  noBill,
  unconfirmedVoucher,
  cancelled,
  editedAfterEntry,
  noPo,
  noSlip,
  shortDelivery,
  overDelivery,
  noInvoiceAmount,
  noAttendance,
  reportWithoutAttendance,
}

class FlagNote {
  const FlagNote(this.flag, {this.n = 0, this.amount = 0, this.qty = 0, this.unit = ''});
  final CloseFlag flag;
  final int n;
  final double amount;
  final double qty;
  final String unit;

  /// In the app's language.
  String get label => switch (flag) {
        CloseFlag.missingPunchOut => n == 1
            ? tr('Punch-out missing on 1 day')
            : trf('Punch-out missing on {n} days', {'n': n}),
        CloseFlag.noWageRate => tr('No daily wage set, so wages can\'t be worked out'),
        CloseFlag.advance => trf('Advance of {amount} not worked off yet', {'amount': rupees(amount)}),
        CloseFlag.noBill => tr('No bill photo'),
        CloseFlag.unconfirmedVoucher => tr('Voucher number not confirmed yet (not synced)'),
        CloseFlag.cancelled => tr('Cancelled entry'),
        CloseFlag.editedAfterEntry => tr('Edited after it was entered'),
        CloseFlag.noPo => tr('Not against a purchase order'),
        CloseFlag.noSlip => tr('No delivery slip photo'),
        CloseFlag.shortDelivery =>
          trf('Short by {qty} against the order', {'qty': [fmtQty(qty), unit].where((s) => s.isNotEmpty).join(' ')}),
        CloseFlag.overDelivery =>
          trf('{qty} more than ordered', {'qty': [fmtQty(qty), unit].where((s) => s.isNotEmpty).join(' ')}),
        CloseFlag.noInvoiceAmount => tr('No invoice amount'),
        CloseFlag.noAttendance => tr('No attendance recorded'),
        CloseFlag.reportWithoutAttendance =>
          trf('Report says {n} people, but no attendance', {'n': n}),
      };

  /// In English, for the pack accounts receives.
  String get english => switch (flag) {
        CloseFlag.missingPunchOut => n == 1 ? 'Punch-out missing on 1 day' : 'Punch-out missing on $n days',
        CloseFlag.noWageRate => 'No daily wage set',
        CloseFlag.advance => 'Advance of ${rupees(amount)} not worked off yet',
        CloseFlag.noBill => 'No bill photo',
        CloseFlag.unconfirmedVoucher => 'Voucher number not confirmed',
        CloseFlag.cancelled => 'Cancelled entry',
        CloseFlag.editedAfterEntry => 'Edited after entry',
        CloseFlag.noPo => 'Not against a PO',
        CloseFlag.noSlip => 'No delivery slip photo',
        CloseFlag.shortDelivery => 'Short by ${[fmtQty(qty), unit].where((s) => s.isNotEmpty).join(' ')} against the PO',
        CloseFlag.overDelivery => '${[fmtQty(qty), unit].where((s) => s.isNotEmpty).join(' ')} more than ordered',
        CloseFlag.noInvoiceAmount => 'No invoice amount',
        CloseFlag.noAttendance => 'No attendance recorded',
        CloseFlag.reportWithoutAttendance => 'Report says $n people, no attendance',
      };
}

class CloseItem {
  CloseItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.detail,
    required this.fingerprint,
    required this.flags,
    required this.day,
    this.amount,
    this.quantity,
    this.unit = '',
    this.orderedQty,
    this.wage,
    this.expense,
    this.receipt,
    this.evidence = 0,
  });

  final CloseKind kind;
  final String id;
  final String title;
  final String detail;

  /// What the item looks like now, to tell whether it changed after a
  /// decision.
  final String fingerprint;
  final List<FlagNote> flags;

  /// The day it belongs to (for sorting); the week's Monday for wages.
  final DateTime day;
  final double? amount;

  /// For a delivery: what came, and what the order asked for.
  final double? quantity;
  final String unit;
  final double? orderedQty;
  final WageLine? wage;
  final SiteExpense? expense;
  final MaterialReceipt? receipt;

  /// Bill or slip photos behind it.
  final int evidence;

  ItemState state = ItemState.waiting;

  /// Every decision on it this week, oldest first.
  final List<CloseReview> history = [];

  CloseReview? get last => history.isEmpty ? null : history.last;

  /// The quantity the manager accepted, when it was approved with one.
  double? get acceptedQty {
    for (final r in history.reversed) {
      if (r.decision == 'approved') return r.acceptedQty;
    }
    return null;
  }

  bool get needsDecision => state == ItemState.waiting || state == ItemState.fixed || state == ItemState.changed;
  bool get hasFlags => flags.isNotEmpty;
}

class WeekClose {
  WeekClose({
    required this.project,
    required this.from,
    required this.items,
    required this.history,
    required this.sheet,
  });

  final Project project;

  /// Monday 00:00 of the week.
  final DateTime from;
  DateTime get to => from.add(const Duration(days: 7));
  String get weekKey => markDay(from);
  final List<CloseItem> items;

  /// Every decision this week, oldest first.
  final List<CloseReview> history;
  final WageSheet sheet;

  /// The latest close or reopen, if any.
  CloseReview? get weekDecision {
    for (final r in history.reversed) {
      if (r.itemKind == 'week') return r;
    }
    return null;
  }

  bool get isClosed => weekDecision?.decision == 'closed';

  List<CloseItem> get waiting => [for (final i in items) if (i.needsDecision) i];
  List<CloseItem> get sentBack => [for (final i in items) if (i.state == ItemState.sentBack) i];
  List<CloseItem> get approved => [for (final i in items) if (i.state == ItemState.approved) i];
  List<CloseItem> get flagged => [for (final i in items) if (i.hasFlags) i];

  /// Everything decided, nothing sent back, not closed yet.
  bool get canClose => !isClosed && waiting.isEmpty && sentBack.isEmpty;

  /// Closed, but something changed or arrived since (a late entry synced
  /// in, an approved expense edited).
  bool get changedSinceClose => isClosed && (waiting.isNotEmpty || sentBack.isNotEmpty);

  double get wagesEarned => sheet.totalEarned;
  double get wagesPaid => sheet.totalPaid;
  double get wagesDue => sheet.totalDue;
  double get advancesOut =>
      sheet.lines.fold(0.0, (s, l) => s + (l.balanceDue < 0 ? -l.balanceDue : 0));
  double get expensesTotal => items
      .where((i) => i.kind == CloseKind.expense && !(i.expense?.voided ?? false))
      .fold(0.0, (s, i) => s + (i.amount ?? 0));
  double get receiptsTotal =>
      items.where((i) => i.kind == CloseKind.receipt).fold(0.0, (s, i) => s + (i.amount ?? 0));

  /// Approved items' money: wages earned, expenses, delivery invoices.
  double get approvedTotal => approved
      .where((i) => i.kind != CloseKind.attendance && !(i.expense?.voided ?? false))
      .fold(0.0, (s, i) => s + (i.amount ?? 0));
}

String _f(double? v) => v == null ? '-' : v.toStringAsFixed(2);

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Fingerprints: the fields that make an item what was approved.
String wageFingerprint(WageLine l) => 'd${_f(l.days)}|e${_f(l.earned)}|p${_f(l.paidInPeriod)}';

String expenseFingerprint(SiteExpense e) =>
    'a${_f(e.amount)}|c${e.category}|w${e.workerId ?? ''}|t${e.paidTo ?? ''}|d${e.incurredOn}|x${e.voided ? 1 : 0}';

String receiptFingerprint(MaterialReceipt r) =>
    'q${_f(r.quantity)}|a${_f(r.amount)}|m${r.materialName.trim().toLowerCase()}|u${(r.unit ?? '').trim().toLowerCase()}|o${r.poId ?? ''}';

String attendanceFingerprint(int people, int reported) => 'p$people|r$reported';

/// Builds a site's week. [expenseBills] and [receiptSlips] count the photos
/// behind each expense and receipt; [unconfirmedVouchers] are expenses the
/// server has not numbered yet. Days after [now] are not checked for
/// attendance.
WeekClose buildWeekClose({
  required Project project,
  required DateTime weekOf,
  required List<Worker> workers,
  required List<LabourAttendanceData> punches,
  required List<AttendanceMark> marks,
  required List<SiteExpense> expenses,
  required List<MaterialReceipt> receipts,
  required List<PurchaseOrder> orders,
  required List<PurchaseRequest> requests,
  required List<DprEntry> reports,
  required List<CloseReview> reviews,
  Map<String, int> expenseBills = const {},
  Map<String, int> receiptSlips = const {},
  Set<String> unconfirmedVouchers = const {},
  DateTime? now,
}) {
  final from = weekStart(weekOf);
  final to = from.add(const Duration(days: 7));
  final at = now ?? DateTime.now();
  bool inWeek(DateTime d) => !d.isBefore(from) && d.isBefore(to);

  final sheet = buildWageSheet(
      workers: workers,
      punches: punches,
      expenses: [for (final e in expenses) if (!e.voided) e],
      from: from,
      to: to,
      marks: marks);
  final items = <CloseItem>[];

  // Wages: one item per worker who worked or was paid this week.
  for (final l in sheet.lines) {
    if (l.days <= 0 && l.paidInPeriod <= 0 && l.missingPunchOuts == 0) continue;
    final flags = [
      if (l.missingPunchOuts > 0) FlagNote(CloseFlag.missingPunchOut, n: l.missingPunchOuts),
      if (l.dailyWage == null && l.days > 0) const FlagNote(CloseFlag.noWageRate),
      if (l.balanceDue < -0.005) FlagNote(CloseFlag.advance, amount: -l.balanceDue),
    ];
    final days = l.days == l.days.roundToDouble() ? l.days.toInt().toString() : l.days.toStringAsFixed(1);
    items.add(CloseItem(
      kind: CloseKind.wages,
      id: l.key,
      title: l.name,
      detail: [
        trf('{n} days', {'n': days}),
        if (l.dailyWage != null) trf('earned {amount}', {'amount': rupees(l.earned)}),
        if (l.paidInPeriod > 0) trf('paid {amount}', {'amount': rupees(l.paidInPeriod)}),
        if (l.balanceDue > 0.005) trf('due {amount}', {'amount': rupees(l.balanceDue)}),
      ].join(' · '),
      fingerprint: wageFingerprint(l),
      flags: flags,
      day: from,
      amount: l.earned,
      wage: l,
    ));
  }

  // Expenses entered for this week, cancelled ones too (accounts needs to
  // know a voucher number was voided).
  for (final e in expenses) {
    final on = DateTime.tryParse(e.incurredOn) ?? e.createdAt;
    final d = _day(on);
    if (!inWeek(d)) continue;
    final bills = expenseBills[e.id] ?? 0;
    final flags = [
      if (e.voided) const FlagNote(CloseFlag.cancelled),
      // A worker's wage or advance is backed by the wage sheet, not a bill.
      if (!e.voided && bills == 0 && e.workerId == null) const FlagNote(CloseFlag.noBill),
      if (unconfirmedVouchers.contains(e.id)) const FlagNote(CloseFlag.unconfirmedVoucher),
      if (e.editedAt != null && !e.voided) const FlagNote(CloseFlag.editedAfterEntry),
    ];
    final payee = e.paidTo?.trim() ?? '';
    items.add(CloseItem(
      kind: CloseKind.expense,
      id: e.id,
      title: [voucherLabel(e.voucherNo), tr(e.category)].where((s) => s.isNotEmpty).join(' · '),
      detail: [
        fmtDate(d, short: true),
        if (payee.isNotEmpty) payee,
        if ((e.note ?? '').trim().isNotEmpty) e.note!.trim(),
      ].join(' · '),
      fingerprint: expenseFingerprint(e),
      flags: flags,
      day: d,
      amount: e.amount,
      expense: e,
      evidence: bills,
    ));
  }

  // Deliveries, checked against their order.
  final requestById = {for (final r in requests) r.id: r};
  final orderById = {for (final o in orders) o.id: o};
  for (final r in receipts) {
    final d = _day(r.receivedOn);
    if (!inWeek(d)) continue;
    final order = r.poId == null ? null : orderById[r.poId];
    final request = order?.requestId == null ? null : requestById[order!.requestId];
    final unit = (r.unit ?? '').trim().isNotEmpty ? r.unit!.trim() : (request?.unit ?? '').trim();
    final slips = receiptSlips[r.id] ?? 0;
    final flags = <FlagNote>[
      if (r.poId == null) const FlagNote(CloseFlag.noPo),
      if (slips == 0) const FlagNote(CloseFlag.noSlip),
      if (r.amount <= 0) const FlagNote(CloseFlag.noInvoiceAmount),
    ];
    double? ordered;
    if (order != null && request != null && request.quantity > 0) {
      ordered = request.quantity;
      // Everything received on this order up to and including this delivery.
      final upTo = receipts.where((x) => x.poId == order.id && !x.receivedOn.isAfter(r.receivedOn));
      final got = upTo.fold(0.0, (s, x) => s + x.quantity);
      final isLast = !receipts.any((x) => x.poId == order.id && x.receivedOn.isAfter(r.receivedOn));
      final closed = closedOrderStatuses.contains(order.status);
      if (got > ordered + 0.0001) {
        flags.add(FlagNote(CloseFlag.overDelivery, qty: got - ordered, unit: unit));
      } else if (closed && isLast && got < ordered - 0.0001) {
        // The order was closed short: what never came.
        flags.add(FlagNote(CloseFlag.shortDelivery, qty: ordered - got, unit: unit));
      }
    }
    items.add(CloseItem(
      kind: CloseKind.receipt,
      id: r.id,
      title: [r.materialName.trim(), fmtQty(r.quantity), unit].where((s) => s.isNotEmpty).join(' '),
      detail: [
        fmtDate(d, short: true),
        if (ordered != null) trf('ordered {qty}', {'qty': [fmtQty(ordered), unit].where((s) => s.isNotEmpty).join(' ')}),
        if (order?.poNumber != null && order!.poNumber!.trim().isNotEmpty) order.poNumber!.trim(),
      ].join(' · '),
      fingerprint: receiptFingerprint(r),
      flags: flags,
      day: d,
      amount: r.amount,
      quantity: r.quantity,
      unit: unit,
      orderedQty: ordered,
      receipt: r,
      evidence: slips,
    ));
  }

  // Working days (Monday to Saturday, up to today) with no attendance at
  // all, on a site that has workers or sent a report that day.
  final hasWorkers = workers.any((w) => w.status == 'active');
  final marked = marksByWorker(marks);
  for (var i = 0; i < 6; i++) {
    final d = from.add(Duration(days: i));
    if (d.isAfter(_day(at))) break;
    final punched = punches.where((p) => _day(p.punchIn) == d).map((p) => p.workerId ?? p.workerName).toSet();
    final handMarked = marked.values.where((byDay) => (byDay[d] ?? 0) > 0).length;
    final people = punched.length + handMarked;
    if (people > 0) continue;
    final reported = reports
        .where((r) => _day(r.entryDate) == d)
        .fold(0, (s, r) => s > r.manpowerCount ? s : r.manpowerCount);
    if (!hasWorkers && reported == 0) continue;
    // Today is still being recorded: only a report with people on it counts.
    if (d == _day(at) && reported == 0) continue;
    items.add(CloseItem(
      kind: CloseKind.attendance,
      id: markDay(d),
      title: fmtDay(d),
      detail: fmtDate(d, short: true),
      fingerprint: attendanceFingerprint(people, reported),
      flags: [
        reported > 0 ? FlagNote(CloseFlag.reportWithoutAttendance, n: reported) : const FlagNote(CloseFlag.noAttendance),
      ],
      day: d,
    ));
  }

  // Wages first, then the days in order.
  const kindOrder = {CloseKind.wages: 0, CloseKind.attendance: 1, CloseKind.expense: 2, CloseKind.receipt: 3};
  items.sort((a, b) {
    final k = kindOrder[a.kind]!.compareTo(kindOrder[b.kind]!);
    if (k != 0) return k;
    final d = a.day.compareTo(b.day);
    return d != 0 ? d : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });

  // [reviews] come oldest first (CloseDao.forWeek); their order is kept
  // as given, since two decisions can share a second.
  final mine = reviews.where((r) => r.projectId == project.id && r.weekStart == markDay(from)).toList();
  final byKey = {for (final i in items) '${i.kind.key}:${i.id}': i};
  for (final r in mine) {
    byKey['${r.itemKind}:${r.itemId}']?.history.add(r);
  }
  for (final i in items) {
    i.state = itemState(i.history, i.fingerprint);
  }

  return WeekClose(project: project, from: from, items: items, history: mine, sheet: sheet);
}

/// Where an item stands, from its decisions and what it looks like now.
ItemState itemState(List<CloseReview> history, String fingerprint) {
  if (history.isEmpty) return ItemState.waiting;
  final last = history.last;
  switch (last.decision) {
    case 'approved':
      return last.fingerprint == null || last.fingerprint == fingerprint ? ItemState.approved : ItemState.changed;
    case 'sent_back':
      // Corrected on the site since it was sent back.
      return last.fingerprint != null && last.fingerprint != fingerprint ? ItemState.fixed : ItemState.sentBack;
    case 'fixed':
      return ItemState.fixed;
    default:
      return ItemState.waiting;
  }
}

/// Words for a decision, in the app's language.
String decisionLabel(String decision) => switch (decision) {
      'approved' => tr('Approved'),
      'sent_back' => tr('Sent back'),
      'fixed' => tr('Marked fixed'),
      'closed' => tr('Week closed'),
      'reopened' => tr('Week reopened'),
      _ => decision,
    };

String decisionEnglish(String decision) => switch (decision) {
      'approved' => 'Approved',
      'sent_back' => 'Sent back',
      'fixed' => 'Marked fixed',
      'closed' => 'Week closed',
      'reopened' => 'Week reopened',
      _ => decision,
    };

String stateLabel(ItemState s) => switch (s) {
      ItemState.waiting => tr('To review'),
      ItemState.approved => tr('Approved'),
      ItemState.sentBack => tr('Sent back'),
      ItemState.fixed => tr('Corrected, review again'),
      ItemState.changed => tr('Changed after approval'),
    };

String kindLabel(CloseKind k) => switch (k) {
      CloseKind.wages => tr('Wages'),
      CloseKind.expense => tr('Expenses'),
      CloseKind.receipt => tr('Deliveries'),
      CloseKind.attendance => tr('Attendance'),
    };
