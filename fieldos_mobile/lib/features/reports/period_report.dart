/// Weekly and monthly progress reports, put together from what the site
/// already recorded: daily reports, attendance, tasks, issues, material
/// received and money. Owners send these to clients on WhatsApp every
/// Saturday; before this they had to copy each day's report by hand.
library;

import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';

enum PeriodKind { thisWeek, lastWeek, thisMonth, lastMonth }

class ReportPeriod {
  const ReportPeriod(this.kind, this.start, this.end);
  final PeriodKind kind;

  /// First day, at midnight.
  final DateTime start;

  /// The day after the last day, at midnight (exclusive).
  final DateTime end;

  bool contains(DateTime t) {
    final l = t.toLocal();
    return !l.isBefore(start) && l.isBefore(end);
  }

  DateTime get lastDay => end.subtract(const Duration(days: 1));
}

/// Weeks start on Monday, as site weeks (and wage weeks) do.
ReportPeriod periodFor(PeriodKind kind, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - DateTime.monday));
  return switch (kind) {
    PeriodKind.thisWeek => ReportPeriod(kind, monday, today.add(const Duration(days: 1))),
    PeriodKind.lastWeek => ReportPeriod(kind, monday.subtract(const Duration(days: 7)), monday),
    PeriodKind.thisMonth => ReportPeriod(kind, DateTime(now.year, now.month), today.add(const Duration(days: 1))),
    PeriodKind.lastMonth => ReportPeriod(kind, DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
  };
}

const periodLabels = {
  PeriodKind.thisWeek: 'This week',
  PeriodKind.lastWeek: 'Last week',
  PeriodKind.thisMonth: 'This month',
  PeriodKind.lastMonth: 'Last month',
};

class MaterialTotal {
  MaterialTotal(this.name, this.unit);
  final String name;
  final String? unit;
  double qty = 0;
  double amount = 0;
}

class DayNote {
  const DayNote(this.day, this.text, this.people);
  final DateTime day;
  final String text;
  final int people;
}

class PeriodReport {
  PeriodReport({
    required this.project,
    required this.period,
    required this.days,
    required this.reportsFiled,
    required this.workingDays,
    required this.labourDays,
    required this.tasksFinished,
    required this.progressNow,
    required this.lateTasks,
    required this.issuesRaised,
    required this.issuesFixed,
    required this.issuesOpen,
    required this.materials,
    required this.spent,
    required this.spentByCategory,
    required this.received,
  });

  final Project project;
  final ReportPeriod period;
  final List<DayNote> days;
  final int reportsFiled;

  /// Days in the period up to today, so "5 of 6 days reported" is honest.
  final int workingDays;

  /// Worker-days: one person on site on one day. From attendance when it
  /// was kept, else from the headcount on each daily report.
  final int labourDays;
  final List<String> tasksFinished;
  final int progressNow;
  final int lateTasks;
  final List<String> issuesRaised;
  final int issuesFixed;
  final int issuesOpen;
  final List<MaterialTotal> materials;
  final double spent;
  final Map<String, double> spentByCategory;
  final double received;

  bool get isEmpty =>
      reportsFiled == 0 && labourDays == 0 && tasksFinished.isEmpty && issuesRaised.isEmpty && materials.isEmpty && spent == 0 && received == 0;
}

DateTime _day(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// First line of a report, cut to fit a WhatsApp line.
String firstLine(String text, {int max = 140}) {
  final line = text.trim().split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
  return line.length <= max ? line : '${line.substring(0, max - 1).trimRight()}…';
}

Future<PeriodReport> buildPeriodReport(AppDatabase db, Project project, ReportPeriod period, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final dprs = (await db.dprDao.forProject(project.id)).where((d) => period.contains(d.entryDate)).toList()
    ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
  final attendance = (await db.attendanceDao.forProject(project.id)).where((a) => period.contains(a.punchIn));
  final tasks = await db.taskDao.forProject(project.id);
  final issues = await db.issueDao.forProject(project.id);
  final receipts = (await db.materialDao.forProject(project.id)).where((r) => period.contains(r.receivedOn));
  final expenses = (await db.expenseDao.forProject(project.id)).where((e) {
    final d = DateTime.tryParse(e.incurredOn);
    return d != null && period.contains(d);
  });
  final payments = (await db.paymentDao.forProject(project.id)).where((p) => period.contains(p.receivedOn));

  // One line per day; a second report on the same day adds to it.
  final byDay = <DateTime, DayNote>{};
  for (final d in dprs) {
    final day = _day(d.entryDate);
    final prev = byDay[day];
    final line = firstLine(d.workSummary);
    byDay[day] = prev == null
        ? DayNote(day, line, d.manpowerCount)
        : DayNote(day, '${prev.text} / $line', prev.people + d.manpowerCount);
  }

  final attended = {for (final a in attendance) '${a.workerId ?? a.workerName.toLowerCase()}|${_day(a.punchIn)}'};
  final fromReports = byDay.values.fold<int>(0, (s, d) => s + d.people);

  final materials = <String, MaterialTotal>{};
  for (final r in receipts) {
    final key = '${r.materialName.trim().toLowerCase()}|${r.unit ?? ''}';
    final m = materials.putIfAbsent(key, () => MaterialTotal(r.materialName.trim(), r.unit));
    m.qty += r.quantity;
    m.amount += r.amount;
  }

  final byCategory = <String, double>{};
  for (final e in expenses) {
    byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
  }

  final today = _day(at);
  final lastCounted = period.lastDay.isAfter(today) ? today : period.lastDay;
  final workingDays = lastCounted.isBefore(period.start) ? 0 : lastCounted.difference(period.start).inDays + 1;

  return PeriodReport(
    project: project,
    period: period,
    days: byDay.values.toList(),
    reportsFiled: byDay.length,
    workingDays: workingDays,
    labourDays: attended.isNotEmpty ? attended.length : fromReports,
    tasksFinished: [
      for (final t in tasks)
        if (t.status == 'done' && period.contains(t.updatedAt)) t.title,
    ],
    progressNow: projectProgress(tasks),
    lateTasks: tasks.where((t) => isLate(t, at)).length,
    issuesRaised: [for (final i in issues) if (period.contains(i.createdAt)) i.description],
    issuesFixed: issues.where((i) => i.resolvedAt != null && period.contains(i.resolvedAt!)).length,
    issuesOpen: issues.where((i) => i.status != 'resolved' && i.resolvedAt == null).length,
    materials: materials.values.toList()..sort((a, b) => b.amount.compareTo(a.amount)),
    spent: expenses.fold<double>(0, (s, e) => s + e.amount),
    spentByCategory: byCategory,
    received: payments.fold<double>(0, (s, p) => s + p.amount),
  );
}

String periodRange(ReportPeriod p) => '${fmtDate(p.start, short: true)} to ${fmtDate(p.lastDay, short: true)}';

/// [periodRange] in the app's language, for the screen (shared messages
/// stay in English).
String periodRangeLabel(ReportPeriod p) =>
    trf('{from} to {to}', {'from': fmtDate(p.start, short: true), 'to': fmtDate(p.lastDay, short: true)});

/// The WhatsApp message. Kept in English like the DPR share: it usually
/// goes to the client or the head office.
String periodReportText(PeriodReport r, {required String companyName, bool showMoney = true}) {
  final b = StringBuffer()
    ..writeln('*${r.project.name}* – ${periodLabels[r.period.kind]} (${periodRange(r.period)})')
    ..writeln(companyName)
    ..writeln()
    ..writeln('Daily reports: ${r.reportsFiled} of ${r.workingDays} days')
    ..writeln('Labour: ${r.labourDays} worker-days')
    ..writeln('Overall progress: ${r.progressNow}%${r.lateTasks > 0 ? ' (${r.lateTasks} tasks late)' : ''}');
  if (r.tasksFinished.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Finished*');
    for (final t in r.tasksFinished) {
      b.writeln('✔ $t');
    }
  }
  if (r.days.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Day by day*');
    for (final d in r.days) {
      b.writeln('${fmtDay(d.day)} ${fmtDate(d.day, short: true)}: ${d.text}${d.people > 0 ? ' (${d.people} people)' : ''}');
    }
  }
  if (r.materials.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Material received*');
    for (final m in r.materials) {
      b.writeln('• ${m.name}: ${fmtQty(m.qty)}${m.unit == null || m.unit!.isEmpty ? '' : ' ${m.unit}'}');
    }
  }
  b
    ..writeln()
    ..writeln('*Issues*: ${r.issuesRaised.length} raised, ${r.issuesFixed} fixed, ${r.issuesOpen} open');
  for (final i in r.issuesRaised.take(5)) {
    b.writeln('• ${firstLine(i, max: 100)}');
  }
  if (showMoney && (r.spent > 0 || r.received > 0)) {
    b
      ..writeln()
      ..writeln('*Money*: spent ${rupees(r.spent)}, received ${rupees(r.received)}');
  }
  b
    ..writeln()
    ..write('Sent from FieldOS');
  return b.toString();
}
