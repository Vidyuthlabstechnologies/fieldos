/// Loads a site's day from the phone's database, records what is said
/// about it, and builds the manager's board. The rules live in
/// day_close.dart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/close/week_close_data.dart';
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart' show markDay;
import 'package:fieldos_mobile/providers.dart';

/// Everything recorded on a site, loaded once for several days.
class SiteRecords {
  SiteRecords._(this.project, this.workers, this.punches, this.marks, this.receipts, this.expenses, this.reports,
      this.issues, this.events, this.settings);

  static Future<SiteRecords> load(AppDatabase db, Project project) async => SiteRecords._(
        project,
        await db.workerDao.forProject(project.id),
        await db.attendanceDao.forProject(project.id),
        await db.attendanceDao.marksForProject(project.id),
        await db.materialDao.forProject(project.id),
        await db.expenseDao.allForProject(project.id),
        await db.dprDao.forProject(project.id),
        await db.issueDao.forProject(project.id),
        await db.dayCloseDao.eventsFor(project.id),
        await db.dayCloseDao.settingsFor(project.id),
      );

  final Project project;
  final List<Worker> workers;
  final List<LabourAttendanceData> punches;
  final List<AttendanceMark> marks;
  final List<MaterialReceipt> receipts;
  final List<SiteExpense> expenses;
  final List<DprEntry> reports;
  final List<Issue> issues;
  final List<SiteDayEvent> events;
  final SiteCloseSetting? settings;

  CloseSetup get setup => CloseSetup.from(settings);

  DayClose day(DateTime d) => buildDayClose(
        snapshot: buildDaySnapshot(
          project: project,
          day: d,
          workers: workers,
          punches: punches,
          marks: marks,
          receipts: receipts,
          expenses: expenses,
          reports: reports,
        ),
        settings: settings,
        events: events,
      );

  List<DateTime> missed(DateTime now) => missedDays(events: events, setup: setup, now: now, since: trackingStart);

  /// When the site started using the daily close: its first submission,
  /// or when its cutoff and supervisor were first set. Earlier days are
  /// not held against anyone (a site that never used it has no misses,
  /// exceptions or held wages).
  DateTime? get trackingStart {
    DateTime? start = settings == null ? null : dayOf(settings!.updatedAt);
    for (final e in events) {
      if (e.kind != 'submitted') continue;
      final d = parseDay(e.workDate);
      if (d != null && (start == null || d.isBefore(start))) start = d;
    }
    return start;
  }
}

Future<DayClose> loadDayClose(AppDatabase db, Project project, DateTime day) async =>
    (await SiteRecords.load(db, project)).day(day);

/// Thrown when someone tries something their role doesn't allow. The
/// server refuses it too (site_day_events' and site_close_settings'
/// policies).
class DayCloseNotAllowed implements Exception {
  const DayCloseNotAllowed(this.message);
  final String message;
  @override
  String toString() => message;
}

class DayCloseActions {
  DayCloseActions(this.db, {required this.userId, required this.role});
  final AppDatabase db;
  final String userId;
  final String role;

  bool get canRecord => Roles.canWrite(role) && role != Roles.subcontractor;
  bool get canManage => Roles.canApprove(role);

  void _mustRecord() {
    if (!canRecord) throw const DayCloseNotAllowed("Viewers can't send the day's report.");
  }

  void _mustManage() {
    if (!canManage) throw const DayCloseNotAllowed('Only the owner or a project manager can do this.');
  }

  /// Sends the day. Everything on the checklist must be recorded or
  /// explicitly nothing.
  Future<SiteDayEvent> submit(DayClose d, NothingMarks n, {String? note, DateTime? now}) {
    _mustRecord();
    final missing = missingItems(d.snapshot, n);
    if (missing.isNotEmpty) throw StateError('Still missing: ${missing.map((k) => k.name).join(', ')}');
    return db.dayCloseDao.record(
      projectId: d.snapshot.project.id,
      workDate: d.dayKey,
      kind: 'submitted',
      by: userId,
      siteClosed: n.siteClosed,
      noDeliveries: n.noDeliveries && d.snapshot.receipts.isEmpty,
      noExpenses: n.noExpenses && d.snapshot.expenses.isEmpty,
      note: note,
      fingerprint: d.snapshot.fingerprint,
      now: now,
    );
  }

  /// Takes the day back to add or correct something; sending it again
  /// makes a new submission.
  Future<SiteDayEvent> reopen(DayClose d, {String? note, DateTime? now}) {
    _mustRecord();
    if (!d.isSubmitted) throw StateError('The day has not been sent.');
    return db.dayCloseDao.record(
        projectId: d.snapshot.project.id, workDate: d.dayKey, kind: 'reopened', by: userId, note: note, now: now);
  }

  /// Why the report was missed (the two-week pilot asks every time).
  Future<SiteDayEvent> recordMissReason(DayClose d, MissReason reason, {String? note, DateTime? now}) {
    _mustRecord();
    if (reason == MissReason.other && (note ?? '').trim().isEmpty) throw ArgumentError('Say what happened.');
    return db.dayCloseDao.record(
      projectId: d.snapshot.project.id,
      workDate: d.dayKey,
      kind: 'miss_reason',
      by: userId,
      reason: reason.key,
      note: note,
      now: now,
    );
  }

  /// The manager followed up (called, messaged) about a missing day.
  Future<SiteDayEvent> followUp(DayClose d, String note, {DateTime? now}) {
    _mustManage();
    if (note.trim().isEmpty) throw ArgumentError('Say what you did.');
    return db.dayCloseDao.record(
        projectId: d.snapshot.project.id, workDate: d.dayKey, kind: 'follow_up', by: userId, note: note, now: now);
  }

  Future<SiteCloseSetting> saveSetup(String projectId, CloseSetup s, {DateTime? now}) {
    _mustManage();
    return db.dayCloseDao.saveSettings(
      projectId: projectId,
      cutoffMinutes: s.cutoffMinutes,
      supervisorId: s.supervisorId,
      backupId: s.backupId,
      backupUntil: s.backupUntil == null ? null : markDay(s.backupUntil!),
      by: userId,
      now: now,
    );
  }

  /// Lets the verified part of a weekly item go ahead while the rest
  /// waits for its day reports. Recorded against the approver.
  Future<SiteDayEvent> releaseVerified(WeekVerification v, CloseItem item, {DateTime? now}) {
    _mustManage();
    final iv = v.of(item);
    if (iv == null || !iv.isPartial || iv.verified <= 0.005) throw StateError('Nothing verified to release.');
    return db.dayCloseDao.record(
      projectId: v.week.project.id,
      workDate: v.week.weekKey,
      kind: 'partial',
      by: userId,
      amount: iv.verified,
      itemRef: itemRef(item),
      fingerprint: item.fingerprint,
      note: 'held ${iv.unverified.toStringAsFixed(2)} for ${iv.unverifiedDays.map(markDay).join(',')}',
      now: now,
    );
  }

  /// Approves a weekly item in full although some of its days have no
  /// submitted report. The reason and the approver are recorded, on the
  /// override and on the approval itself.
  Future<CloseReview> overrideAndApprove(WeekVerification v, CloseItem item, String reason, {DateTime? now}) async {
    _mustManage();
    if (reason.trim().isEmpty) throw ArgumentError('Say why it is approved without the day reports.');
    final iv = v.of(item);
    await db.dayCloseDao.record(
      projectId: v.week.project.id,
      workDate: v.week.weekKey,
      kind: 'override',
      by: userId,
      amount: iv?.unverified ?? item.amount,
      itemRef: itemRef(item),
      fingerprint: item.fingerprint,
      note: reason,
      now: now,
    );
    return CloseActions(db, userId: userId, role: role)
        .approve(v.week, item, note: 'Override: ${reason.trim()}', now: now);
  }
}

/// A site's row on the manager's board.
class SiteDayRow {
  SiteDayRow({required this.records, required this.today, required this.yesterday, required this.missed});
  final SiteRecords records;
  final DayClose today;
  final DayClose yesterday;

  /// Missed days in the last two weeks.
  final List<DateTime> missed;

  Project get project => records.project;
  bool get isRepeat => missed.length >= repeatMissCount;
}

Future<List<SiteDayRow>> loadDayBoard(AppDatabase db, String companyId, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  final today = dayOf(t);
  final out = <SiteDayRow>[];
  for (final p in await db.projectDao.forCompany(companyId)) {
    if (p.status != 'active') continue;
    final r = await SiteRecords.load(db, p);
    out.add(SiteDayRow(
      records: r,
      today: r.day(today),
      yesterday: r.day(today.subtract(const Duration(days: 1))),
      missed: r.missed(t),
    ));
  }
  return out;
}

final dayBoardProvider = FutureProvider.autoDispose.family<List<SiteDayRow>, String>((ref, companyId) async {
  // Home's pull-to-refresh (and any site change) reloads the board too.
  await ref.watch(projectsProvider(companyId).future);
  return loadDayBoard(ref.watch(appDatabaseProvider), companyId);
});

final siteRecordsProvider = FutureProvider.autoDispose.family<SiteRecords, String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  final p = await db.projectDao.byId(projectId);
  if (p == null) throw StateError('Site not found');
  return SiteRecords.load(db, p);
});

/// When each teammate's phone last synced, by user id.
final memberSyncProvider =
    FutureProvider.autoDispose.family<Map<String, MemberSyncStatusData>, String>((ref, companyId) async {
  final rows = await ref.watch(appDatabaseProvider).dayCloseDao.syncStatusFor(companyId);
  return {for (final r in rows) r.userId: r};
});

/// Loads the weekly verification for a week close (used by the weekly
/// close screen).
Future<WeekVerification> loadWeekVerification(AppDatabase db, WeekClose w) async {
  final r = await SiteRecords.load(db, w.project);
  return verifyWeek(
    week: w,
    events: r.events,
    workers: r.workers,
    punches: r.punches,
    marks: r.marks,
    expenses: r.expenses,
    since: r.trackingStart,
  );
}

/// Whether the week [day] falls in is already closed: a late entry or
/// correction then goes back to the manager's weekly queue on its own.
Future<bool> weekAlreadyClosed(AppDatabase db, Project project, DateTime day) async =>
    (await loadWeekClose(db, project, day)).isClosed;
