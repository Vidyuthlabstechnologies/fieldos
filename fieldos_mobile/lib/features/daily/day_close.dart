/// The daily site close: by the site's cutoff, the supervisor confirms the
/// day from what is already recorded (attendance, deliveries, expenses and
/// the work report), says "nothing" out loud where there was nothing, and
/// sends the WhatsApp report FieldOS writes from it. The manager then sees
/// "submitted", "report not received · last synced at 2:10 pm" or "site
/// closed", never an empty register that could mean either.
///
/// Pure logic, so every rule can be tested. Events are rows in
/// SiteDayEvents, which are only ever added.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// The default cutoff: 7 pm.
const defaultCutoffMinutes = 19 * 60;

/// When a day still not submitted becomes an exception: 9 am the next day.
const exceptionHour = 9;

/// Misses in [repeatWindowDays] that count as a pattern, not a slip.
const repeatMissCount = 3;
const repeatWindowDays = 14;

DateTime dayOf(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime? parseDay(String s) {
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// Why a report was missed, for the two-week pilot. Each needs a
/// different fix: a better reminder, offline sending, or less to type.
enum MissReason { forgot, poorSignal, tooMuchWork, other }

extension MissReasonKey on MissReason {
  String get key => switch (this) {
        MissReason.forgot => 'forgot',
        MissReason.poorSignal => 'poor_signal',
        MissReason.tooMuchWork => 'too_much_work',
        MissReason.other => 'other',
      };
  static MissReason? parse(String? s) => MissReason.values.where((r) => r.key == s).firstOrNull;
}

String missReasonLabel(MissReason r) => switch (r) {
      MissReason.forgot => tr('Forgot'),
      MissReason.poorSignal => tr('Poor signal'),
      MissReason.tooMuchWork => tr('Too much work to enter'),
      MissReason.other => tr('Something else'),
    };

/// A site's close setup, with its defaults when none is saved.
class CloseSetup {
  const CloseSetup({this.cutoffMinutes = defaultCutoffMinutes, this.supervisorId, this.backupId, this.backupUntil});

  factory CloseSetup.from(SiteCloseSetting? s) => s == null
      ? const CloseSetup()
      : CloseSetup(
          cutoffMinutes: s.cutoffMinutes,
          supervisorId: s.supervisorId,
          backupId: s.backupId,
          backupUntil: s.backupUntil == null ? null : parseDay(s.backupUntil!),
        );

  final int cutoffMinutes;
  final String? supervisorId;
  final String? backupId;

  /// Inclusive.
  final DateTime? backupUntil;

  DateTime cutoffOn(DateTime day) => dayOf(day).add(Duration(minutes: cutoffMinutes));
  DateTime exceptionAt(DateTime day) => dayOf(day).add(const Duration(days: 1, hours: exceptionHour));

  bool backupActiveOn(DateTime day) =>
      backupId != null && (backupUntil == null || !dayOf(day).isAfter(backupUntil!));

  /// Who the day's report is expected from: the backup while they cover,
  /// otherwise the supervisor. Null when nobody is named (then anyone on
  /// the site may send it, and the reminder goes to everyone who records).
  String? responsibleOn(DateTime day) => backupActiveOn(day) ? backupId : supervisorId;

  /// Whether [userId] should get the cutoff reminder for the site.
  bool remindsUser(String userId, DateTime day, {required bool canRecord}) {
    final r = responsibleOn(day);
    return r == null ? canRecord : r == userId;
  }
}

/// One line of the Today checklist.
enum CheckKind { attendance, deliveries, expenses, work }

enum CheckState {
  /// Something is recorded.
  recorded,

  /// Explicitly nothing (or the site was closed).
  nothing,

  /// Neither: this is what the reminder lists.
  missing,
}

class CheckItem {
  const CheckItem(this.kind, this.state, {this.count = 0, this.amount = 0});
  final CheckKind kind;
  final CheckState state;
  final int count;
  final double amount;
}

String checkLabel(CheckKind k) => switch (k) {
      CheckKind.attendance => tr('Attendance'),
      CheckKind.deliveries => tr('Deliveries'),
      CheckKind.expenses => tr('Expenses'),
      CheckKind.work => tr('Work done'),
    };

/// A record of the day as it will appear in the report, with when and by
/// whom it was entered (it may be the next morning).
class DayEntry {
  const DayEntry({required this.kind, required this.title, required this.workDay, required this.enteredAt, required this.by});
  final CheckKind kind;
  final String title;
  final DateTime workDay;
  final DateTime enteredAt;
  final String by;

  /// Entered on a later day than the work it records.
  bool get isBackdated => dayOf(enteredAt).isAfter(workDay);
}

/// Everything recorded for one site on one day.
class DaySnapshot {
  DaySnapshot({
    required this.project,
    required this.day,
    required this.people,
    required this.receipts,
    required this.expenses,
    required this.reports,
    required this.entries,
  });

  final Project project;
  final DateTime day;

  /// Names of the people who worked, punched in or marked present.
  final List<String> people;
  final List<MaterialReceipt> receipts;

  /// Not cancelled.
  final List<SiteExpense> expenses;
  final List<DprEntry> reports;
  final List<DayEntry> entries;

  double get expenseTotal => expenses.fold(0.0, (s, e) => s + e.amount);
  int get reportedPeople => reports.fold(0, (s, r) => s > r.manpowerCount ? s : r.manpowerCount);

  /// What a submission covers: if any of it changes afterwards, the
  /// manager sees "changed after it was sent".
  String get fingerprint =>
      'p${people.length}|d${receipts.length}|e${expenseTotal.toStringAsFixed(2)}|w${reports.length}';

  List<DayEntry> get backdated => [for (final e in entries) if (e.isBackdated) e];
}

DaySnapshot buildDaySnapshot({
  required Project project,
  required DateTime day,
  required List<Worker> workers,
  required List<LabourAttendanceData> punches,
  required List<AttendanceMark> marks,
  required List<MaterialReceipt> receipts,
  required List<SiteExpense> expenses,
  required List<DprEntry> reports,
}) {
  final d = dayOf(day);
  final names = {for (final w in workers) w.id: w.name};
  final people = <String, String>{};
  final entries = <DayEntry>[];
  for (final p in punches.where((p) => p.projectId == project.id && dayOf(p.punchIn) == d)) {
    final key = p.workerId ?? 'name:${p.workerName.trim().toLowerCase()}';
    if (people.containsKey(key)) continue;
    people[key] = p.workerId == null ? p.workerName.trim() : (names[p.workerId] ?? p.workerName.trim());
    entries.add(DayEntry(
        kind: CheckKind.attendance, title: people[key]!, workDay: d, enteredAt: p.createdAt, by: p.recordedBy));
  }
  for (final m in marks.where((m) => m.projectId == project.id && (m.units ?? 0) > 0 && parseDay(m.day) == d)) {
    if (people.containsKey(m.workerId)) continue;
    people[m.workerId] = names[m.workerId] ?? tr('Worker');
    entries.add(DayEntry(
        kind: CheckKind.attendance, title: people[m.workerId]!, workDay: d, enteredAt: m.updatedAt, by: m.recordedBy));
  }
  final dayReceipts = [for (final r in receipts) if (r.projectId == project.id && dayOf(r.receivedOn) == d) r];
  for (final r in dayReceipts) {
    entries.add(DayEntry(
        kind: CheckKind.deliveries, title: r.materialName, workDay: d, enteredAt: r.createdAt, by: r.receivedBy));
  }
  final dayExpenses = [
    for (final e in expenses)
      if (e.projectId == project.id && !e.voided && dayOf(DateTime.tryParse(e.incurredOn) ?? e.createdAt) == d) e
  ];
  for (final e in dayExpenses) {
    entries.add(DayEntry(
        kind: CheckKind.expenses,
        title: '${tr(e.category)} ${rupees(e.amount)}',
        workDay: d,
        enteredAt: e.createdAt,
        by: e.recordedBy));
  }
  final dayReports = [for (final r in reports) if (r.projectId == project.id && dayOf(r.entryDate) == d) r];
  for (final r in dayReports) {
    entries.add(DayEntry(
        kind: CheckKind.work, title: r.workSummary, workDay: d, enteredAt: r.createdAt, by: r.createdBy));
  }
  entries.sort((a, b) => a.enteredAt.compareTo(b.enteredAt));
  return DaySnapshot(
    project: project,
    day: d,
    people: people.values.toList(),
    receipts: dayReceipts,
    expenses: dayExpenses,
    reports: dayReports,
    entries: entries,
  );
}

/// What the supervisor has said is "nothing" today, before submitting.
class NothingMarks {
  const NothingMarks({this.siteClosed = false, this.noDeliveries = false, this.noExpenses = false});
  final bool siteClosed;
  final bool noDeliveries;
  final bool noExpenses;
}

/// The Today checklist: what is recorded, what was explicitly nothing, and
/// what is still missing.
List<CheckItem> checklist(DaySnapshot s, NothingMarks n) {
  CheckState state(int count, bool none) =>
      count > 0 ? CheckState.recorded : (n.siteClosed || none ? CheckState.nothing : CheckState.missing);
  return [
    CheckItem(CheckKind.attendance, state(s.people.length, false), count: s.people.length),
    CheckItem(CheckKind.deliveries, state(s.receipts.length, n.noDeliveries), count: s.receipts.length),
    CheckItem(CheckKind.expenses, state(s.expenses.length, n.noExpenses),
        count: s.expenses.length, amount: s.expenseTotal),
    CheckItem(CheckKind.work, state(s.reports.length, false), count: s.reports.length),
  ];
}

List<CheckKind> missingItems(DaySnapshot s, NothingMarks n) =>
    [for (final c in checklist(s, n)) if (c.state == CheckState.missing) c.kind];

/// Where a site's day stands.
enum DayStatus {
  /// Today, before the cutoff, nothing sent yet.
  open,

  /// Sent (on this phone it may still be waiting to sync).
  submitted,

  /// Sent with "site closed".
  siteClosed,

  /// Past the cutoff and not on this phone. On the manager's phone this is
  /// "report not received": the supervisor may have forgotten, or saved it
  /// offline. Never "zero activity".
  notReceived,

  /// Still not received the next morning: in the exceptions list.
  missed,
}

/// One site's day, from its events and what is recorded.
class DayClose {
  DayClose({required this.snapshot, required this.setup, required this.events});

  final DaySnapshot snapshot;
  final CloseSetup setup;

  /// This day's events, oldest first.
  final List<SiteDayEvent> events;

  DateTime get day => snapshot.day;
  String get dayKey => markDay(day);

  /// The submission that stands: the latest, unless reopened since.
  SiteDayEvent? get submission {
    for (final e in events.reversed) {
      if (e.kind == 'reopened') return null;
      if (e.kind == 'submitted') return e;
    }
    return null;
  }

  bool get isSubmitted => submission != null;

  /// Sent after the day it covers (the entry date is later than the work
  /// date).
  bool get submittedLate => submission != null && dayOf(submission!.createdAt).isAfter(day);

  /// Sent after the site's cutoff, the same day or later.
  bool get submittedAfterCutoff => submission != null && submission!.createdAt.isAfter(setup.cutoffOn(day));

  /// Something recorded for the day changed after it was sent.
  bool get changedSinceSubmit =>
      submission != null && submission!.fingerprint != null && submission!.fingerprint != snapshot.fingerprint;

  NothingMarks get marks => submission == null
      ? const NothingMarks()
      : NothingMarks(
          siteClosed: submission!.siteClosed,
          noDeliveries: submission!.noDeliveries,
          noExpenses: submission!.noExpenses,
        );

  List<SiteDayEvent> get missReasons => [for (final e in events) if (e.kind == 'miss_reason') e];
  List<SiteDayEvent> get followUps => [for (final e in events) if (e.kind == 'follow_up') e];

  DayStatus status(DateTime now) {
    final s = submission;
    if (s != null) return s.siteClosed ? DayStatus.siteClosed : DayStatus.submitted;
    if (now.isBefore(setup.cutoffOn(day))) return DayStatus.open;
    if (now.isBefore(setup.exceptionAt(day))) return DayStatus.notReceived;
    return DayStatus.missed;
  }

  /// Missed: not sent before the next morning (late submissions included).
  bool wasMissed(DateTime now) {
    final s = submission;
    if (s != null) return s.createdAt.isAfter(setup.exceptionAt(day));
    return !now.isBefore(setup.exceptionAt(day));
  }
}

DayClose buildDayClose({
  required DaySnapshot snapshot,
  required SiteCloseSetting? settings,
  required List<SiteDayEvent> events,
}) =>
    DayClose(
      snapshot: snapshot,
      setup: CloseSetup.from(settings),
      events: [for (final e in events) if (e.projectId == snapshot.project.id && e.workDate == markDay(snapshot.day)) e],
    );

/// Days in the [repeatWindowDays] before [now]'s day that were missed,
/// counted from the site's first submission (days before the site used the
/// daily close are not held against anyone).
List<DateTime> missedDays({
  required List<SiteDayEvent> events,
  required CloseSetup setup,
  required DateTime now,
  DateTime? since,
}) {
  final submittedAt = <String, DateTime>{};
  final reopened = <String>{};
  DateTime? first;
  for (final e in events) {
    if (e.kind == 'submitted') {
      final d = parseDay(e.workDate);
      if (d != null && (first == null || d.isBefore(first))) first = d;
      // The first time it was sent is what counts for being on time.
      submittedAt.putIfAbsent(e.workDate, () => e.createdAt);
      reopened.remove(e.workDate);
    } else if (e.kind == 'reopened') {
      reopened.add(e.workDate);
    }
  }
  final start = since ?? first;
  if (start == null) return const [];
  final today = dayOf(now);
  final out = <DateTime>[];
  for (var i = repeatWindowDays; i >= 1; i--) {
    final d = today.subtract(Duration(days: i));
    if (d.isBefore(start)) continue;
    final at = submittedAt[markDay(d)];
    final late = at == null ? !now.isBefore(setup.exceptionAt(d)) : at.isAfter(setup.exceptionAt(d));
    if (late) out.add(d);
  }
  return out;
}

/// The WhatsApp-ready site report, written from what is recorded, in the
/// app's language. [workerCount] etc. come from the snapshot; nothing here
/// is typed twice.
String whatsAppReport(DaySnapshot s, NothingMarks n, {List<Issue> issues = const []}) {
  final b = StringBuffer('*${s.project.name}* · ${fmtDay(s.day)}, ${fmtDate(s.day, short: true)}\n');
  if (n.siteClosed && s.people.isEmpty && s.reports.isEmpty) {
    b.writeln(tr('Site closed today.'));
    return b.toString().trimRight();
  }
  if (n.siteClosed) b.writeln(tr('Site closed today.'));
  if (s.people.isEmpty) {
    b.writeln('${tr('Attendance')}: ${tr('nobody worked')}');
  } else {
    final shown = s.people.take(8).join(', ');
    final more = s.people.length > 8 ? ' ${trf('and {n} more', {'n': s.people.length - 8})}' : '';
    b.writeln('${tr('Attendance')}: ${trf('{n} people', {'n': s.people.length})} ($shown$more)');
  }
  if (s.receipts.isEmpty) {
    b.writeln('${tr('Deliveries')}: ${tr('none')}');
  } else {
    b.writeln('${tr('Deliveries')}:');
    for (final r in s.receipts) {
      b.writeln('- ${[r.materialName.trim(), fmtQty(r.quantity), (r.unit ?? '').trim()].where((x) => x.isNotEmpty).join(' ')}');
    }
  }
  if (s.expenses.isEmpty) {
    b.writeln('${tr('Expenses')}: ${tr('none')}');
  } else {
    b.writeln('${tr('Expenses')}: ${rupees(s.expenseTotal)}');
    for (final e in s.expenses) {
      final to = (e.paidTo ?? '').trim();
      b.writeln('- ${tr(e.category)} ${rupees(e.amount)}${to.isEmpty ? '' : ' ($to)'}');
    }
  }
  if (s.reports.isNotEmpty) {
    b.writeln('${tr('Work done')}:');
    for (final r in s.reports) {
      b.writeln(r.workSummary.trim());
    }
  }
  final open = [for (final i in issues) if (i.status != 'resolved' && dayOf(i.createdAt) == s.day) i];
  if (open.isNotEmpty) {
    b.writeln('${tr('Problems')}:');
    for (final i in open) {
      b.writeln('- ${i.description.trim()}');
    }
  }
  final late = s.backdated;
  if (late.isNotEmpty) {
    b.writeln(trf('{n} entries were added on a later day.', {'n': late.length}));
  }
  return b.toString().trimRight();
}

// ---------------------------------------------------------------------------
// Partial verification in the weekly close: money for days whose daily
// report was never submitted is held, the rest can go ahead, and an
// approver who pays it anyway records why.
// ---------------------------------------------------------------------------

class ItemVerification {
  const ItemVerification({required this.verified, required this.unverified, required this.unverifiedDays});
  final double verified;
  final double unverified;
  final List<DateTime> unverifiedDays;
  bool get isPartial => unverified > 0.005;
}

String itemRef(CloseItem i) => '${i.kind.key}:${i.id}';

/// Splits each weekly item's money into the days with a submitted daily
/// report (verified) and the days without. Attendance items carry no
/// money.
class WeekVerification {
  WeekVerification(this.week, this.items, this.events);
  final WeekClose week;
  final Map<String, ItemVerification> items;

  /// This week's override and partial-release events, oldest first.
  final List<SiteDayEvent> events;

  ItemVerification? of(CloseItem i) => items[itemRef(i)];

  SiteDayEvent? overrideFor(CloseItem i) {
    for (final e in events.reversed) {
      if (e.itemRef == itemRef(i) && e.kind == 'override') return e;
    }
    return null;
  }

  SiteDayEvent? releaseFor(CloseItem i) {
    for (final e in events.reversed) {
      if (e.itemRef == itemRef(i) && e.kind == 'partial') return e;
    }
    return null;
  }

  double get heldTotal => items.values.fold(0.0, (s, v) => s + v.unverified);
}

WeekVerification verifyWeek({
  required WeekClose week,
  required List<SiteDayEvent> events,
  required List<Worker> workers,
  required List<LabourAttendanceData> punches,
  required List<AttendanceMark> marks,
  required List<SiteExpense> expenses,
  DateTime? since,
}) {
  final submitted = <String>{};
  for (final e in events) {
    if (e.projectId != week.project.id) continue;
    if (e.kind == 'submitted') submitted.add(e.workDate);
    if (e.kind == 'reopened') submitted.remove(e.workDate);
  }
  // Days before the site used the daily close ([since], null if it never
  // has) have nothing to verify against, so they are not held.
  bool ok(DateTime d) => since == null || d.isBefore(since) || submitted.contains(markDay(d));

  // Each worker's pay, day by day.
  final perDay = <String, Map<DateTime, double>>{};
  for (var i = 0; i < 7; i++) {
    final d = week.from.add(Duration(days: i));
    final sheet = buildWageSheet(
      workers: workers,
      punches: punches,
      expenses: const [],
      from: d,
      to: d.add(const Duration(days: 1)),
      marks: marks,
    );
    for (final l in sheet.lines) {
      if (l.earned > 0) perDay.putIfAbsent(l.key, () => {})[d] = l.earned;
    }
  }

  final out = <String, ItemVerification>{};
  for (final i in week.items) {
    switch (i.kind) {
      case CloseKind.wages:
        var held = 0.0;
        final days = <DateTime>[];
        (perDay[i.id] ?? const {}).forEach((d, earned) {
          if (!ok(d)) {
            held += earned;
            days.add(d);
          }
        });
        days.sort();
        final total = i.amount ?? 0;
        out[itemRef(i)] = ItemVerification(verified: total - held, unverified: held, unverifiedDays: days);
      case CloseKind.expense:
      case CloseKind.receipt:
        if (i.expense?.voided ?? false) continue;
        final amount = i.amount ?? 0;
        out[itemRef(i)] = ok(i.day)
            ? ItemVerification(verified: amount, unverified: 0, unverifiedDays: const [])
            : ItemVerification(verified: 0, unverified: amount, unverifiedDays: [i.day]);
      case CloseKind.attendance:
        break;
    }
  }
  final weekEvents = [
    for (final e in events)
      if (e.projectId == week.project.id && (e.kind == 'override' || e.kind == 'partial') && e.workDate == week.weekKey) e
  ];
  return WeekVerification(week, out, weekEvents);
}
