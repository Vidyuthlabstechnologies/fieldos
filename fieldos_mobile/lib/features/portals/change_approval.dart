/// The client approves or declines a change before it is built (customer
/// review: the homeowner's biggest fear is extras she never agreed to).
///
/// The builder sends a change with the client's price and the days it adds;
/// the client answers once, and the server keeps who, when and any note. Online
/// only: nothing here is kept on the phone, so it does not touch the sync.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

String changeStatusLabel(ChangeRequest c, {required bool forClient}) => switch (c.status) {
      'approved' => tr('Approved'),
      'declined' => tr('Declined'),
      _ => forClient ? tr('Waiting for you') : tr('Waiting for the client'),
    };

PillTone _tone(ChangeRequest c) => switch (c.status) {
      'approved' => PillTone.ok,
      'declined' => PillTone.danger,
      _ => PillTone.warn,
    };

String _daysText(int days) => days > 0 ? trf('Adds {n} days', {'n': days}) : trf('Saves {n} days', {'n': -days});

/// What a change is, for both sides: number and title, what it is, the price,
/// and the time.
class _ChangeBody extends StatelessWidget {
  const _ChangeBody({required this.change, required this.forClient});
  final ChangeRequest change;
  final bool forClient;

  @override
  Widget build(BuildContext context) {
    final c = change;
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('#${c.number} ${c.title}', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: StatusPill(changeStatusLabel(c, forClient: forClient), tone: _tone(c)),
      ),
      if ((c.description ?? '').isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(c.description!, style: theme.textTheme.bodyMedium),
      ],
      const SizedBox(height: 6),
      Wrap(spacing: 16, runSpacing: 2, children: [
        Text(rupees(c.amount), key: Key('change-amount-${c.number}'), style: theme.textTheme.titleMedium),
        if (c.extraDays != 0) Text(_daysText(c.extraDays), style: theme.textTheme.bodySmall),
      ]),
      if (!c.pending && c.decidedOn != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(fmtDate(c.decidedOn!, short: true), style: theme.textTheme.bodySmall),
        ),
      if ((c.note ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('"${c.note}"', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
        ),
    ]);
  }
}

/// On the client's site card: changes waiting for her answer first, then the
/// ones already decided. [onChanged] reloads the portal after an answer.
class ClientChangesSection extends ConsumerWidget {
  const ClientChangesSection({super.key, required this.changes, required this.onChanged});
  final List<ChangeRequest> changes;
  final VoidCallback onChanged;

  Future<void> _decide(BuildContext context, WidgetRef ref, ChangeRequest c, {required bool approve}) async {
    final answer = await showDialog<_Answer>(
      context: context,
      builder: (ctx) => _DecideDialog(change: c, approve: approve),
    );
    if (answer == null || !context.mounted) return;
    try {
      await ref.read(portalServiceProvider).decideChange(c.id, approve: approve, note: answer.note);
      onChanged();
      if (context.mounted) showSnack(context, approve ? tr('Approved.') : tr('Declined.'));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (changes.isEmpty) return const SizedBox.shrink();
    final waiting = changes.where((c) => c.pending).length;
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(waiting == 0 ? tr('Changes') : trf('Changes to approve: {n}', {'n': waiting}),
            key: const Key('client-changes-header'), style: theme.textTheme.titleMedium),
      ),
      for (final c in changes)
        Card(
          key: Key('client-change-${c.number}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ChangeBody(change: c, forClient: true),
              if (c.pending) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      key: Key('change-decline-${c.number}'),
                      onPressed: () => _decide(context, ref, c, approve: false),
                      child: Text(tr('Decline')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: Key('change-approve-${c.number}'),
                      onPressed: () => _decide(context, ref, c, approve: true),
                      child: Text(tr('Approve')),
                    ),
                  ),
                ]),
              ],
            ]),
          ),
        ),
    ]);
  }
}

final _changesProvider = FutureProvider.autoDispose.family<List<ChangeRequest>, String>((ref, projectId) async {
  final service = ref.read(cloudSyncServiceProvider);
  if (!service.isSignedIn) await service.restoreSession();
  return ref.read(portalServiceProvider).changesFor(projectId);
});

/// The builder's side: what was sent to the client and what she answered.
class ClientChangesScreen extends ConsumerWidget {
  const ClientChangesScreen({super.key, required this.project});
  final Project project;

  Future<void> _ask(BuildContext context, WidgetRef ref) async {
    final form = await showDialog<_AskResult>(context: context, builder: (ctx) => const _AskDialog());
    if (form == null || !context.mounted) return;
    if (form.title.isEmpty) {
      showSnack(context, tr('Give the change a title.'), error: true);
      return;
    }
    final amount = form.amount;
    if (amount == null) {
      showSnack(context, tr('Enter the price for the client.'), error: true);
      return;
    }
    try {
      await ref.read(portalServiceProvider).requestChange(project.id,
          title: form.title,
          description: form.what.isEmpty ? null : form.what,
          amount: amount,
          extraDays: form.extraDays);
      ref.invalidate(_changesProvider(project.id));
      if (context.mounted) showSnack(context, tr('Sent to the client.'));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref, ChangeRequest c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Withdraw this change?')),
        content: Text('#${c.number} ${c.title}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('change-withdraw-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Withdraw'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(portalServiceProvider).withdrawChange(c.id);
      ref.invalidate(_changesProvider(project.id));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_changesProvider(project.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Client approval of changes')),
        actions: [
          IconButton(tooltip: tr('Refresh'), icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(_changesProvider(project.id))),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('change-ask'),
        icon: const Icon(Icons.add),
        label: Text(tr('Ask the client')),
        onPressed: () => _ask(context, ref),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(_changesProvider(project.id).future),
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: tr('Nothing sent yet'),
                  message: tr('Send the client a change to approve before you build it: the price, and the days it adds. '
                      'The answer is kept with the date.'),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
                  for (final c in list)
                    Card(
                      key: Key('builder-change-${c.number}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _ChangeBody(change: c, forClient: false),
                          if (c.pending)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                key: Key('change-withdraw-${c.number}'),
                                onPressed: () => _withdraw(context, ref, c),
                                child: Text(tr('Withdraw')),
                              ),
                            ),
                        ]),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }
}

class _Answer {
  const _Answer(this.note);
  final String? note;
}

/// The question before an answer is sent: what it is, a note, and that it is final.
class _DecideDialog extends StatefulWidget {
  const _DecideDialog({required this.change, required this.approve});
  final ChangeRequest change;
  final bool approve;

  @override
  State<_DecideDialog> createState() => _DecideDialogState();
}

class _DecideDialogState extends State<_DecideDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.approve ? tr('Approve this change?') : tr('Decline this change?')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('#${c.number} ${c.title}', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(rupees(c.amount), style: theme.textTheme.titleLarge),
          if (c.extraDays != 0) Text(_daysText(c.extraDays)),
          const SizedBox(height: 10),
          TextField(
            key: const Key('change-note'),
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(labelText: tr('Note (optional)'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          Text(tr('Your answer is recorded with today\'s date and cannot be changed afterwards.'),
              style: theme.textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(
          key: const Key('change-confirm'),
          onPressed: () {
            final text = _note.text.trim();
            Navigator.pop(context, _Answer(text.isEmpty ? null : text));
          },
          child: Text(widget.approve ? tr('Approve') : tr('Decline')),
        ),
      ],
    );
  }
}

class _AskResult {
  const _AskResult(this.title, this.what, this.amount, this.extraDays);
  final String title;
  final String what;
  final double? amount;
  final int extraDays;
}

class _AskDialog extends StatefulWidget {
  const _AskDialog();

  @override
  State<_AskDialog> createState() => _AskDialogState();
}

class _AskDialogState extends State<_AskDialog> {
  final _title = TextEditingController();
  final _what = TextEditingController();
  final _price = TextEditingController();
  final _days = TextEditingController();

  @override
  void dispose() {
    for (final c in [_title, _what, _price, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Ask the client')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('change-title'),
            controller: _title,
            maxLength: 120,
            decoration: InputDecoration(labelText: tr('Title'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('change-what'),
            controller: _what,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr('What changes'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('change-price'),
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('Price for the client'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('change-days'),
            controller: _days,
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            decoration: InputDecoration(labelText: tr('Extra days (optional)'), border: const OutlineInputBorder()),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(
          key: const Key('change-send'),
          onPressed: () => Navigator.pop(
            context,
            _AskResult(_title.text.trim(), _what.text.trim(), parseTypedNumber(_price.text),
                int.tryParse(westernDigits(_days.text.trim())) ?? 0),
          ),
          child: Text(tr('Send')),
        ),
      ],
    );
  }
}
