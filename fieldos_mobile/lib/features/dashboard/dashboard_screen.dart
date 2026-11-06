/// Multi-site dashboard: every project the company runs, with a live
/// budget-vs-actuals health card powered by [CostControlAgent]. This is the
/// agentic replacement for Onsite's passive dashboards — it computes overrun
/// risk per site instead of just displaying totals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.companyId, required this.companyName});
  final String companyId;
  final String companyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider(companyId));

    return Scaffold(
      appBar: AppBar(title: Text(tr('Dashboard'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(projectsProvider(companyId).future),
        child: projectsAsync.when(
          data: (projects) => projects.isEmpty
              ? EmptyState(
                  icon: Icons.insights_outlined,
                  title: tr('No projects yet'),
                  message: tr('Each site shows here with its budget, spending, open issues and daily reports.'),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(companyName, style: Theme.of(context).textTheme.titleLarge),
                    ),
                    for (final p in projects) _ProjectHealthCard(projectId: p.id, companyId: companyId),
                  ],
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) =>
              ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(projectsProvider(companyId))),
        ),
      ),
    );
  }
}

class _ProjectHealthCard extends ConsumerWidget {
  const _ProjectHealthCard({required this.projectId, required this.companyId});
  final String projectId;
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(costSummaryProvider(projectId));
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final project = await ref.read(appDatabaseProvider).projectDao.byId(projectId);
          if (project != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: summaryAsync.when(
            data: (s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(s.projectName,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium)),
                    const SizedBox(width: 8),
                    StatusPill(_statusLabel(s.status), tone: _statusTone(s.status)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Metric(label: tr('Budget'), value: s.status == 'no_budget' ? 'Not set' : rupees(s.budget)),
                    _Metric(label: tr('Spent'), value: rupees(s.actual)),
                    if (s.status != 'no_budget')
                      _Metric(
                        label: s.variance < 0 ? tr('Over by') : tr('Left'),
                        value: rupees(s.variance.abs()),
                        warn: s.variance < 0,
                      ),
                  ],
                ),
                if (s.status == 'no_budget') ...[
                  const SizedBox(height: 8),
                  Text(tr('Add a priced BOQ under Estimation to compare spending with a budget.'),
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ],
                const SizedBox(height: 10),
                Text(
                  [
                    s.openIssues == 1 ? '1 open issue' : '${s.openIssues} open issues',
                    s.dprCount == 1 ? '1 daily report' : '${s.dprCount} daily reports',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                if (s.alerts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final a in s.alerts.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
                          const SizedBox(width: 6),
                          Expanded(child: Text(a, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  if (s.alerts.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 22),
                      child: Text('and ${s.alerts.length - 3} more',
                          style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                    ),
                ],
                if (s.status == 'over' && Roles.canWrite(ref.watch(sessionProvider).role ?? Roles.viewer)) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.approval_outlined, size: 18),
                      label: Text(tr('Ask for approval')),
                      onPressed: () => _raise(context, ref, s.projectId, s.variance),
                    ),
                  ),
                ],
              ],
            ),
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (e, st) => Text(friendlyError(e, st)),
          ),
        ),
      ),
    );
  }

  Future<void> _raise(BuildContext context, WidgetRef ref, String projectId, double variance) async {
    final db = ref.read(appDatabaseProvider);
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    if (await hasPendingBudgetApproval(db, projectId)) {
      if (context.mounted) showSnack(context, 'This site is already waiting for approval.');
      return;
    }
    await raiseBudgetOverrunApproval(db, projectId, variance, requestedBy: user.id);
    ref.invalidate(pendingApprovalsProvider(companyId));
    if (context.mounted) showSnack(context, 'Sent to Approvals for the owner or a project manager');
  }
}

String _statusLabel(String status) => switch (status) {
      'over' => tr('Over budget'),
      'at_risk' => tr('Close to budget'),
      'no_budget' => tr('No budget yet'),
      _ => tr('On track'),
    };

PillTone _statusTone(String status) => switch (status) {
      'over' => PillTone.danger,
      'at_risk' => PillTone.warn,
      'no_budget' => PillTone.neutral,
      _ => PillTone.ok,
    };

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.warn = false});
  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: theme.textTheme.titleSmall?.copyWith(color: warn ? theme.colorScheme.error : null)),
          ),
        ],
      ),
    );
  }
}
