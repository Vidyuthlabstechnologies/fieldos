import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

final siteStockProvider = FutureProvider.autoDispose.family<List<StockLine>, String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  return buildSiteStock(await db.materialDao.forProject(projectId), await db.materialDao.usageForProject(projectId));
});

String _qty(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

/// What's in the site store right now: received (GRN tab) minus used.
class StockView extends ConsumerWidget {
  const StockView({super.key, required this.projectId, required this.userId});
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(siteStockProvider(projectId));
    return Stack(children: [
      stock.when(
        data: (lines) => lines.isEmpty
            ? Center(
                child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr('Stock appears here once material is received in the GRN tab.'), textAlign: TextAlign.center),
              ))
            : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                for (final l in lines)
                  ListTile(
                    leading: _badge(context, l.status),
                    title: Text(l.name),
                    subtitle: Text('Received ${_qty(l.received)} · Used ${_qty(l.used)}'),
                    trailing: Text('${_qty(l.balance)} ${l.unit ?? ''}'.trim(),
                        style: TextStyle(fontWeight: FontWeight.w700, color: _color(context, l.status))),
                    onTap: () => _recordUsage(context, ref, preset: l),
                  ),
              ]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'record-usage',
          onPressed: () => _recordUsage(context, ref),
          icon: const Icon(Icons.outbox),
          label: Text(tr('Record material used')),
        ),
      ),
    ]);
  }

  static Color? _color(BuildContext context, StockStatus s) => switch (s) {
        StockStatus.overused || StockStatus.out => toneColor(context, PillTone.danger),
        StockStatus.low => toneColor(context, PillTone.warn),
        StockStatus.ok => null,
      };

  static Widget _badge(BuildContext context, StockStatus s) => switch (s) {
        StockStatus.overused => Tooltip(
            message: tr('More used than received. Check for a missing GRN or loss.'),
            child: Icon(Icons.error, color: toneColor(context, PillTone.danger))),
        StockStatus.out =>
          Tooltip(message: tr('Nothing left'), child: Icon(Icons.remove_circle, color: toneColor(context, PillTone.danger))),
        StockStatus.low => Tooltip(
            message: tr('Running low: order soon'), child: Icon(Icons.warning_amber, color: toneColor(context, PillTone.warn))),
        StockStatus.ok => Icon(Icons.check_circle_outline, color: toneColor(context, PillTone.ok)),
      };

  Future<void> _recordUsage(BuildContext context, WidgetRef ref, {StockLine? preset}) async {
    final name = TextEditingController(text: preset?.name ?? '');
    final qty = TextEditingController();
    final unit = TextEditingController(text: preset?.unit ?? '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Material used')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Material (e.g. Cement)'))),
          Row(children: [
            Expanded(
              child: TextField(
                controller: qty,
                autofocus: preset != null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Quantity used')),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(width: 90, child: TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit')))),
          ]),
          TextField(controller: note, decoration: InputDecoration(labelText: tr('Where (e.g. 2nd floor slab)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final q = double.tryParse(qty.text.trim());
    if (ok != true || q == null || q <= 0 || name.text.trim().isEmpty) return;
    await ref.read(appDatabaseProvider).materialDao.recordUsage(MaterialUsageCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          materialName: name.text.trim(),
          quantity: q,
          unit: Value(unit.text.trim().isEmpty ? null : unit.text.trim()),
          recordedBy: userId,
          usedOn: DateTime.now(),
          note: Value(note.text.trim().isEmpty ? null : note.text.trim()),
        ));
    ref.invalidate(siteStockProvider(projectId));
  }
}
