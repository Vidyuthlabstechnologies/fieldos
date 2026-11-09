/// The owner's daily brief: one short summary per running site of what
/// happened today (people, money, material, report, tasks, issues), with
/// the sites that need the owner ranked first. Owners pay for not having
/// to phone every site in the evening; this is that phone call, and it is
/// built on the phone from what the sites already recorded, so it works
/// offline and costs nothing to run.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/project_cost_summary.dart';
import 'package:fieldos_mobile/features/project/site_day.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/reports/period_report.dart' show firstLine;

/// How much a site needs the owner today.
enum BriefLevel { needsYou, watch, onTrack }

/// Why a site needs attention.
enum FlagKind { overBudget, nearBudget, seriousIssues, noReport, lateTasks, nobodyIn, newIssues }

/// One reason a site needs attention. [weight] orders the sites; [n] is
/// the count the words carry ("3 tasks late").
class BriefFlag {
  const BriefFlag(this.kind, this.weight, {this.n = 1, this.today = true});
  final FlagKind kind;
  final int weight;
  final int n;
  final bool today;

  /// In English, for the WhatsApp message.
  String get english => switch (kind) {
        FlagKind.overBudget => 'Over budget',
        FlagKind.nearBudget => 'Close to budget',
        FlagKind.seriousIssues => n == 1 ? '1 serious issue open' : '$n serious issues open',
        FlagKind.noReport => today ? 'No report yet today' : 'No report that day',
        FlagKind.lateTasks => n == 1 ? '1 task late' : '$n tasks late',
        FlagKind.nobodyIn => today ? 'Nobody punched in today' : 'Nobody punched in',
        FlagKind.newIssues => n == 1 ? '1 new issue' : '$n new issues',
      };
}

class SiteBrief {
  SiteBrief({
    required this.project,
    required this.day,
    required this.people,
    required this.spent,
    required this.received,
    required this.materials,
    required this.reportLine,
    required this.tasksDone,
    required this.lateTasks,
    required this.dueTomorrow,
    required this.newIssues,
    required this.openIssues,
    required this.openHighIssues,
    required this.costStatus,
    required this.costAlert,
    required this.flags,
  });

  final Project project;
  final DateTime day;

  /// Distinct workers who punched in.
  final int people;
  final double spent;
  final double received;

  /// "Cement 40 bags", "Sand 2 brass".
  final List<String> materials;

  /// First line of the day's report, or null when none was sent.
  final String? reportLine;
  final List<String> tasksDone;
  final int lateTasks;
  final List<String> dueTomorrow;
  final List<String> newIssues;
  final int openIssues;
  final int openHighIssues;

  /// 'ok' | 'at_risk' | 'over' | 'no_budget'.
  final String costStatus;
  final String? costAlert;
  final List<BriefFlag> flags;

  int get score => flags.fold(0, (s, f) => s + f.weight);

  BriefLevel get level => score >= 5
      ? BriefLevel.needsYou
      : score >= 2
          ? BriefLevel.watch
          : BriefLevel.onTrack;

  bool get reported => reportLine != null;
}

bool _sameDay(DateTime a, DateTime b) {
  final l = a.toLocal();
  return l.year == b.year && l.month == b.month && l.day == b.day;
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// The flags for a site, worst first. Kept apart so the ranking rules can
/// be read (and tested) in one place.
List<BriefFlag> briefFlags({
  required bool reported,
  required int people,
  required int lateTasks,
  required int openHighIssues,
  required int newIssues,
  required String costStatus,
  required bool isToday,
}) {
  final out = <BriefFlag>[
    if (costStatus == 'over') const BriefFlag(FlagKind.overBudget, 4),
    if (costStatus == 'at_risk') const BriefFlag(FlagKind.nearBudget, 2),
    if (openHighIssues > 0) BriefFlag(FlagKind.seriousIssues, 3 * openHighIssues.clamp(1, 2), n: openHighIssues),
    if (!reported) BriefFlag(FlagKind.noReport, 3, today: isToday),
    if (lateTasks > 0) BriefFlag(FlagKind.lateTasks, lateTasks.clamp(1, 4), n: lateTasks),
    if (people == 0) BriefFlag(FlagKind.nobodyIn, 2, today: isToday),
    if (newIssues > 0 && openHighIssues == 0) BriefFlag(FlagKind.newIssues, 1, n: newIssues),
  ];
  // Heaviest first; equal weights keep the order above (List.sort is not
  // stable, so the position breaks ties).
  final order = {for (var i = 0; i < out.length; i++) out[i]: i};
  return out..sort((a, b) => b.weight != a.weight ? b.weight.compareTo(a.weight) : order[a]!.compareTo(order[b]!));
}

Future<SiteBrief> buildSiteBrief(AppDatabase db, Project project, {required DateTime day, DateTime? now}) async {
  final at = now ?? DateTime.now();
  final d = _dayOf(day);
  final isToday = _dayOf(at) == d;
  final dprs = (await db.dprDao.forProject(project.id)).where((r) => _sameDay(r.entryDate, d)).toList()
    ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
  final attendance = await db.attendanceDao.forProject(project.id);
  final tasks = await db.taskDao.forProject(project.id);
  final issues = await db.issueDao.forProject(project.id);
  final receipts = await db.materialDao.forProject(project.id);
  final expenses = (await db.expenseDao.forProject(project.id)).where((e) {
    final t = DateTime.tryParse(e.incurredOn);
    return t != null && _sameDay(t, d);
  });
  final payments = (await db.paymentDao.forProject(project.id)).where((p) => _sameDay(p.receivedOn, d));
  final cost = await ProjectCostSummary.forProject(db, project);

  // From the end of the day being briefed, so a past day reads as it stood.
  final asOf = isToday ? at : d.add(const Duration(hours: 23, minutes: 59));
  final tomorrow = d.add(const Duration(days: 1));
  final open = issues.where((i) => i.status != 'resolved' && i.resolvedAt == null).toList();
  final people = workersOnDay(attendance, d);
  final late = tasks.where((t) => isLate(t, asOf)).length;
  final highOpen = open.where((i) => i.severity == 'high').length;
  final fresh = [for (final i in issues) if (_sameDay(i.createdAt, d)) firstLine(i.description, max: 90)];
  final reportLine = dprs.isEmpty ? null : firstLine(dprs.map((r) => r.workSummary).join('\n'), max: 160);

  return SiteBrief(
    project: project,
    day: d,
    people: people,
    spent: expenses.fold(0, (s, e) => s + e.amount),
    received: payments.fold(0, (s, p) => s + p.amount),
    materials: materialsOnDay(receipts, d),
    reportLine: reportLine,
    tasksDone: [for (final t in tasks) if (t.status == 'done' && _sameDay(t.updatedAt, d)) t.title],
    lateTasks: late,
    dueTomorrow: [
      for (final t in tasks)
        if (isOpen(t) && t.dueDate != null && _dayOf(t.dueDate!.toLocal()) == tomorrow) t.title,
    ],
    newIssues: fresh,
    openIssues: open.length,
    openHighIssues: highOpen,
    costStatus: cost.status,
    costAlert: cost.alerts.isEmpty ? null : cost.alerts.first,
    flags: briefFlags(
      reported: reportLine != null,
      people: people,
      lateTasks: late,
      openHighIssues: highOpen,
      newIssues: fresh.length,
      costStatus: cost.status,
      isToday: isToday,
    ),
  );
}

/// Every running site's brief for [day], the ones needing the owner first.
Future<List<SiteBrief>> buildOwnerBrief(AppDatabase db, String companyId, {required DateTime day, DateTime? now}) async {
  final projects = (await db.projectDao.forCompany(companyId)).where((p) => p.status == 'active');
  final out = [for (final p in projects) await buildSiteBrief(db, p, day: day, now: now)];
  return rankBriefs(out);
}

List<SiteBrief> rankBriefs(List<SiteBrief> briefs) => briefs
  ..sort((a, b) {
    final s = b.score.compareTo(a.score);
    return s != 0 ? s : a.project.name.toLowerCase().compareTo(b.project.name.toLowerCase());
  });

/// Totals across sites, for the one-line summary on Home.
({int needYou, int people, double spent, int reported}) briefTotals(List<SiteBrief> briefs) => (
      needYou: briefs.where((b) => b.level == BriefLevel.needsYou).length,
      people: briefs.fold(0, (s, b) => s + b.people),
      spent: briefs.fold(0.0, (s, b) => s + b.spent),
      reported: briefs.where((b) => b.reported).length,
    );

const _levelWord = {BriefLevel.needsYou: '🔴 Needs you', BriefLevel.watch: '🟠 Watch', BriefLevel.onTrack: '🟢 On track'};

/// The WhatsApp message. English like the other shared reports: it usually
/// goes to a partner or the head office.
String ownerBriefText(List<SiteBrief> briefs, {required String companyName, required DateTime day, bool showMoney = true}) {
  final t = briefTotals(briefs);
  final b = StringBuffer()
    ..writeln('*$companyName – site brief, ${fmtDay(day)} ${fmtDate(day, short: true)}*')
    ..writeln(
        '${briefs.length} ${briefs.length == 1 ? 'site' : 'sites'} · ${t.people} people on site · ${t.reported} of ${briefs.length} reported'
        '${showMoney ? ' · ${rupees(t.spent)} spent' : ''}');
  for (final s in briefs) {
    b
      ..writeln()
      ..writeln('*${s.project.name}* – ${_levelWord[s.level]}');
    if (s.flags.isNotEmpty) b.writeln('⚠ ${s.flags.map((f) => f.english).join(', ')}');
    final facts = [
      '${s.people} ${s.people == 1 ? 'person' : 'people'}',
      if (showMoney && s.spent > 0) '${rupees(s.spent)} spent',
      if (showMoney && s.received > 0) '${rupees(s.received)} received',
    ];
    b.writeln(facts.join(' · '));
    if (s.reportLine != null) b.writeln('Work: ${s.reportLine}');
    if (s.materials.isNotEmpty) b.writeln('Material: ${s.materials.join(', ')}');
    if (s.tasksDone.isNotEmpty) b.writeln('Finished: ${s.tasksDone.join(', ')}');
    for (final i in s.newIssues.take(3)) {
      b.writeln('Issue: $i');
    }
    if (s.dueTomorrow.isNotEmpty) b.writeln('Tomorrow: ${s.dueTomorrow.take(4).join(', ')}');
    if (showMoney && s.costAlert != null) b.writeln('Budget: ${s.costAlert}');
  }
  b
    ..writeln()
    ..write('Sent from FieldOS');
  return b.toString();
}
