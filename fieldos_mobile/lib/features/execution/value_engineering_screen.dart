/// Value engineering for one site: work value done against what has been
/// spent, spend per day against the plan, and what delay is costing. Only
/// for the site's management and accounts (it shows the site's money).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/project_cost_summary.dart';
import 'package:fieldos_mobile/features/execution/value_engineering.dart';
import 'package:fieldos_mobile/features/money/expense_heads.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

typedef _Loaded = ({ProjectCostSummary summary, ValueReading? reading, List<({DateTime day, double amount})> days});

final _valueProvider = FutureProvider.autoDispose.family<_Loaded, Project>((ref, project) async {
  final db = ref.watch(appDatabaseProvider);
  final expenses = await db.expenseDao.forProject(project.id);
  final summary = await ProjectCostSummary.forProject(db, project, expenses: expenses);
  final now = DateTime.now();
  return (
    summary: summary,
    reading: readValue(
        budget: summary.budget, spent: summary.actual, progressPct: summary.progress, start: project.startDate, end: project.endDate, now: now),
    days: spendByDay(expenses, now),
  );
});

class ValueEngineeringScreen extends ConsumerWidget {
  const ValueEngineeringScreen({super.key, required this.project});
  final Project project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(siteFinanceProvider(project.id));
    final data = ref.watch(_valueProvider(project));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Value engineering'))),
      body: allowed.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (ok) => !ok
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(tr('Only the site\'s management and accounts see this.'))))
            : data.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => ErrorState(error: e, stack: st),
                data: (d) => _Body(project: project, loaded: d),
              ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.project, required this.loaded});
  final Project project;
  final _Loaded loaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = loaded.reading;
    if (r == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('Add the site budget and its start and end dates to see planned against actual.'), textAlign: TextAlign.center),
        ),
      );
    }
    final peak = loaded.days.fold<double>(0, (m, d) => d.amount > m ? d.amount : m);
    Widget row(String label, String value, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (r.spendOutpacesProgress)
        Card(
          key: const Key('value-alert-spend'),
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(trf('Spending is {n} points ahead of the work done.', {'n': r.spendAheadPoints}),
                style: TextStyle(color: theme.colorScheme.onErrorContainer, fontWeight: FontWeight.w600)),
          ),
        ),
      if (r.behindPlan)
        Card(
          key: const Key('value-alert-delay'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(trf('About {n} days behind the plan. At the planned daily spend, the delay costs {cost}.',
                {'n': r.delayDays, 'cost': rupees(r.delayCost)})),
          ),
        ),
      const SizedBox(height: 8),
      Text(tr('Planned and actual'), style: theme.textTheme.titleMedium),
      row(tr('Budget'), rupees(r.budget)),
      row(tr('Planned value (time gone)'), '${rupees(r.plannedValue)} · ${r.plannedPct}%', key: const Key('value-planned')),
      row(tr('Work value done'), '${rupees(r.workValueDone)} · ${r.progressPct}%', key: const Key('value-done')),
      row(tr('Spent'), rupees(r.spent), key: const Key('value-spent')),
      const SizedBox(height: 16),
      Text(tr('Spend per day'), style: theme.textTheme.titleMedium),
      row(tr('Average so far'), rupees(r.spendPerDay)),
      row(tr('Planned'), rupees(r.plannedPerDay)),
      const SizedBox(height: 8),
      for (final d in loaded.days)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 56, child: Text('${d.day.day}/${d.day.month}', style: theme.textTheme.bodySmall)),
            Expanded(
              child: LinearProgressIndicator(value: peak == 0 ? 0 : d.amount / peak, minHeight: 8),
            ),
            SizedBox(width: 90, child: Text(rupees(d.amount), textAlign: TextAlign.end)),
          ]),
        ),
    ]);
  }
}
