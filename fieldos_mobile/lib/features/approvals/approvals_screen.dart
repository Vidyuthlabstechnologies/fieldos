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
import 'package:fieldos_mobile/features/close/week_close_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingApprovalsProvider(companyId));
    final projects = ref.watch(projectsProvider(companyId)).value ?? const <Project>[];
    final names = {for (final p in projects) p.id: p.name};
    final canDecide = Roles.canApprove(ref.watch(sessionProvider).role);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Approvals'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(pendingApprovalsProvider(companyId).future),
        child: pending.when(
          data: (items) => items.isEmpty
              ? Column(
                  children: [
                    _WeeklyCloseLink(companyId: companyId),
                    Expanded(
                      child: EmptyState(
                        icon: Icons.task_alt,
                        title: tr('Nothing waiting'),
                        message: tr('When a site goes over its budget, or a purchase needs a yes, it waits here.'),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length + (canDecide ? 1 : 2),
                  itemBuilder: (context, i) {
                    if (i == 0) return _WeeklyCloseLink(companyId: companyId, padding: EdgeInsets.zero);
                    i -= 1;
                    if (!canDecide && i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                        child: FormMessage(
                          tr('The owner or a project manager decides these. You can see what is waiting.'),
                          error: false,
                        ),
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
                              '${names[a.projectId] ?? tr('A project')} · ${raisedWhen(a.createdAt)}',
                              style: Theme.of(
                                context,
                              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            if (note.isNotEmpty) ...[const SizedBox(height: 8), Text(note)],
                            if (canDecide)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(onPressed: () => _reject(context, ref, a), child: Text(tr('Reject'))),
                                  const SizedBox(width: 4),
                                  FilledButton(
                                    onPressed: () => _decide(context, ref, a, true, null),
                                    child: Text(tr('Approve')),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) =>
              ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(pendingApprovalsProvider(companyId))),
        ),
      ),
    );
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, Approval a) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Reject this?')),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLength: 200,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Reason (optional)'), counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Reject'))),
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
      if (context.mounted) showSnack(context, approve ? tr('Approved') : tr('Rejected'));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }
}

/// Wages, expenses and deliveries are approved a week at a time, in the
/// weekly close; this card leads there from the approvals queue.
class _WeeklyCloseLink extends StatelessWidget {
  const _WeeklyCloseLink({required this.companyId, this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 0)});
  final String companyId;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Card(
      child: ListTile(
        leading: const Icon(Icons.fact_check_outlined),
        title: Text(tr('Weekly close')),
        subtitle: Text(tr('Approve each site\'s wages, expenses and deliveries for the week.')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => WeeklyCloseListScreen(companyId: companyId))),
      ),
    ),
  );
}

/// "raised today", "raised yesterday" or "raised on 3 Nov", in the app's
/// language. (It used to compare the already-translated day with the
/// English word, so other languages read "raised on आज".)
String raisedWhen(DateTime t, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final l = t.toLocal();
  final days = DateTime(n.year, n.month, n.day).difference(DateTime(l.year, l.month, l.day)).inDays;
  return switch (days) {
    0 => tr('raised today'),
    1 => tr('raised yesterday'),
    _ => trf('raised on {date}', {'date': fmtDate(l, short: true, now: n)}),
  };
}

String approvalLabel(String type) => switch (type) {
  'budget_overrun' => tr('Site over budget'),
  'purchase_order' => tr('Purchase order'),
  'material_receipt' => tr('Material received'),
  _ => tr('${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}'),
};

/// Raise a budget-overrun approval for a project (the dashboard's "Ask for
/// approval" on a site that is over budget). [requestedBy] is the person
/// asking: the cloud only accepts a request raised by the signed-in user,
/// and its requested_by column holds a user id.
Future<void> raiseBudgetOverrunApproval(
  AppDatabase db,
  String projectId,
  double variance, {
  required String requestedBy,
}) async {
  await db.approvalDao.create(
    ApprovalsCompanion.insert(
      id: const Uuid().v4(),
      projectId: Value(projectId),
      entityType: 'budget_overrun',
      entityId: projectId,
      requestedBy: requestedBy,
      status: const Value('pending'),
      decisionNote: Value('Spending is ${rupees(variance.abs())} over the BOQ budget.'),
    ),
  );
}

/// Whether this project already has a budget-overrun approval waiting, so
/// the dashboard does not raise the same one twice.
Future<bool> hasPendingBudgetApproval(AppDatabase db, String projectId) async =>
    (await db.approvalDao.pendingFor(projectId)).any((a) => a.entityType == 'budget_overrun');
