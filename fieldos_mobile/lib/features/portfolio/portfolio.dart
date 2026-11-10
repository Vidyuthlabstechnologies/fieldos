/// The portfolio view: every running site on one screen, with what is
/// missing, what is waiting too long, and what money is outstanding. For a
/// company running many sites, it answers "where do I look first?".
library;

import 'package:drift/drift.dart' show Value;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart' show weekStart;
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';

/// An approval or a week's close is overdue after this long.
const overdueAfter = Duration(hours: 48);

class SiteStatus {
  const SiteStatus({
    required this.project,
    required this.missingReportDays,
    required this.closeWaiting,
    required this.closeSentBack,
    required this.weekClosed,
    required this.lastWeekOpen,
    required this.overdueApprovals,
    required this.wagesDue,
    required this.supplierDue,
    required this.clientReceivable,
    required this.retentionHeld,
  });

  final Project project;

  /// Days this week (Mon to Sat, up to yesterday) with no daily report.
  final List<DateTime> missingReportDays;
  final int closeWaiting;
  final int closeSentBack;
  final bool weekClosed;

  /// Last week still not closed, though it had items.
  final bool lastWeekOpen;

  /// Approvals waiting longer than [overdueAfter].
  final int overdueApprovals;

  /// Wages earned this week and not yet paid.
  final double wagesDue;

  /// What the site's deliveries still owe suppliers (opening balances are
  /// company-wide and not in here).
  final double supplierDue;

  /// Billed to the client and not yet received.
  final double clientReceivable;

  /// Kept back from the client's bills as retention.
  final double retentionHeld;

  /// How badly the site needs someone; 0 is all well.
  int get weight =>
      missingReportDays.length * 2 +
      closeSentBack * 2 +
      closeWaiting +
      overdueApprovals * 2 +
      (lastWeekOpen ? 3 : 0);

  bool get allWell => weight == 0;
}

/// Days from Monday of [now]'s week up to yesterday, Sundays left out,
/// with no report in [reports].
List<DateTime> missingReportDays(List<DprEntry> reports, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final from = weekStart(now);
  final have = {for (final r in reports) _day(r.entryDate.toLocal())};
  return [
    for (var d = from; d.isBefore(today); d = DateTime(d.year, d.month, d.day + 1))
      if (d.weekday != DateTime.sunday && !have.contains(d)) d,
  ];
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Billed less received, never below zero; and retention kept back.
({double receivable, double retention}) clientMoney(List<ClientBill> bills, List<PaymentsReceivedData> payments) {
  final billed = bills.fold<double>(0, (s, b) => s + b.netPayable);
  final received = payments.where((p) => !p.voided).fold<double>(0, (s, p) => s + p.amount);
  final retention = bills.fold<double>(0, (s, b) => s + b.gross * b.retentionPct / 100);
  final due = billed - received;
  return (receivable: due > 0.005 ? due : 0, retention: retention);
}

Future<SiteStatus> buildSiteStatus(AppDatabase db, Project project, {required List<Supplier> suppliers, DateTime? now}) async {
  final at = now ?? DateTime.now();
  final week = await loadWeekClose(db, project, at, now: at);
  final last = await loadWeekClose(db, project, weekStart(at).subtract(const Duration(days: 7)), now: at);
  final pending = await db.approvalDao.pendingFor(project.id);
  final overdue = pending.where((a) => at.difference(a.createdAt) > overdueAfter).length;

  // The site's own dues to suppliers: its orders, deliveries and payments,
  // without the company-wide opening balances.
  final ledgers = supplierLedgers(
    await db.purchaseDao.ordersFor(project.id),
    await db.materialDao.forProject(project.id),
    at,
    suppliers: [for (final s in suppliers) s.copyWith(openingBalance: const Value(null))],
    expenses: await db.expenseDao.forProject(project.id),
  );
  final supplierDue = ledgers.values.fold<double>(0, (s, l) => s + (l.balance > 0 ? l.balance : 0));
  final money = clientMoney(await db.billDao.forProject(project.id), await db.paymentDao.forProject(project.id));

  return SiteStatus(
    project: project,
    missingReportDays: missingReportDays(await db.dprDao.forProject(project.id), at),
    closeWaiting: week.waiting.length,
    closeSentBack: week.sentBack.length,
    weekClosed: week.isClosed,
    lastWeekOpen: !last.isClosed && last.items.isNotEmpty,
    overdueApprovals: overdue,
    wagesDue: week.sheet.totalDue,
    supplierDue: supplierDue,
    clientReceivable: money.receivable,
    retentionHeld: money.retention,
  );
}

/// Every running site, the ones that need someone first. [visible]: the
/// sites this person may see (members-only sites they aren't on are left
/// out); null means all.
Future<List<SiteStatus>> buildPortfolio(AppDatabase db, String companyId, {Set<String>? visible, DateTime? now}) async {
  final suppliers = await db.supplierDao.forCompany(companyId);
  final sites = (await db.projectDao.forCompany(companyId))
      .where((p) => p.status == 'active' && (visible == null || visible.contains(p.id)));
  final out = [for (final p in sites) await buildSiteStatus(db, p, suppliers: suppliers, now: now)];
  out.sort((a, b) {
    final c = b.weight.compareTo(a.weight);
    return c != 0 ? c : a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());
  });
  return out;
}

class PortfolioTotals {
  const PortfolioTotals(this.sites);
  final List<SiteStatus> sites;
  int get needingAttention => sites.where((s) => !s.allWell).length;
  int get missingReports => sites.fold(0, (n, s) => n + s.missingReportDays.length);
  int get overdueApprovals => sites.fold(0, (n, s) => n + s.overdueApprovals);
  int get weeksOpen => sites.where((s) => s.lastWeekOpen).length;
  double get wagesDue => sites.fold(0, (n, s) => n + s.wagesDue);
  double get supplierDue => sites.fold(0, (n, s) => n + s.supplierDue);
  double get clientReceivable => sites.fold(0, (n, s) => n + s.clientReceivable);
  double get retentionHeld => sites.fold(0, (n, s) => n + s.retentionHeld);
}
