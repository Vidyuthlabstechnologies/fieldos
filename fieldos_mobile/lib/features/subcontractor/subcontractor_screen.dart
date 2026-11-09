/// Subcontractor directory (company-scoped). Managed alongside suppliers but
/// distinct: subcontractors are the labour/agency partners tied to work orders.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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
