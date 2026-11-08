/// The weekly or monthly progress report for one site, ready to send.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/features/reports/period_report.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

Future<void> openPeriodReport(BuildContext context, Project project) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PeriodReportScreen(project: project)));

class PeriodReportScreen extends ConsumerStatefulWidget {
  const PeriodReportScreen({super.key, required this.project, this.now});
  final Project project;

  /// For tests.
  final DateTime? now;

  @override
  ConsumerState<PeriodReportScreen> createState() => _PeriodReportScreenState();
}

class _PeriodReportScreenState extends ConsumerState<PeriodReportScreen> {
  PeriodKind _kind = PeriodKind.thisWeek;
  late Future<PeriodReport> _report = _load();

  DateTime get _now => widget.now ?? DateTime.now();

  Future<PeriodReport> _load() =>
      buildPeriodReport(ref.read(appDatabaseProvider), widget.project, periodFor(_kind, _now), now: _now);

  void _pick(PeriodKind k) => setState(() {
        _kind = k;
        _report = _load();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMoney = canSeeMoneyIn(ref.watch(sessionProvider).role);
    final company = ref.watch(sessionProvider).activeCompany?.name ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(tr('Progress report'))),
      body: FutureBuilder<PeriodReport>(
        future: _report,
        builder: (context, snap) {
          final r = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in PeriodKind.values)
                  ChoiceChip(label: Text(tr(periodLabels[k]!)), selected: _kind == k, onSelected: (_) => _pick(k)),
              ]),
              const SizedBox(height: 8),
              if (r == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                Text('${widget.project.name} · ${periodRange(r.period)}', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                if (r.isEmpty)
                  EmptyState(
                    compact: true,
                    icon: Icons.event_note_outlined,
                    title: tr('Nothing recorded in this period'),
                    message: tr('Daily reports, attendance, tasks, issues, material and money from these days show up here.'),
                  )
                else ...[
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _Fact(trf('{done} of {days} days reported', {'done': r.reportsFiled, 'days': r.workingDays}),
                        warn: r.reportsFiled < r.workingDays),
                    _Fact(trf('{n} worker-days', {'n': r.labourDays})),
                    _Fact(trf('{n}% done overall', {'n': r.progressNow})),
                    if (r.lateTasks > 0) _Fact(trf('{n} tasks late', {'n': r.lateTasks}), warn: true),
                  ]),
                  if (r.tasksFinished.isNotEmpty) ...[
                    const SectionHeader('Finished'),
                    for (final t in r.tasksFinished)
                      ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.check_circle_outline), title: Text(t)),
                  ],
                  if (r.days.isNotEmpty) ...[
                    const SectionHeader('Day by day'),
                    for (final d in r.days)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${fmtDay(d.day)} · ${fmtDate(d.day, short: true)}'),
                        subtitle: Text(d.text),
                        trailing: d.people > 0 ? Text(trf('{n} people', {'n': d.people})) : null,
                      ),
                  ],
                  if (r.materials.isNotEmpty) ...[
                    const SectionHeader('Material received'),
                    for (final m in r.materials)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.name),
                        trailing: Text('${fmtQty(m.qty)} ${m.unit ?? ''}'.trim()),
                      ),
                  ],
                  const SectionHeader('Issues'),
                  Text(trf('{raised} raised, {fixed} fixed, {open} still open',
                      {'raised': r.issuesRaised.length, 'fixed': r.issuesFixed, 'open': r.issuesOpen})),
                  if (showMoney && (r.spent > 0 || r.received > 0)) ...[
                    const SectionHeader('Money'),
                    Text(trf('Spent {spent}, received {received}', {'spent': rupees(r.spent), 'received': rupees(r.received)})),
                    for (final e in r.spentByCategory.entries)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• ${e.key}: ${rupees(e.value)}', style: theme.textTheme.bodySmall),
                      ),
                  ],
                ],
              ],
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<PeriodReport>(
        future: _report,
        builder: (context, snap) => snap.data == null || snap.data!.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton.extended(
                icon: const Icon(Icons.share),
                label: Text(tr('Share on WhatsApp')),
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: periodReportText(snap.data!, companyName: company, showMoney: showMoney),
                )),
              ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.text, {this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => StatusPill(text, tone: warn ? PillTone.warn : PillTone.neutral);
}
