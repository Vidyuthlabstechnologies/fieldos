/// One worker's month at a glance: which days they came, full or half day,
/// hours, overtime and punch-outs that were missed. Contractors are asked
/// this at every wage dispute ("I came on the 14th!"), and the punches were
/// there but only as a long list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class DayMark {
  DayMark(this.day);
  final DateTime day;
  double hours = 0;
  bool openPunch = false;

  /// Days of pay marked by hand, which replace what the punches count.
  double? marked;
  double get credit => marked ?? dayCredit(hours, hasOpenPunch: openPunch);
  double get overtime => hours > overtimeAfterHours ? hours - overtimeAfterHours : 0;
}

class WorkerMonth {
  WorkerMonth(this.month, this.days);

  /// The 1st of the month.
  final DateTime month;
  final Map<int, DayMark> days;

  double get daysWorked => days.values.fold(0, (s, d) => s + d.credit);
  double get hours => days.values.fold(0, (s, d) => s + d.hours);
  double get overtime => days.values.fold(0, (s, d) => s + d.overtime);
  int get missedPunchOuts => days.values.where((d) => d.openPunch && d.marked == null).length;
}

bool punchIsFor(LabourAttendanceData p, Worker w) =>
    p.workerId != null ? p.workerId == w.id : p.workerName.trim().toLowerCase() == w.name.trim().toLowerCase();

/// The same counting as the wage sheet, so the calendar and the pay agree.
WorkerMonth buildWorkerMonth(Iterable<LabourAttendanceData> punches, Worker worker, DateTime anyDayInMonth,
    {Iterable<AttendanceMark> marks = const []}) {
  final month = DateTime(anyDayInMonth.year, anyDayInMonth.month);
  final next = DateTime(month.year, month.month + 1);
  final days = <int, DayMark>{};
  for (final p in punches) {
    if (!punchIsFor(p, worker)) continue;
    final at = p.punchIn.toLocal();
    if (at.isBefore(month) || !at.isBefore(next)) continue;
    final mark = days.putIfAbsent(at.day, () => DayMark(DateTime(at.year, at.month, at.day)));
    final out = p.punchOut;
    final h = out == null ? null : out.difference(p.punchIn).inMinutes / 60.0;
    if (h == null || h < 0 || h > longestShiftHours) {
      mark.openPunch = true;
    } else {
      mark.hours += h;
    }
  }
  for (final MapEntry(key: day, value: units) in (marksByWorker(marks)[worker.id] ?? const {}).entries) {
    if (day.isBefore(month) || !day.isBefore(next)) continue;
    days.putIfAbsent(day.day, () => DayMark(day)).marked = units;
  }
  return WorkerMonth(month, days);
}

String fmtDays(double d) => d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(1);

Future<void> openWorkerCalendar(BuildContext context, Worker worker) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => WorkerCalendarScreen(worker: worker)));

class WorkerCalendarScreen extends ConsumerStatefulWidget {
  const WorkerCalendarScreen({super.key, required this.worker, this.now});
  final Worker worker;

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends ConsumerState<WorkerCalendarScreen> {
  late DateTime _month = DateTime((widget.now ?? DateTime.now()).year, (widget.now ?? DateTime.now()).month);
  late final Future<List<LabourAttendanceData>> _punches =
      ref.read(appDatabaseProvider).attendanceDao.forProject(widget.worker.projectId);
  late final Future<List<AttendanceMark>> _marks =
      ref.read(appDatabaseProvider).attendanceDao.marksForProject(widget.worker.projectId);
  late final Future<(List<LabourAttendanceData>, List<AttendanceMark>)> _data =
      Future.wait([_punches, _marks]).then((r) => (r[0] as List<LabourAttendanceData>, r[1] as List<AttendanceMark>));

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = widget.now ?? DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Scaffold(
      appBar: AppBar(title: Text(widget.worker.name)),
      body: FutureBuilder<(List<LabourAttendanceData>, List<AttendanceMark>)>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final m = buildWorkerMonth(snap.data!.$1, widget.worker, _month, marks: snap.data!.$2);
          final wage = widget.worker.dailyWage;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: tr('Previous month'),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: Text(MaterialLocalizations.of(context).formatMonthYear(_month), textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: tr('Next month'),
                  onPressed: isCurrent ? null : () => _shift(1),
                ),
              ]),
              const SizedBox(height: 8),
              _MonthGrid(month: m, today: DateTime(now.year, now.month, now.day)),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 6, children: [
                _Legend(color: toneColor(context, PillTone.ok), label: tr('Full day')),
                _Legend(color: toneColor(context, PillTone.warn), label: tr('Half day')),
                _Legend(color: toneColor(context, PillTone.danger), label: tr('No punch-out')),
              ]),
              const SectionHeader('This month'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                StatusPill(trf('{n} days worked', {'n': fmtDays(m.daysWorked)}), tone: PillTone.ok),
                StatusPill(trf('{n} hours on site', {'n': m.hours.toStringAsFixed(1)})),
                if (m.overtime > 0) StatusPill(trf('{n} hours overtime', {'n': m.overtime.toStringAsFixed(1)}), tone: PillTone.warn),
                if (m.missedPunchOuts > 0)
                  StatusPill(trf('{n} punch-outs missed', {'n': m.missedPunchOuts}), tone: PillTone.danger),
                if (wage != null && wage > 0)
                  StatusPill(trf('Earned {amount}', {'amount': rupees(m.daysWorked * wage, paise: true)})),
              ]),
              if (m.days.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(tr('No punches this month.'), style: theme.textTheme.bodyMedium),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.today});
  final WorkerMonth month;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = month.month;
    final lead = first.weekday - DateTime.monday;
    final count = DateTime(first.year, first.month + 1, 0).day;
    // Weeks start on Monday, like the wage week. narrowWeekdays starts on Sunday.
    final narrow = MaterialLocalizations.of(context).narrowWeekdays;
    final heads = [for (var i = 1; i <= 7; i++) narrow[i % 7]];
    return Column(children: [
      Row(children: [
        for (final h in heads)
          Expanded(child: Center(child: Text(h, style: theme.textTheme.labelSmall))),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        children: [
          for (var i = 0; i < lead; i++) const SizedBox.shrink(),
          for (var d = 1; d <= count; d++) _DayCell(day: d, mark: month.days[d], isToday: DateTime(first.year, first.month, d) == today),
        ],
      ),
    ]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.mark, required this.isToday});
  final int day;
  final DayMark? mark;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = mark;
    final Color? fill = m == null
        ? null
        : m.marked != null
            ? (m.marked! >= 1
                ? toneColor(context, PillTone.ok)
                : m.marked! > 0
                    ? toneColor(context, PillTone.warn)
                    : toneColor(context, PillTone.danger))
        : m.openPunch && m.hours == 0
            ? toneColor(context, PillTone.danger)
            : m.credit >= 1
                ? toneColor(context, PillTone.ok)
                : m.credit > 0
                    ? toneColor(context, PillTone.warn)
                    : toneColor(context, PillTone.danger);
    final label = m == null
        ? '$day'
        : m.marked != null
            ? '$day, marked ${markLabel(m.marked!)}'
            : '$day, ${m.hours.toStringAsFixed(1)} h${m.openPunch ? ', no punch-out' : ''}';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: fill?.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: theme.colorScheme.primary, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$day', style: TextStyle(color: fill == null ? null : Colors.white, fontWeight: FontWeight.w600)),
          if (m?.marked != null)
            Text(markLabel(m!.marked!), style: const TextStyle(color: Colors.white, fontSize: 10, height: 1)),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
