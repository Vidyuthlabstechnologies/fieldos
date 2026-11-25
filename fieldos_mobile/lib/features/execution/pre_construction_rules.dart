/// The rules behind the pre-construction tracker, kept free of Flutter so
/// they can be tested on their own:
///
/// - an approval is open until it is approved or rejected, and it is
///   stuck when nothing has moved on it for a week;
/// - the bottleneck is the open approval that has waited longest, with
///   whose court the ball is in;
/// - a project's phase (pre-project, execution, post-project) follows its
///   stage;
/// - liaison time and cost add up per approval and per person.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart' show parseDay, ymd;
import 'package:fieldos_mobile/l10n/language.dart';

const approvalAuthorities = [
  'ghmc', 'hmda', 'municipality', 'fire', 'pollution', 'electricity', 'water', 'rera', 'airport', 'other',
];
const approvalStatuses = ['not_started', 'drafting', 'applied', 'query_raised', 'resubmitted', 'approved', 'rejected'];
const approvalWaitingOn = ['us', 'consultant', 'authority', 'client'];

/// Days with no movement before an open approval counts as stuck.
const approvalStuckDays = 7;

/// Days before a clearance lapses that it starts to show as expiring.
const approvalExpiryWarnDays = 30;

String authorityLabel(String a) => switch (a) {
      'ghmc' => tr('GHMC'),
      'hmda' => tr('HMDA'),
      'municipality' => tr('Municipality'),
      'fire' => tr('Fire NOC'),
      'pollution' => tr('Pollution board'),
      'electricity' => tr('Electricity board'),
      'water' => tr('Water board'),
      'rera' => tr('RERA'),
      'airport' => tr('Airport authority'),
      _ => tr('Other authority'),
    };

String approvalStatusLabel(String s) => switch (s) {
      'not_started' => tr('Not started'),
      'drafting' => tr('Preparing the file'),
      'applied' => tr('Applied'),
      'query_raised' => tr('Query raised'),
      'resubmitted' => tr('Resubmitted'),
      'approved' => tr('Approved'),
      'rejected' => tr('Rejected'),
      _ => s,
    };

String waitingOnLabel(String w) => switch (w) {
      'us' => tr('Us'),
      'consultant' => tr('Consultant'),
      'authority' => tr('The authority'),
      'client' => tr('Client'),
      _ => w,
    };

bool approvalIsOpen(SiteApproval a) => a.status != 'approved' && a.status != 'rejected';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar days between two days (not 24-hour blocks, which are an hour
/// out across a clock change).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Days since anything last moved on an open approval.
int approvalIdleDays(SiteApproval a, DateTime now) => daysBetween(a.updatedAt, now).clamp(0, 100000);

bool approvalStuck(SiteApproval a, DateTime now) => approvalIsOpen(a) && approvalIdleDays(a, now) >= approvalStuckDays;

/// Past the date it was expected by, while still open.
bool approvalLate(SiteApproval a, DateTime now) {
  final by = parseDay(a.expectedBy);
  return approvalIsOpen(a) && by != null && by.isBefore(_day(now));
}

/// Days a clearance has left, or null when it has no end date. Negative
/// once it has lapsed.
int? approvalDaysToExpiry(SiteApproval a, DateTime now) {
  final end = parseDay(a.validUntil);
  if (a.status != 'approved' || end == null) return null;
  return daysBetween(now, end);
}

bool approvalExpiring(SiteApproval a, DateTime now) {
  final left = approvalDaysToExpiry(a, now);
  return left != null && left <= approvalExpiryWarnDays;
}

/// Days from applying to now (or to the approval).
int? approvalDaysInProcess(SiteApproval a, DateTime now) {
  final from = parseDay(a.appliedOn);
  if (from == null) return null;
  final to = parseDay(a.approvedOn) ?? _day(now);
  return daysBetween(from, to);
}

class ApprovalSummary {
  ApprovalSummary({required this.total, required this.approved, required this.open, required this.stuck, required this.late, required this.expiring, required this.bottleneck, required this.byWaitingOn});
  final int total;
  final int approved;
  final int open;
  final int stuck;
  final int late;
  final int expiring;

  /// The open approval that has waited longest.
  final SiteApproval? bottleneck;

  /// Open approvals by whose court the ball is in.
  final Map<String, int> byWaitingOn;
}

ApprovalSummary summariseApprovals(List<SiteApproval> all, DateTime now) {
  final open = [for (final a in all) if (approvalIsOpen(a)) a];
  SiteApproval? worst;
  var worstIdle = -1;
  for (final a in open) {
    final idle = approvalIdleDays(a, now);
    if (idle > worstIdle) {
      worst = a;
      worstIdle = idle;
    }
  }
  return ApprovalSummary(
    total: all.length,
    approved: all.where((a) => a.status == 'approved').length,
    open: open.length,
    stuck: open.where((a) => approvalStuck(a, now)).length,
    late: open.where((a) => approvalLate(a, now)).length,
    expiring: all.where((a) => approvalExpiring(a, now)).length,
    bottleneck: worst,
    byWaitingOn: {
      for (final w in approvalWaitingOn)
        if (open.any((a) => a.waitingOn == w)) w: open.where((a) => a.waitingOn == w).length,
    },
  );
}

/// One line added to an approval's history when its status changes.
String approvalHistoryLine(DateTime day, String status, String waitingOn, String note) =>
    '${ymd(day)}|$status|$waitingOn|${note.replaceAll('\n', ' ')}';

({String day, String status, String waitingOn, String note})? parseApprovalHistory(String line) {
  final p = line.split('|');
  if (p.length < 4 || p[0].isEmpty) return null;
  return (day: p[0], status: p[1], waitingOn: p[2], note: p.sublist(3).join('|'));
}

// --- Lifecycle ---------------------------------------------------------------

const lifecyclePhases = ['pre_project', 'execution', 'post_project'];

/// The phase a project is in, from its stage: planning is pre-project,
/// running or on hold is execution, handed over is post-project.
String lifecyclePhaseOf(String projectStatus) => switch (projectStatus) {
      'planning' => 'pre_project',
      'completed' => 'post_project',
      _ => 'execution',
    };

String lifecyclePhaseLabel(String phase) => switch (phase) {
      'pre_project' => tr('Pre-project: planning and approvals'),
      'execution' => tr('During execution'),
      'post_project' => tr('Post-project'),
      _ => phase,
    };

// --- Liaison time and cost ----------------------------------------------------

class LiaisonTotals {
  const LiaisonTotals({this.minutes = 0, this.cost = 0, this.entries = 0});
  final int minutes;
  final double cost;
  final int entries;
  double get hours => minutes / 60;
}

LiaisonTotals liaisonTotal(Iterable<LiaisonLog> logs) {
  var m = 0;
  var c = 0.0;
  var n = 0;
  for (final l in logs) {
    m += l.minutes;
    c += l.cost;
    n++;
  }
  return LiaisonTotals(minutes: m, cost: c, entries: n);
}

/// Totals per approval id (entries with no approval under the empty key).
Map<String, LiaisonTotals> liaisonByApproval(List<LiaisonLog> logs) {
  final by = <String, List<LiaisonLog>>{};
  for (final l in logs) {
    (by[l.approvalId ?? ''] ??= []).add(l);
  }
  return {for (final e in by.entries) e.key: liaisonTotal(e.value)};
}

/// Totals per person, biggest cost first.
List<MapEntry<String, LiaisonTotals>> liaisonByPerson(List<LiaisonLog> logs) {
  final by = <String, List<LiaisonLog>>{};
  for (final l in logs) {
    (by[(l.person ?? '').trim().isEmpty ? '' : l.person!.trim()] ??= []).add(l);
  }
  return [for (final e in by.entries) MapEntry(e.key, liaisonTotal(e.value))]..sort((a, b) => b.value.cost.compareTo(a.value.cost));
}

/// "3 h 20 min" from minutes.
String durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return trf('{n} min', {'n': m});
  if (m == 0) return trf('{n} h', {'n': h});
  return trf('{h} h {m} min', {'h': h, 'm': m});
}

// --- Drawing revisions --------------------------------------------------------

/// The labels offered when uploading a revision: the consultant's next
/// round, then Good for Construction.
List<String> revisionPresets(int existing) => ['Rev ${existing + 1}', 'GFC'];
