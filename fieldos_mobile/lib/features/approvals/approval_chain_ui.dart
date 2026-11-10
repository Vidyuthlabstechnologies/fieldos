/// The approval chain on screen: providers, the status line and the
/// Approve / Reject buttons used on requests, orders and expenses.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final approvalRulesProvider = FutureProvider.autoDispose.family<List<ApprovalRule>, String>(
  (ref, companyId) => ref.watch(appDatabaseProvider).approvalChainDao.rulesFor(companyId),
);

final approvalStepsProvider = FutureProvider.autoDispose.family<List<ApprovalStep>, String>(
  (ref, projectId) => ref.watch(appDatabaseProvider).approvalChainDao.stepsFor(projectId),
);

/// Everything a row needs to show and sign one item's chain.
class ChainView {
  const ChainView({required this.status, required this.amount, this.signAs});
  final ChainStatus status;
  final double amount;

  /// The level this person can sign now, or null.
  final String? signAs;
}

/// Builds a [ChainView] for an item, from what the providers already hold.
/// Null while they load.
ChainView? chainViewFor(
  WidgetRef ref, {
  required String companyId,
  required String projectId,
  required String kind,
  required String itemId,
  required double amount,
  required DateTime createdAt,
}) {
  final rules = ref.watch(approvalRulesProvider(companyId)).value;
  final steps = ref.watch(approvalStepsProvider(projectId)).value;
  final access = ref.watch(mySiteAccessProvider(projectId)).value;
  if (rules == null || steps == null) return null;
  final status = chainStatus(
    requiredLevels(rules, kind, amount, createdAt: createdAt),
    steps.where((s) => s.kind == kind && s.itemId == itemId),
  );
  return ChainView(
    status: status,
    amount: amount,
    signAs: access == null ? null : signingLevel(status, access, amount),
  );
}

/// Asks to approve or reject, and signs. Returns the decision made, or
/// null when the person backed out.
Future<bool?> signApproval(
  BuildContext context,
  WidgetRef ref, {
  required String projectId,
  required String kind,
  required String itemId,
  required String what,
  required ChainView view,
}) async {
  final level = view.signAs;
  if (level == null) return null;
  final note = TextEditingController();
  final approve = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(what),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trf('{amount}. You sign as {level}.', {'amount': rupees(view.amount), 'level': ApprovalLevel.label(level)}),
          ),
          if (view.status.waitingFor.length > 1 && level != ApprovalLevel.owner)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr('The owner approves it after you.'))),
          TextField(
            controller: note,
            decoration: InputDecoration(labelText: tr('Note (needed to reject)')),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Cancel'))),
        TextButton(
          onPressed: () {
            if (note.text.trim().isEmpty) {
              showSnack(c, tr('Say why it is rejected.'), error: true);
              return;
            }
            Navigator.pop(c, false);
          },
          child: Text(tr('Reject')),
        ),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Approve'))),
      ],
    ),
  );
  if (approve == null) return null;
  final session = ref.read(sessionProvider);
  await ref
      .read(appDatabaseProvider)
      .approvalChainDao
      .sign(
        projectId: projectId,
        kind: kind,
        itemId: itemId,
        level: level,
        approve: approve,
        amount: view.amount,
        by: session.user?.id ?? '',
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
  ref.invalidate(approvalStepsProvider(projectId));
  return approve;
}

/// One item waiting for this person's signature.
class ChainItem {
  const ChainItem(
      {required this.project, required this.kind, required this.itemId, required this.title, required this.view});
  final Project project;
  final String kind;
  final String itemId;
  final String title;
  final ChainView view;
}

/// Everything across the company's sites (those this person sees) that
/// waits for their signature: requests not yet ordered, orders not
/// cancelled, and expenses not cancelled.
final chainQueueProvider = FutureProvider.autoDispose.family<List<ChainItem>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final s = ref.watch(sessionProvider);
  final rules = await ref.watch(approvalRulesProvider(companyId).future);
  if (rules.isEmpty) return const [];
  final projects = await ref.watch(projectsProvider(companyId).future);
  final roster = await ref.watch(teamRosterProvider(companyId).future);
  final out = <ChainItem>[];
  for (final p in projects) {
    final access = await siteAccessFor(db, p.id, userId: s.user?.id, companyRole: s.role, cloudUserId: roster.myUserId);
    final steps = await db.approvalChainDao.stepsFor(p.id);
    void add(String kind, String id, String title, double amount, DateTime createdAt) {
      final status = chainStatus(
          requiredLevels(rules, kind, amount, createdAt: createdAt), steps.where((x) => x.kind == kind && x.itemId == id));
      final level = signingLevel(status, access, amount);
      if (level == null) return;
      out.add(ChainItem(
          project: p, kind: kind, itemId: id, title: title, view: ChainView(status: status, amount: amount, signAs: level)));
    }

    for (final r in await db.purchaseDao.requestsFor(p.id)) {
      if (r.status == 'pending') add(ApprovalKind.purchaseRequest, r.id, r.materialName, r.estimatedAmount ?? 0, r.createdAt);
    }
    for (final o in await db.purchaseDao.ordersFor(p.id)) {
      if (o.status != 'cancelled') {
        add(ApprovalKind.purchaseOrder, o.id, o.poNumber ?? tr('Purchase order'), o.totalAmount ?? 0, o.createdAt);
      }
    }
    for (final e in await db.expenseDao.forProject(p.id)) {
      if (!e.voided) add(ApprovalKind.expense, e.id, [e.category, if ((e.paidTo ?? '').isNotEmpty) e.paidTo!].join(' · '), e.amount, e.createdAt);
    }
  }
  out.sort((a, b) => b.view.amount.compareTo(a.view.amount));
  return out;
});

/// The list behind Approvals > "Waiting for your approval".
class ChainQueueScreen extends ConsumerWidget {
  const ChainQueueScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(chainQueueProvider(companyId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Waiting for your approval'))),
      body: queue.when(
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.task_alt,
                title: tr('Nothing waiting'),
                message: tr('Purchase requests, orders and expenses above your approval amounts wait here.'))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final i in items)
                    Card(
                      child: ListTile(
                        title: Text(i.title),
                        subtitle: Text([
                          ApprovalKind.label(i.kind),
                          i.project.name,
                          rupees(i.view.amount),
                          i.view.status.label,
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final ok = await signApproval(context, ref,
                              projectId: i.project.id, kind: i.kind, itemId: i.itemId, what: i.title, view: i.view);
                          if (ok == null) return;
                          final db = ref.read(appDatabaseProvider);
                          if (!ok && i.kind == ApprovalKind.purchaseRequest) {
                            await db.purchaseDao.setRequestStatus(i.itemId, 'rejected');
                          } else if (!ok && i.kind == ApprovalKind.purchaseOrder) {
                            await db.purchaseDao.setOrderStatus(i.itemId, 'cancelled');
                          }
                          ref.invalidate(chainQueueProvider(companyId));
                          if (context.mounted) showSnack(context, ok ? tr('Approved') : tr('Rejected'));
                        },
                      ),
                    ),
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(chainQueueProvider(companyId))),
      ),
    );
  }
}
