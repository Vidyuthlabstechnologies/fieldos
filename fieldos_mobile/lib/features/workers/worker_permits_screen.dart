/// Permits and cards: every worker's permits on a site, soonest expiry
/// first, and one worker's permits to add or renew.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/date_pick.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/workers/worker_permits.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final workerPermitsProvider = FutureProvider.autoDispose.family<List<WorkerPermit>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).siteExecutionDao.permitsFor(projectId));

(String, PillTone) permitPill(WorkerPermit p, DateTime today) {
  final d = daysLeft(p, today);
  return switch (permitStatus(p, today)) {
    PermitStatus.expired => (tr('Expired'), PillTone.danger),
    PermitStatus.dueSoon => (trf('{days} days left', {'days': d}), PillTone.warn),
    PermitStatus.ok => (tr('Valid'), PillTone.ok),
  };
}

bool _seesFullNumbers(WidgetRef ref) => Roles.canApprove(ref.read(sessionProvider).role);

/// All permits on the site, soonest expiry first.
class SitePermitsScreen extends ConsumerWidget {
  const SitePermitsScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permits = ref.watch(workerPermitsProvider(projectId));
    final workers = ref.watch(workersProvider(projectId));
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Permits and cards'))),
      body: permits.when(
        data: (rows) {
          final names = {for (final w in workers.value ?? const <Worker>[]) w.id: w.name};
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(tr('No permits yet. Open a worker and add their permits and cards, with the expiry dates.')),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            for (final p in rows)
              Card(
                child: ListTile(
                  title: Text(names[p.workerId] ?? tr('Worker')),
                  subtitle: Text([
                    tr(permitKind(p.kind)?.label ?? p.kind),
                    fmtDate(p.expiresOn),
                    if ((p.number ?? '').isNotEmpty) _seesFullNumbers(ref) ? p.number! : maskedNumber(p.number),
                  ].join(' · ')),
                  trailing: () {
                    final (label, tone) = permitPill(p, today);
                    return StatusPill(label, tone: tone);
                  }(),
                ),
              ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
      ),
    );
  }
}

/// One worker's permits: each kind the market tracks, with its date.
class WorkerPermitsScreen extends ConsumerWidget {
  const WorkerPermitsScreen({super.key, required this.worker});
  final Worker worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permits = ref.watch(workerPermitsProvider(worker.projectId));
    final today = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(worker.name)),
      body: permits.when(
        data: (rows) {
          final mine = {for (final p in rows.where((p) => p.workerId == worker.id)) p.kind: p};
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(tr('Reminders come 90, 60, 30 and 7 days before each date. Renew before the date, not after.'),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            for (final k in permitKinds)
              Card(
                child: ListTile(
                  key: Key('permit-${k.key}'),
                  title: Text(tr(k.label)),
                  subtitle: Text(mine[k.key] == null
                      ? tr('Not added')
                      : [
                          trf('Expires {date}', {'date': fmtDate(mine[k.key]!.expiresOn)}),
                          if ((mine[k.key]!.number ?? '').isNotEmpty)
                            _seesFullNumbers(ref) ? mine[k.key]!.number! : maskedNumber(mine[k.key]!.number),
                        ].join(' · ')),
                  trailing: mine[k.key] == null
                      ? const Icon(Icons.add)
                      : () {
                          final (label, tone) = permitPill(mine[k.key]!, today);
                          return StatusPill(label, tone: tone);
                        }(),
                  onTap: () => _edit(context, ref, k, mine[k.key]),
                ),
              ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, PermitKind kind, WorkerPermit? current) async {
    final number = TextEditingController(text: current?.number ?? '');
    var date = current?.expiresOn;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr(kind.label)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: number,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('Number (optional)')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Expiry date')),
              subtitle: Text(date == null ? tr('Pick a date') : fmtDate(date!)),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final now = DateTime.now();
                final picked = await pickDate(ctx,
                    initial: date ?? now.add(const Duration(days: 365)),
                    first: DateTime(now.year - 5),
                    last: DateTime(now.year + 15));
                if (picked != null) setState(() => date = picked);
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: date == null ? null : () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (saved != true || date == null) return;
    await ref.read(appDatabaseProvider).siteExecutionDao.savePermit(
          projectId: worker.projectId,
          workerId: worker.id,
          kind: kind.key,
          expiresOn: date!,
          number: number.text,
          by: ref.read(sessionProvider).user!.id,
        );
    ref.invalidate(workerPermitsProvider(worker.projectId));
  }
}
