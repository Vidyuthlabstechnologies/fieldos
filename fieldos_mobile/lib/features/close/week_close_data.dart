/// Loads a site's week from the phone's database, and records decisions on
/// it. The rules live in week_close.dart.
library;

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart' show weekStart, markDay;

Future<WeekClose> loadWeekClose(AppDatabase db, Project project, DateTime weekOf,
    {Set<String> unconfirmedVouchers = const {}, DateTime? now}) async {
  final slips = await db.materialDao.slipsForProject(project.id);
  return buildWeekClose(
    project: project,
    weekOf: weekOf,
    workers: await db.workerDao.forProject(project.id),
    punches: await db.attendanceDao.forProject(project.id),
    marks: await db.attendanceDao.marksForProject(project.id),
    expenses: await db.expenseDao.allForProject(project.id),
    receipts: await db.materialDao.forProject(project.id),
    orders: await db.purchaseDao.ordersFor(project.id),
    requests: await db.purchaseDao.requestsFor(project.id),
    reports: await db.dprDao.forProject(project.id),
    reviews: await db.closeDao.forWeek(project.id, markDay(weekStart(weekOf))),
    expenseBills: await db.expenseDao.attachmentCounts(project.id),
    receiptSlips: {for (final e in slips.entries) e.key: e.value.length},
    unconfirmedVouchers: unconfirmedVouchers,
    now: now,
  );
}

/// Thrown when someone tries a decision their role doesn't allow. The
/// server refuses it too (site_close_reviews' insert policy).
class CloseNotAllowed implements Exception {
  const CloseNotAllowed(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The decisions people make on a week. [role] is the app's role
/// (owner / manager / member / viewer).
class CloseActions {
  CloseActions(this.db, {required this.userId, required this.role});
  final AppDatabase db;
  final String userId;
  final String role;

  bool get canDecide => Roles.canApprove(role);
  bool get canFix => Roles.canWrite(role);

  void _mustDecide() {
    if (!canDecide) throw const CloseNotAllowed('Only the owner or a project manager can approve or send back.');
  }

  Future<CloseReview> approve(WeekClose w, CloseItem item, {double? acceptedQty, String? note, DateTime? now}) {
    _mustDecide();
    if (acceptedQty != null && acceptedQty < 0) throw ArgumentError('accepted quantity below zero');
    return db.closeDao.record(
      projectId: w.project.id,
      weekStart: w.weekKey,
      itemKind: item.kind.key,
      itemId: item.id,
      decision: 'approved',
      by: userId,
      note: note,
      fingerprint: item.fingerprint,
      amount: item.amount,
      acceptedQty: item.kind == CloseKind.receipt ? (acceptedQty ?? item.quantity) : null,
      now: now,
    );
  }

  /// Approves every item still waiting that has nothing flagged. Flagged
  /// ones need a person to look at them one by one.
  Future<int> approveClean(WeekClose w, {DateTime? now}) async {
    _mustDecide();
    var n = 0;
    for (final i in w.waiting.where((i) => !i.hasFlags)) {
      await approve(w, i, now: now);
      n++;
    }
    return n;
  }

  Future<CloseReview> sendBack(WeekClose w, CloseItem item, String note, {DateTime? now}) {
    _mustDecide();
    if (note.trim().isEmpty) throw ArgumentError('Say what needs fixing.');
    return db.closeDao.record(
      projectId: w.project.id,
      weekStart: w.weekKey,
      itemKind: item.kind.key,
      itemId: item.id,
      decision: 'sent_back',
      by: userId,
      note: note,
      fingerprint: item.fingerprint,
      amount: item.amount,
      now: now,
    );
  }

  /// The site says an item sent back is sorted (for a fix that changed
  /// nothing on record, such as "the bill is with the office").
  Future<CloseReview> markFixed(WeekClose w, CloseItem item, {String? note, DateTime? now}) {
    if (!canFix) throw const CloseNotAllowed('Viewers can\'t change the week.');
    return db.closeDao.record(
      projectId: w.project.id,
      weekStart: w.weekKey,
      itemKind: item.kind.key,
      itemId: item.id,
      decision: 'fixed',
      by: userId,
      note: note,
      fingerprint: item.fingerprint,
      amount: item.amount,
      now: now,
    );
  }

  Future<CloseReview> closeWeek(WeekClose w, {String? note, DateTime? now}) {
    _mustDecide();
    if (!w.canClose) throw StateError('Everything must be approved before the week is closed.');
    return db.closeDao.record(
      projectId: w.project.id,
      weekStart: w.weekKey,
      itemKind: 'week',
      itemId: 'week',
      decision: 'closed',
      by: userId,
      note: note,
      fingerprint: '${w.items.length}|${w.approvedTotal.toStringAsFixed(2)}',
      amount: w.approvedTotal,
      now: now,
    );
  }

  Future<CloseReview> reopen(WeekClose w, String note, {DateTime? now}) {
    _mustDecide();
    if (note.trim().isEmpty) throw ArgumentError('Say why the week is reopened.');
    return db.closeDao.record(
      projectId: w.project.id,
      weekStart: w.weekKey,
      itemKind: 'week',
      itemId: 'week',
      decision: 'reopened',
      by: userId,
      note: note,
      now: now,
    );
  }
}
