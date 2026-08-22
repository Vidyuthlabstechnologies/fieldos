/// Multi-level approvals queue. This is the Onsite "approvals" module made
/// agentic: the cost engine raises a `budget_overrun` approval automatically
/// when a site's actuals cross its BOQ budget, and humans resolve it here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingApprovalsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Approvals')),
      body: pending.when(
        data: (items) => items.isEmpty
            ? const Center(child: Text('No pending approvals.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final a = items[i];
                  return Card(
                    child: ListTile(
                      title: Text(_label(a.entityType)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Ref: ${a.entityId}'),
                          if (a.decisionNote != null && a.decisionNote!.isNotEmpty) Text(a.decisionNote!),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            tooltip: 'Approve',
                            onPressed: () => _decide(ref, a, true),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: 'Reject',
                            onPressed: () => _decide(ref, a, false),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }

  Future<void> _decide(WidgetRef ref, Approval a, bool approve) async {
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    await ref.read(appDatabaseProvider).approvalDao.decide(a.id, approve, user.id, null);
    ref.invalidate(pendingApprovalsProvider);
  }
}

String _label(String type) => switch (type) {
      'budget_overrun' => 'Budget overrun',
      'purchase_order' => 'Purchase order',
      'material_receipt' => 'Material receipt',
      _ => type,
    };

/// Raise a budget-overrun approval for a project (called from the dashboard
/// when a site tips into "over" budget).
Future<void> raiseBudgetOverrunApproval(AppDatabase db, String projectId, double variance) async {
  await db.approvalDao.create(ApprovalsCompanion.insert(
    id: const Uuid().v4(),
    projectId: Value(projectId),
    entityType: 'budget_overrun',
    entityId: projectId,
    requestedBy: 'cost_engine',
    status: const Value('pending'),
    decisionNote: Value('Actuals exceed BOQ budget by ₹${variance.abs().toStringAsFixed(0)}.'),
  ));
}
