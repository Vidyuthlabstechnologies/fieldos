/// The day register on screen: one tap per worker to mark the day, with
/// who came by trade and the day's wage bill on top.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/day_register.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/workers/worker_calendar.dart' show fmtDays;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class DayRegisterScreen extends ConsumerStatefulWidget {
  const DayRegisterScreen({super.key, required this.projectId, required this.userId, this.now});
  final String projectId;
  final String userId;

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<DayRegisterScreen> createState() => _DayRegisterScreenState();
}

class _DayRegisterScreenState extends ConsumerState<DayRegisterScreen> {
  DateTime get _today {
    final n = widget.now ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  late DateTime _day = _today;

  void _refresh() {
    ref.invalidate(attendanceMarksProvider(widget.projectId));
    ref.invalidate(attendanceProvider(widget.projectId));
  }

  Future<void> _mark(Worker w, double? units) async {
    await ref.read(appDatabaseProvider).attendanceDao.setMark(
        projectId: widget.projectId, workerId: w.id, day: markDay(_day), units: units, by: widget.userId);
    _refresh();
  }

  Future<void> _markRestPresent(List<RegisterRow> rows) async {
    final dao = ref.read(appDatabaseProvider).attendanceDao;
    final rest = rows.where((r) => r.marked == null && !r.punched).toList();
    for (final r in rest) {
      await dao.setMark(
          projectId: widget.projectId, workerId: r.worker.id, day: markDay(_day), units: 1, by: widget.userId);
    }
    _refresh();
    if (mounted) showSnack(context, trf('{n} marked present.', {'n': rest.length}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workers = ref.watch(workersProvider(widget.projectId));
    final punches = ref.watch(attendanceProvider(widget.projectId));
    final marks = ref.watch(attendanceMarksProvider(widget.projectId));
    final ready = workers.hasValue && punches.hasValue && marks.hasValue;
    final rows = ready
        ? buildRegister(workers: workers.value!, punches: punches.value!, marks: marks.value!, day: _day)
        : const <RegisterRow>[];
    final extra = ready ? unlistedPunched(workers.value!, punches.value!, _day) : 0;
    final trades = headcountByTrade(rows);
    final present = rows.where((r) => r.present).length + extra;
    final paidDays = rows.fold<double>(0, (s, r) => s + r.units);
    final cost = rows.fold<double>(0, (s, r) => s + r.cost);
    final unmarked = rows.where((r) => r.marked == null && !r.punched).length;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Day register'))),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                Row(children: [
                  IconButton(
                    tooltip: tr('Previous day'),
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _day = _day.subtract(const Duration(days: 1))),
                  ),
                  Expanded(
                    child: TextButton(
                      key: const Key('register-day'),
                      onPressed: () async {
                        final d = await showDatePicker(
                            context: context, initialDate: _day, firstDate: DateTime(2020), lastDate: _today);
                        if (d != null) setState(() => _day = d);
                      },
                      child: Text(_day == _today ? tr('Today') : fmtDate(_day), style: theme.textTheme.titleMedium),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('Next day'),
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _day == _today ? null : () => setState(() => _day = _day.add(const Duration(days: 1))),
                  ),
                ]),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        key: const Key('register-headcount'),
                        trf('{n} on site', {'n': present}),
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        cost > 0
                            ? trf('{days} days of pay · {amount}', {'days': fmtDays(paidDays), 'amount': rupees(cost, paise: true)})
                            : trf('{days} days of pay', {'days': fmtDays(paidDays)}),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (trades.isNotEmpty || extra > 0) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final t in trades) StatusPill('${tr(t.trade)} ${t.people}', tone: PillTone.ok),
                          if (extra > 0) StatusPill(trf('{n} not in the worker list', {'n': extra})),
                        ]),
                      ],
                    ]),
                  ),
                ),
                if (rows.isEmpty)
                  EmptyState(
                    icon: Icons.groups_outlined,
                    title: tr('No workers yet'),
                    message: tr('Add workers with their trade and daily wage, then mark their days here.'),
                    compact: true,
                  )
                else ...[
                  if (unmarked > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        key: const Key('register-rest-present'),
                        icon: const Icon(Icons.done_all),
                        label: Text(trf('Mark the other {n} present', {'n': unmarked})),
                        onPressed: () => _markRestPresent(rows),
                      ),
                    ),
                  for (final (i, r) in rows.indexed) ...[
                    if (i == 0 || tradeOf(rows[i - 1].worker) != tradeOf(r.worker))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 18, 4, 4),
                        child: Text(tr(tradeOf(r.worker)).toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                      ),
                    _WorkerRow(row: r, onMark: (u) => _mark(r.worker, u)),
                  ],
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      tr('A mark replaces what the punches count for that day. Tap a chosen mark again to go back to the punches.'),
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({required this.row, required this.onMark});
  final RegisterRow row;
  final ValueChanged<double?> onMark;

  String _units(double u) => switch (u) {
        0 => tr('Absent'),
        0.25 => tr('¼ day'),
        0.5 => tr('½ day'),
        1 => tr('Full day'),
        1.5 => '1½',
        2 => tr('Double'),
        3 => tr('Triple'),
        _ => u.toString(),
      };

  @override
  Widget build(BuildContext context) {
    final r = row;
    final theme = Theme.of(context);
    final status = r.marked != null
        ? trf('Marked: {mark}', {'mark': _units(r.marked!)})
        : r.punched
            ? trf('From punches: {days} ({hours} h)', {'days': _units(r.fromPunches), 'hours': r.hours.toStringAsFixed(1)})
            : tr('Not marked');
    return Card(
      key: Key('register-${r.worker.id}'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.worker.name, style: theme.textTheme.titleSmall)),
            if (r.cost > 0) Text(rupees(r.cost, paise: true), style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          Text(status, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final u in markUnits)
              ChoiceChip(
                key: Key('mark-${r.worker.id}-$u'),
                visualDensity: VisualDensity.compact,
                label: Text(markLabel(u)),
                tooltip: _units(u),
                selected: r.marked == u,
                onSelected: (_) => onMark(r.marked == u ? null : u),
              ),
          ]),
        ]),
      ),
    );
  }
}
