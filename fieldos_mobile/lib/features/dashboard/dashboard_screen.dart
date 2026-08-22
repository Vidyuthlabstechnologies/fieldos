/// Multi-site dashboard: every project the company runs, with a live
/// budget-vs-actuals health card powered by [CostControlAgent]. This is the
/// agentic replacement for Onsite's passive dashboards — it computes overrun
/// risk per site instead of just displaying totals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.companyId, required this.companyName});
  final String companyId;
  final String companyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(projectsProvider(companyId));

    return Scaffold(
      appBar: AppBar(title: Text('$companyName · Dashboard')),
      body: projectsAsync.when(
        data: (projects) => projects.isEmpty
            ? const Center(child: Text('No projects yet.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: projects.length,
                itemBuilder: (context, i) {
                  final p = projects[i];
                  return _ProjectHealthCard(projectId: p.id, projectName: p.name);
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProjectHealthCard extends ConsumerWidget {
  const _ProjectHealthCard({required this.projectId, required this.projectName});
  final String projectId;
  final String projectName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(costSummaryProvider(projectId));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    Expanded(child: Text(s.projectName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    _StatusChip(status: s.status),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _Metric(label: 'Budget', value: s.budget),
                    _Metric(label: 'Actual', value: s.actual),
                    _Metric(label: 'Variance', value: s.variance),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Chip(label: Text('${s.openIssues} open issues')),
                    const SizedBox(width: 8),
                    Chip(label: Text('${s.dprCount} DPRs')),
                  ],
                ),
                if (s.alerts.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...s.alerts.map((a) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: Colors.redAccent)),
                            Expanded(child: Text(a, style: const TextStyle(fontSize: 12, color: Colors.redAccent))),
                          ],
                        ),
                      )),
                ],
                if (s.status == 'over') ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.approval, size: 16),
                      label: const Text('Raise approval'),
                      onPressed: () async {
                        final user = ref.read(sessionProvider).user;
                        if (user == null) return;
                        await raiseBudgetOverrunApproval(
                          ref.read(appDatabaseProvider),
                          s.projectId,
                          s.variance,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Budget-overrun approval raised.')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
            loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
            error: (e, _) => Text('Error: $e'),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            Text('₹${value.abs().toStringAsFixed(0)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'over' => Colors.red,
      'at_risk' => Colors.orange,
      _ => Colors.green,
    };
    final label = switch (status) {
      'over' => 'OVER BUDGET',
      'at_risk' => 'AT RISK',
      _ => 'ON TRACK',
    };
    return Chip(
      label: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
