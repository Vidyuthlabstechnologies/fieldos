/// Subcontractor directory (company-scoped). Managed alongside suppliers but
/// distinct: subcontractors are the labour/agency partners tied to work orders.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';

class SubcontractorsScreen extends ConsumerWidget {
  const SubcontractorsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subs = ref.watch(subcontractorsProvider(companyId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Subcontractors'))),
      body: subs.when(
        data: (rows) => rows.isEmpty
            ? MitraEmpty(tr('No subcontractors yet.'))
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final s = rows[i];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.engineering),
                      title: Text(s.name),
                      subtitle: Text([s.trade, s.contactPhone]
                          .where((e) => e != null && e.isNotEmpty)
                          .join(' · ')),
                      trailing: Roles.canApprove(ref.watch(sessionProvider).role)
                          ? IconButton(
                              tooltip: tr('Give access to claim work'),
                              icon: const Icon(Icons.key_outlined),
                              onPressed: () => _shareCode(context, ref, s),
                            )
                          : null,
                    ),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => _add(context, ref),
      ),
    );
  }

  /// The code the subcontractor joins with on their own phone (free,
  /// restricted to their work orders and claims).
  Future<void> _shareCode(BuildContext context, WidgetRef ref, Subcontractor s) async {
    try {
      final service = ref.read(cloudSyncServiceProvider);
      if (!service.isSignedIn) await service.restoreSession();
      if (!service.isSignedIn) {
        if (context.mounted) showSnack(context, tr('Turn on Team & sync first.'), error: true);
        return;
      }
      await service.syncNow();
      final code = await service.subcontractorAccessCode(s.id);
      if (!context.mounted) return;
      final text = trf(
          '{name}: install FieldOS, tap "Subcontractor? Join free with the builder\'s code" and enter {code}. '
          'You will see your work orders and can claim the work you finish.',
          {'name': s.name, 'code': code});
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(trf('Access for {name}', {'name': s.name})),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(code, style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(tr('They see only their own work orders and claims, and use FieldOS free.')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close'))),
            FilledButton.icon(
              icon: const Icon(Icons.share),
              label: Text(tr('Share')),
              onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
            ),
          ],
        ),
      );
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final trade = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Add subcontractor')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
            TextField(controller: phone, decoration: InputDecoration(labelText: tr('Contact phone'))),
            TextField(controller: trade, decoration: InputDecoration(labelText: tr('Trade'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).subcontractorDao.create(SubcontractorsCompanion.insert(
          id: const Uuid().v4(),
          companyId: companyId,
          name: name.text.trim(),
          contactPhone: Value(phone.text.trim()),
          trade: Value(trade.text.trim()),
        ));
    ref.invalidate(subcontractorsProvider(companyId));
  }
}
