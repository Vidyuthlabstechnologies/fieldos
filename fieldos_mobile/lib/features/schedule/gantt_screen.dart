/// One site's schedule as a Gantt chart: a bar per dated task, links for
/// "earlier work", the critical path in red and today's line. Tap a task to
/// see why it moved and to link it to the work it waits for.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_data.dart';
import 'package:fieldos_mobile/features/schedule/schedule_rules.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

const _rowHeight = 48.0;
const _headerHeight = 40.0;
const _nameWidth = 136.0;

class GanttScreen extends ConsumerStatefulWidget {
  const GanttScreen({super.key, required this.project, this.now});
  final Project project;

  /// Tests pin the day.
  final DateTime? now;

  @override
  ConsumerState<GanttScreen> createState() => _GanttScreenState();
}

class _GanttScreenState extends ConsumerState<GanttScreen> {
  /// Pixels per day: days (28) or weeks (8).
  double _dayWidth = 28;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(executionDataProvider(widget.project.id));
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Schedule')),
        actions: [
          IconButton(
            key: const Key('gantt-zoom'),
            tooltip: _dayWidth > 10 ? tr('Show weeks') : tr('Show days'),
            icon: Icon(_dayWidth > 10 ? Icons.zoom_out : Icons.zoom_in),
            onPressed: () => setState(() => _dayWidth = _dayWidth > 10 ? 8 : 28),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(tr('Could not load tasks'))),
        data: (d) {
          final s = buildSchedule(d.tasks, d.constraints, now);
          if (s.rows.isEmpty) {
            return EmptyState(
              icon: Icons.view_timeline_outlined,
              title: tr('No dated tasks yet'),
              message: tr('Give tasks a start or due date and they appear here as bars.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _Summary(schedule: s),
              _Legend(),
              _Chart(
                schedule: s,
                dayWidth: _dayWidth,
                today: DateTime.utc(now.year, now.month, now.day),
                onTap: (r) => _openTask(context, s, r),
              ),
              if (s.unscheduled.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                  child: Text(
                    trf('{n} tasks have no dates and are not on the chart.', {'n': s.unscheduled.length}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openTask(BuildContext context, Schedule s, ScheduledTask r) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _TaskSheet(project: widget.project, schedule: s, row: r),
      );
}

String _d(DateTime d) => fmtDate(DateTime(d.year, d.month, d.day), short: true);

class _Summary extends StatelessWidget {
  const _Summary({required this.schedule});
  final Schedule schedule;

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    final late = s.daysLate;
    return Card(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(trf('Planned finish {day}', {'day': _d(s.plannedFinish!)}), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            late == 0
                ? tr('Heading to finish on time')
                : trf('Heading to finish {day}, {n} days late', {'day': _d(s.projectedFinish!), 'n': late}),
            style: TextStyle(color: late == 0 ? toneColor(context, PillTone.ok) : toneColor(context, PillTone.danger)),
          ),
          const SizedBox(height: 4),
          Text(
            trf('{n} tasks on the critical path: a day lost on any of them moves the finish.', {'n': s.critical.length}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: Wrap(spacing: 16, runSpacing: 4, children: [
        item(cs.primary, tr('Planned')),
        item(toneColor(context, PillTone.danger), tr('Critical path')),
        item(toneColor(context, PillTone.ok), tr('Done')),
        item(cs.outlineVariant, tr('Planned dates')),
      ]),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.schedule, required this.dayWidth, required this.today, required this.onTap});
  final Schedule schedule;
  final double dayWidth;
  final DateTime today;
  final void Function(ScheduledTask) onTap;

  @override
  Widget build(BuildContext context) {
    final s = schedule;
    // A few days either side, and always today.
    var first = s.first!;
    var last = s.last!;
    if (today.isBefore(first)) first = today;
    if (today.isAfter(last)) last = today;
    first = first.subtract(const Duration(days: 2));
    last = last.add(const Duration(days: 3));
    final days = last.difference(first).inDays + 1;
    final width = days * dayWidth;
    final height = _headerHeight + s.rows.length * _rowHeight;
    final theme = Theme.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        width: _nameWidth,
        child: Column(children: [
          const SizedBox(height: _headerHeight),
          for (final r in s.rows)
            Semantics(
              button: true,
              label: '${r.task.title}, ${_d(r.start)} – ${_d(r.finish)}${r.critical ? ', ${tr('Critical path')}' : ''}',
              excludeSemantics: true,
              child: InkWell(
                key: Key('gantt-row-${r.task.id}'),
                onTap: () => onTap(r),
                child: Container(
                  height: _rowHeight,
                  padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    r.task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: r.critical ? FontWeight.w600 : null,
                      decoration: r.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Time runs left to right in every language, as on paper charts.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              onTapUp: (e) {
                final i = ((e.localPosition.dy - _headerHeight) / _rowHeight).floor();
                if (i >= 0 && i < s.rows.length) onTap(s.rows[i]);
              },
              child: CustomPaint(
                size: Size(width, height),
                painter: _GanttPainter(
                  schedule: s,
                  first: first,
                  days: days,
                  dayWidth: dayWidth,
                  today: today,
                  textStyle: theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
                  primary: theme.colorScheme.primary,
                  critical: toneColor(context, PillTone.danger),
                  done: toneColor(context, PillTone.ok),
                  planned: theme.colorScheme.outlineVariant,
                  grid: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                  link: theme.colorScheme.onSurfaceVariant,
                  todayColor: theme.colorScheme.tertiary,
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _GanttPainter extends CustomPainter {
  _GanttPainter({
    required this.schedule,
    required this.first,
    required this.days,
    required this.dayWidth,
    required this.today,
    required this.textStyle,
    required this.primary,
    required this.critical,
    required this.done,
    required this.planned,
    required this.grid,
    required this.link,
    required this.todayColor,
  });

  final Schedule schedule;
  final DateTime first;
  final int days;
  final double dayWidth;
  final DateTime today;
  final TextStyle textStyle;
  final Color primary, critical, done, planned, grid, link, todayColor;

  double _x(DateTime d) => d.difference(first).inDays * dayWidth;

  void _text(Canvas c, String s, Offset at) {
    final tp = TextPainter(text: TextSpan(text: s, style: textStyle), textDirection: TextDirection.ltr)..layout();
    tp.paint(c, at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final weeks = dayWidth < 10;
    for (var i = 0; i < days; i++) {
      final d = first.add(Duration(days: i));
      final x = i * dayWidth;
      final weekStart = d.weekday == DateTime.monday;
      if (!weeks || weekStart) canvas.drawLine(Offset(x, _headerHeight - 6), Offset(x, size.height), gridPaint);
      if (weeks) {
        if (weekStart) _text(canvas, fmtDate(DateTime(d.year, d.month, d.day), short: true), Offset(x + 2, 4));
      } else {
        if (d.day == 1 || i == 0) _text(canvas, fmtDate(DateTime(d.year, d.month, d.day), short: true), Offset(x + 2, 2));
        _text(canvas, '${d.day}', Offset(x + 4, 20));
      }
    }

    for (var i = 0; i < schedule.rows.length; i++) {
      final r = schedule.rows[i];
      final top = _headerHeight + i * _rowHeight;
      // Planned dates as a thin outline under the bar, when it moved.
      if (r.start != r.plannedStart || r.finish != r.plannedFinish) {
        canvas.drawRRect(
          RRect.fromLTRBR(_x(r.plannedStart), top + 34, _x(r.plannedFinish) + dayWidth, top + 38, const Radius.circular(2)),
          Paint()..color = planned,
        );
      }
      final color = r.done ? done : (r.critical ? critical : primary);
      final rect = RRect.fromLTRBR(_x(r.start), top + 12, _x(r.finish) + dayWidth, top + 30, const Radius.circular(4));
      canvas.drawRRect(rect, Paint()..color = color.withValues(alpha: r.done ? 0.7 : 0.25));
      // Progress fill.
      final pct = r.done ? 1.0 : (r.task.progress.clamp(0, 100) / 100);
      if (pct > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(rect.left, rect.top, rect.left + rect.width * pct, rect.bottom));
        canvas.drawRRect(rect, Paint()..color = color);
        canvas.restore();
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Links: from the end of the earlier bar to the start of the later one.
    final linkPaint = Paint()
      ..color = link
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rowOf = {for (var i = 0; i < schedule.rows.length; i++) schedule.rows[i].task.id: i};
    for (final l in schedule.links) {
      final a = rowOf[l.from], b = rowOf[l.to];
      if (a == null || b == null) continue;
      final from = schedule.rows[a], to = schedule.rows[b];
      final y1 = _headerHeight + a * _rowHeight + 21;
      final y2 = _headerHeight + b * _rowHeight + 21;
      final x1 = _x(from.finish) + dayWidth;
      final x2 = _x(to.start);
      final mid = math.max(x1 + 4, math.min(x2 - 4, x1 + 8));
      final path = Path()
        ..moveTo(x1, y1)
        ..lineTo(mid, y1)
        ..lineTo(mid, y2)
        ..lineTo(x2, y2);
      canvas.drawPath(path, linkPaint);
      canvas.drawPath(
        Path()
          ..moveTo(x2, y2)
          ..lineTo(x2 - 5, y2 - 4)
          ..lineTo(x2 - 5, y2 + 4)
          ..close(),
        Paint()..color = link,
      );
    }

    final tx = _x(today) + dayWidth / 2;
    canvas.drawLine(
      Offset(tx, _headerHeight - 6),
      Offset(tx, size.height),
      Paint()
        ..color = todayColor
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GanttPainter old) =>
      old.schedule != schedule || old.dayWidth != dayWidth || old.today != today || old.primary != primary;
}

class _TaskSheet extends ConsumerWidget {
  const _TaskSheet({required this.project, required this.schedule, required this.row});
  final Project project;
  final Schedule schedule;
  final ScheduledTask row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final s = schedule;
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final canWrite = session.role != null && Roles.canWrite(session.role!);
    String title(String id) => s.byId[id]?.task.title ?? tr('Another task');
    final into = s.linksInto(r.task.id);
    final outOf = s.linksOutOf(r.task.id);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.task.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(trf('Planned {from} – {to}', {'from': _d(r.plannedStart), 'to': _d(r.plannedFinish)})),
          if (!r.done && (r.startSlip > 0 || r.finishSlip > 0))
            Text(
              trf('Heading {from} – {to}', {'from': _d(r.start), 'to': _d(r.finish)}),
              style: TextStyle(color: toneColor(context, PillTone.danger)),
            ),
          if (r.pushedBy != null)
            Text(trf('Waiting for "{task}" to finish.', {'task': title(r.pushedBy!)}), style: theme.textTheme.bodySmall),
          if (!r.done)
            Text(
              r.critical
                  ? tr('On the critical path: no spare days.')
                  : trf('{n} spare days before it moves the finish.', {'n': r.spareDays}),
              style: theme.textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          SectionHeader('Waits for'),
          if (into.isEmpty) Text(tr('Nothing linked.'), style: theme.textTheme.bodySmall),
          for (final l in into)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.subdirectory_arrow_right),
              title: Text(title(l.from)),
              trailing: canWrite
                  ? IconButton(
                      key: Key('gantt-unlink-${l.from}'),
                      tooltip: tr('Remove link'),
                      icon: const Icon(Icons.link_off),
                      onPressed: () => _write(context, ref, () async {
                        // Every copy of the link (two phones can add it offline).
                        for (final id in l.ids) {
                          await ref
                              .read(appDatabaseProvider)
                              .siteExecutionDao
                              .clearConstraint(id, by: session.user!.id, note: tr('Link removed in the schedule'));
                        }
                      }),
                    )
                  : null,
            ),
          if (outOf.isNotEmpty) ...[
            const SizedBox(height: 8),
            SectionHeader('Holds up'),
            for (final l in outOf)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.arrow_forward),
                title: Text(title(l.to)),
              ),
          ],
          if (canWrite) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('gantt-link'),
              icon: const Icon(Icons.add_link),
              label: Text(tr('Add earlier work it waits for')),
              onPressed: () => _pickEarlier(context, ref, session.user!.id),
            ),
          ],
        ]),
      ),
    );
  }

  Future<void> _pickEarlier(BuildContext context, WidgetRef ref, String me) async {
    final already = {for (final l in schedule.linksInto(row.task.id)) l.from};
    final options = [
      for (final o in schedule.rows)
        if (o.task.id != row.task.id && !already.contains(o.task.id)) o,
    ];
    final pick = await showModalBottomSheet<ScheduledTask>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
            child: Text(tr('Which task must finish first?'), style: Theme.of(ctx).textTheme.titleMedium),
          ),
          if (options.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(tr('No other dated tasks.'))),
          for (final o in options)
            ListTile(
              key: Key('gantt-pick-${o.task.id}'),
              title: Text(o.task.title),
              subtitle: Text('${_d(o.start)} – ${_d(o.finish)}'),
              onTap: () => Navigator.pop(ctx, o),
            ),
        ]),
      ),
    );
    if (pick == null || !context.mounted) return;
    if (wouldLoop(schedule.links, from: pick.task.id, to: row.task.id)) {
      showSnack(context, tr('That would make a loop: the other task already waits for this one.'), error: true);
      return;
    }
    await _write(context, ref, () async {
      await ref.read(appDatabaseProvider).siteExecutionDao.addConstraint(
            projectId: project.id,
            taskId: row.task.id,
            kind: 'predecessor',
            description: pick.task.title.length > 280 ? pick.task.title.substring(0, 280) : pick.task.title,
            by: me,
            linkId: pick.task.id,
          );
    });
  }

  Future<void> _write(BuildContext context, WidgetRef ref, Future<void> Function() run) async {
    try {
      await run();
      ref.invalidate(executionDataProvider(project.id));
      if (context.mounted) Navigator.pop(context);
    } on ExecutionRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }
}
