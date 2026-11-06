/// Multi-level approvals queue. This is the Onsite "approvals" module made
/// agentic: the cost engine raises a `budget_overrun` approval automatically
/// when a site's actuals cross its BOQ budget, and humans resolve it here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingApprovalsProvider(companyId));
    final projects = ref.watch(projectsProvider(companyId)).valueOrNull ?? const <Project>[];
    final names = {for (final p in projects) p.id: p.name};
    final canDecide = Roles.canApprove(ref.watch(sessionProvider).role);

    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingApprovalsProvider(companyId).future),
        child: pending.when(
          data: (items) => items.isEmpty
              ? const EmptyState(
                  icon: Icons.task_alt,
                  title: 'Nothing waiting',
                  message: 'When a site goes over its budget, or a purchase needs a yes, it waits here.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length + (canDecide ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (!canDecide && i == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: FormMessage('The owner or a project manager decides these. You can see what is waiting.',
                            error: false),
                      );
                    }
                    final a = items[canDecide ? i : i - 1];
                    final note = a.decisionNote?.trim() ?? '';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(approvalLabel(a.entityType), style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              '${names[a.projectId] ?? 'A project'} · raised ${_when(a.createdAt)}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(note),
                            ],
                            if (canDecide)
                              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                TextButton(onPressed: () => _reject(context, ref, a), child: const Text('Reject')),
                                const SizedBox(width: 4),
                                FilledButton(onPressed: () => _decide(context, ref, a, true, null), child: const Text('Approve')),
                              ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(
              error: e, stack: st, onRetry: () => ref.invalidate(pendingApprovalsProvider(companyId))),
        ),
      ),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, Approval a) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this?'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Reason (optional)', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok != true || !context.mounted) return;
    await _decide(context, ref, a, false, text.isEmpty ? null : text);
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Approval a, bool approve, String? note) async {
    final session = ref.read(sessionProvider);
    final user = session.user;
    if (user == null || !Roles.canApprove(session.role)) return;
    try {
      await ref.read(appDatabaseProvider).approvalDao.decide(a.id, approve, user.id, note);
      ref.invalidate(pendingApprovalsProvider(companyId));
      if (context.mounted) showSnack(context, approve ? 'Approved' : 'Rejected');
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }
}

/// "today", "yesterday" or "on 3 Nov".
String _when(DateTime t) {
  final day = fmtDay(t);
  return day == 'Today' || day == 'Yesterday' ? day.toLowerCase() : 'on $day';
}

String approvalLabel(String type) => switch (type) {
      'budget_overrun' => 'Site over budget',
      'purchase_order' => 'Purchase order',
      'material_receipt' => 'Material received',
      _ => '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}',
    };

/// Raise a budget-overrun approval for a project (the dashboard's "Ask for
/// approval" on a site that is over budget). [requestedBy] is the person
/// asking: the cloud only accepts a request raised by the signed-in user,
/// and its requested_by column holds a user id.
Future<void> raiseBudgetOverrunApproval(AppDatabase db, String projectId, double variance,
    {required String requestedBy}) async {
  await db.approvalDao.create(ApprovalsCompanion.insert(
    id: const Uuid().v4(),
    projectId: Value(projectId),
    entityType: 'budget_overrun',
    entityId: projectId,
    requestedBy: requestedBy,
    status: const Value('pending'),
    decisionNote: Value('Spending is ${rupees(variance.abs())} over the BOQ budget.'),
  ));
}

/// Whether this project already has a budget-overrun approval waiting, so
/// the dashboard does not raise the same one twice.
Future<bool> hasPendingBudgetApproval(AppDatabase db, String projectId) async =>
    (await db.approvalDao.pendingFor(projectId)).any((a) => a.entityType == 'budget_overrun');
