/// CRM rules: the stages a lead moves through, what a quote adds up to,
/// quote numbers, and the pipeline an owner looks at on Monday morning.
///
/// Pure code on plain values so every figure is unit-tested. Lines reuse
/// [BillLine] so a quote's items read exactly like the bill that follows.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';

/// Open stages in the order a lead moves, then the two ends.
const leadStages = ['new', 'contacted', 'site_visit', 'quoted', 'negotiation', 'won', 'lost'];
const openLeadStages = ['new', 'contacted', 'site_visit', 'quoted', 'negotiation'];

/// English labels (looked up with tr() on screen).
const leadStageLabels = {
  'new': 'New',
  'contacted': 'Contacted',
  'site_visit': 'Site visit',
  'quoted': 'Quoted',
  'negotiation': 'Negotiation',
  'won': 'Won',
  'lost': 'Lost',
};

const leadSources = ['referral', 'walk_in', 'website', 'social', 'builder', 'repeat', 'other'];
const leadSourceLabels = {
  'referral': 'Referral',
  'walk_in': 'Walk-in',
  'website': 'Website',
  'social': 'Social media',
  'builder': 'Builder or architect',
  'repeat': 'Past client',
  'other': 'Other',
};

const activityKinds = ['call', 'visit', 'meeting', 'whatsapp', 'note'];
const activityKindLabels = {
  'call': 'Call',
  'visit': 'Site visit',
  'meeting': 'Meeting',
  'whatsapp': 'WhatsApp',
  'note': 'Note',
  'stage': 'Stage changed',
};

/// Quick answers on the "lost" sheet; any other reason can be typed.
const lostReasonChoices = ['Price too high', 'Went with another contractor', 'Project on hold', 'No response'];

/// When to follow up after a call, as days from today.
const followUpChoices = [(1, 'Tomorrow'), (3, 'In 3 days'), (7, 'In a week'), (30, 'In a month')];

const quoteStatuses = ['draft', 'sent', 'accepted', 'rejected'];
const quoteStatusLabels = {'draft': 'Draft', 'sent': 'Sent', 'accepted': 'Accepted', 'rejected': 'Rejected'};

bool isOpenStage(String stage) => openLeadStages.contains(stage);

double _round2(double v) => (v * 100).roundToDouble() / 100;

class QuoteTotals {
  const QuoteTotals({
    required this.subtotal,
    required this.discount,
    required this.cgst,
    required this.sgst,
    required this.igst,
  });

  /// The lines added up.
  final double subtotal;

  /// What was taken off, never more than [subtotal].
  final double discount;
  final double cgst;
  final double sgst;
  final double igst;

  double get taxable => _round2(subtotal - discount);
  double get gst => _round2(cgst + sgst + igst);
  double get total => _round2(taxable + gst);
}

/// [discount] is a flat amount off before GST, as quotes in the trade are
/// written ("less special discount"). GST then works as on a bill: half
/// CGST and half SGST inside the state, IGST across states.
QuoteTotals quoteTotals(List<BillLine> lines, {double discount = 0, double gstRate = 18, bool interState = false}) {
  final subtotal = _round2(lines.fold<double>(0, (s, l) => s + l.amount));
  final off = _round2(discount.clamp(0, subtotal).toDouble());
  final t = billTotals([BillLine(description: '', unit: '', rate: subtotal - off, qty: 1)],
      gstRate: gstRate, interState: interState);
  return QuoteTotals(subtotal: subtotal, discount: off, cgst: t.cgst, sgst: t.sgst, igst: t.igst);
}

/// "Q-2611-007": the year and month, then a running number across the
/// company's quotes. Each phone adds one to the highest it holds; the
/// server adds a suffix if two phones picked the same one while offline.
String nextQuoteNumber(Iterable<String> existing, DateTime date) {
  var max = 0;
  for (final n in existing) {
    final parts = n.split('-');
    if (parts.length < 3 || parts.first.toUpperCase() != 'Q') continue;
    final v = int.tryParse(parts[2]);
    if (v != null && v > max) max = v;
  }
  final ym = '${(date.year % 100).toString().padLeft(2, '0')}${date.month.toString().padLeft(2, '0')}';
  return 'Q-$ym-${(max + 1).toString().padLeft(3, '0')}';
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A follow-up is due on its day and overdue the day after.
bool isFollowUpDue(CrmLead l, DateTime now) =>
    isOpenStage(l.stage) && l.nextFollowUp != null && !_day(l.nextFollowUp!).isAfter(_day(now));

bool isFollowUpOverdue(CrmLead l, DateTime now) =>
    isOpenStage(l.stage) && l.nextFollowUp != null && _day(l.nextFollowUp!).isBefore(_day(now));

/// An open lead nobody has set a next step for.
bool hasNoNextStep(CrmLead l) => isOpenStage(l.stage) && l.nextFollowUp == null;

/// What a lead is worth: its latest quote that isn't rejected, else the
/// estimate typed in.
double leadValue(CrmLead l, List<CrmQuote> quotesOfLead) {
  final live = quotesOfLead.where((q) => q.status != 'rejected').toList()
    ..sort((a, b) => b.quoteDate.compareTo(a.quoteDate));
  if (live.isNotEmpty) return live.first.total;
  return l.estimatedValue ?? 0;
}

class StageSummary {
  const StageSummary(this.stage, this.count, this.value);
  final String stage;
  final int count;
  final double value;
}

class Pipeline {
  const Pipeline({
    required this.stages,
    required this.openValue,
    required this.wonValue,
    required this.wonCount,
    required this.lostCount,
    required this.dueToday,
    required this.overdue,
    required this.noNextStep,
    required this.lostReasons,
  });

  final List<StageSummary> stages;
  final double openValue;
  final double wonValue;
  final int wonCount;
  final int lostCount;

  /// Open leads whose follow-up is today or earlier.
  final int dueToday;
  final int overdue;
  final int noNextStep;

  /// Why leads were lost, most common first.
  final List<(String, int)> lostReasons;

  /// Won out of everything decided, 0..1; null before anything is decided.
  double? get winRate => wonCount + lostCount == 0 ? null : wonCount / (wonCount + lostCount);
}

/// The pipeline over [leads], valuing each by [leadValue]. [since] limits
/// won and lost to those decided from that day (this month, this year).
Pipeline pipeline(List<CrmLead> leads, List<CrmQuote> quotes, {required DateTime now, DateTime? since}) {
  final byLead = <String, List<CrmQuote>>{};
  for (final q in quotes) {
    (byLead[q.leadId] ??= []).add(q);
  }
  final count = {for (final s in leadStages) s: 0};
  final value = {for (final s in leadStages) s: 0.0};
  final reasons = <String, int>{};
  var won = 0, lost = 0, due = 0, late = 0, none = 0;
  var wonValue = 0.0;
  for (final l in leads) {
    final v = leadValue(l, byLead[l.id] ?? const []);
    final decidedInRange = since == null || !l.updatedAt.isBefore(since);
    if (!isOpenStage(l.stage) && !decidedInRange) continue;
    count[l.stage] = (count[l.stage] ?? 0) + 1;
    value[l.stage] = (value[l.stage] ?? 0) + v;
    if (l.stage == 'won') {
      won++;
      wonValue += v;
    } else if (l.stage == 'lost') {
      lost++;
      final r = (l.lostReason ?? '').trim();
      final key = r.isEmpty ? 'No reason given' : r;
      reasons[key] = (reasons[key] ?? 0) + 1;
    }
    if (isFollowUpDue(l, now)) due++;
    if (isFollowUpOverdue(l, now)) late++;
    if (hasNoNextStep(l)) none++;
  }
  final reasonList = reasons.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  return Pipeline(
    stages: [for (final s in leadStages) StageSummary(s, count[s]!, _round2(value[s]!))],
    openValue: _round2(openLeadStages.fold<double>(0, (s, st) => s + value[st]!)),
    wonValue: _round2(wonValue),
    wonCount: won,
    lostCount: lost,
    dueToday: due,
    overdue: late,
    noNextStep: none,
    lostReasons: reasonList,
  );
}

/// Open leads in the order to work them: overdue first, then due today,
/// then by next follow-up, then those with no next step, newest first.
List<CrmLead> workingOrder(List<CrmLead> leads, DateTime now) {
  int rank(CrmLead l) {
    if (!isOpenStage(l.stage)) return 4;
    if (isFollowUpOverdue(l, now)) return 0;
    if (isFollowUpDue(l, now)) return 1;
    if (l.nextFollowUp != null) return 2;
    return 3;
  }

  return [...leads]..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      if (a.nextFollowUp != null && b.nextFollowUp != null) {
        final c = a.nextFollowUp!.compareTo(b.nextFollowUp!);
        if (c != 0) return c;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
}

/// Budget lines for the site made from a won quote: one per quote line,
/// code "Q-01", "Q-02"..., budget = the line's amount (before GST, which
/// is the client's money, not the site's cost).
List<({String code, String name, double budget})> budgetLinesFromQuote(List<BillLine> lines) => [
      for (final (i, l) in lines.where((l) => l.description.trim().isNotEmpty && l.amount > 0).indexed)
        (
          code: 'Q-${(i + 1).toString().padLeft(2, '0')}',
          name: l.unit.isEmpty ? l.description : '${l.description} (${l.unit})',
          budget: l.amount,
        ),
    ];

List<BillLine> decodeQuoteLines(String json) => decodeLines(json);
