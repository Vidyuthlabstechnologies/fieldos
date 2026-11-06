/// Attendance by day, newest first, a week at a time. Punches left open on
/// an earlier day sit at the top until someone records when the worker
/// left, because the wage sheet counts them as half a day until then.
library;

import 'package:flutter/material.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class AttendanceList extends StatefulWidget {
  const AttendanceList({
    super.key,
    required this.rows,
    required this.onPunchOut,
    required this.onSetOutTime,
    this.now,
  });

  final List<LabourAttendanceData> rows;
  final void Function(LabourAttendanceData) onPunchOut;
  final void Function(LabourAttendanceData) onSetOutTime;

  /// For tests.
  final DateTime? now;

  /// Calendar days shown at first, and days with punches added by each
  /// "Show earlier days".
  static const pageDays = 7;

  @override
  State<AttendanceList> createState() => _AttendanceListState();
}

class _AttendanceListState extends State<AttendanceList> {
  /// Earlier days (with punches) revealed beyond the first week.
  int _earlier = 0;

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now()).toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final forgotten = <LabourAttendanceData>[];
    final byDay = <DateTime, List<LabourAttendanceData>>{};
    for (final a in widget.rows) {
      final l = a.punchIn.toLocal();
      final day = DateTime(l.year, l.month, l.day);
      if (a.punchOut == null && day.isBefore(today)) {
        forgotten.add(a);
      } else {
        byDay.putIfAbsent(day, () => []).add(a);
      }
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final weekStart = today.subtract(const Duration(days: AttendanceList.pageDays - 1));
    final thisWeek = days.where((d) => !d.isBefore(weekStart)).length;
    final shown = days.take(thisWeek + _earlier).toList();
    final hidden = days.length - shown.length;
    forgotten.sort((a, b) => b.punchIn.compareTo(a.punchIn));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (forgotten.isNotEmpty) ...[
          _DayHeader(
            title: tr('Not punched out'),
            detail: 'Set when they left. Until then each counts as half a day.',
            warn: true,
          ),
          for (final a in forgotten)
            _PunchTile(
              punch: a,
              now: now,
              showDate: true,
              action: TextButton(onPressed: () => widget.onSetOutTime(a), child: Text(tr('Set time out'))),
            ),
        ],
        if (shown.isEmpty && forgotten.isEmpty)
          EmptyState(
            icon: Icons.event_available_outlined,
            title: tr('Nobody punched in this week'),
            compact: true,
          ),
        for (final day in shown) ...[
          _DayHeader(title: fmtDay(day, now: now), detail: _people(byDay[day]!)),
          for (final a in byDay[day]!..sort((a, b) => b.punchIn.compareTo(a.punchIn)))
            _PunchTile(
              punch: a,
              now: now,
              action: a.punchOut == null
                  ? TextButton(onPressed: () => widget.onPunchOut(a), child: Text(tr('Punch out')))
                  : null,
            ),
        ],
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.history),
              label: Text('Show earlier days ($hidden more)'),
              onPressed: () => setState(() => _earlier += AttendanceList.pageDays),
            ),
          ),
      ],
    );
  }

  /// "8 people", counting each worker once however many punches they have.
  static String _people(List<LabourAttendanceData> punches) {
    final n = {for (final p in punches) p.workerId ?? 'name:${p.workerName.trim().toLowerCase()}'}.length;
    return n == 1 ? '1 person' : '$n people';
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.title, required this.detail, this.warn = false});

  final String title;
  final String detail;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
      child: Semantics(
        header: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(title,
              style: theme.textTheme.titleSmall?.copyWith(color: warn ? _warnColor(theme) : null)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ),
        ]),
      ),
    );
  }
}

Color _warnColor(ThemeData theme) =>
    theme.brightness == Brightness.dark ? const Color(0xFFFFC66D) : Brand.warn;

class _PunchTile extends StatelessWidget {
  const _PunchTile({required this.punch, required this.now, this.action, this.showDate = false});

  final LabourAttendanceData punch;
  final DateTime now;
  final Widget? action;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color, place) = switch (punch.withinGeofence) {
      true => (Icons.location_on, theme.brightness == Brightness.dark ? const Color(0xFF8FD9B0) : Brand.ok, 'On site'),
      false => (Icons.wrong_location_outlined, _warnColor(theme), 'Away from the site area'),
      null => (Icons.location_disabled_outlined, scheme.onSurfaceVariant, 'Not checked'),
    };
    final inAt = punch.punchIn.toLocal();
    final out = punch.punchOut?.toLocal();
    final times = [
      showDate ? 'In ${fmtDate(inAt, short: true, now: now)}, ${fmtTime(inAt)}' : 'In ${fmtTime(inAt)}',
      if (out != null)
        isSameDay(out, inAt) ? 'out ${fmtTime(out)}' : 'out ${fmtDateTime(out, now: now)}'
      else if (!showDate)
        'not out yet',
      if (out != null) fmtHours(out.difference(inAt)),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Tooltip(message: place, child: Icon(icon, color: color)),
        title: Text(punch.workerName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$times\n$place', maxLines: 2),
        isThreeLine: false,
        trailing: action,
      ),
    );
  }
}
