import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/purchase_screens.dart';
import 'package:fieldos_mobile/features/procurement/site_stock.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart' show onTheWayTo;
import 'package:fieldos_mobile/features/warehouse/warehouse_screen.dart' show showMoveForm, showReceiveDialog, moveRouteText;
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

final siteStockProvider = FutureProvider.autoDispose.family<List<StockLine>, String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  return buildSiteStock(await db.materialDao.forProject(projectId), await db.materialDao.usageForProject(projectId),
      moves: await db.warehouseDao.movesForSite(projectId), projectId: projectId);
});

/// Transfers on their way to this site, and the site's company (to pick
/// where to send material).
final siteIncomingProvider =
    FutureProvider.autoDispose.family<({List<StockMove> moves, String? companyId}), String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  final project = await db.projectDao.byId(projectId);
  return (moves: onTheWayTo(await db.warehouseDao.movesForSite(projectId), projectId: projectId), companyId: project?.companyId);
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
    final incoming = ref.watch(siteIncomingProvider(projectId)).value;
    final coming = incoming?.moves ?? const <StockMove>[];
    return Stack(children: [
      stock.when(
        data: (lines) => lines.isEmpty && coming.isEmpty
            ? Center(
                child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(tr('Stock appears here once material is received in the GRN tab.'), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('add-opening-stock'),
                    icon: const Icon(Icons.inventory_outlined),
                    label: Text(tr('Add stock already on site')),
                    onPressed: () => _addOpeningStock(context, ref),
                  ),
                ]),
              ))
            : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                if (coming.isNotEmpty) ...[
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SectionHeader('On the way here')),
                  for (final m in coming)
                    ListTile(
                      key: Key('incoming-${m.id}'),
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text('${m.materialName} · ${_qty(m.quantity)} ${m.unit ?? ''}'.trim()),
                      subtitle: Text(moveRouteText(m, null)),
                      trailing: FilledButton.tonal(
                        key: Key('receive-${m.id}'),
                        onPressed: () async {
                          if (await showReceiveDialog(context, ref, m, userId) != null) _refresh(ref);
                        },
                        child: Text(tr('Receive')),
                      ),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Wrap(alignment: WrapAlignment.end, children: [
                    if (incoming?.companyId != null)
                      TextButton.icon(
                        key: const Key('send-material'),
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: Text(tr('Send')),
                        onPressed: () async {
                          final m = await showMoveForm(context, ref,
                              companyId: incoming!.companyId!, userId: userId, kind: 'transfer', fromProjectId: projectId);
                          if (m != null) _refresh(ref);
                        },
                      ),
                    TextButton.icon(
                      key: const Key('add-opening-stock'),
                      icon: const Icon(Icons.inventory_outlined),
                      label: Text(tr('Opening stock')),
                      onPressed: () => _addOpeningStock(context, ref),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.calculate_outlined),
                      label: Text(tr('Unit converter')),
                      onPressed: () => openUnitConverter(context),
                    ),
                  ]),
                ),
                for (final l in lines)
                  ListTile(
                    leading: _badge(context, l.status),
                    title: Text(l.name),
                    subtitle: Text([
                      l.opening > 0
                          ? trf('Opening {opening} · Received {got} · Used {used}', {
                              'opening': _qty(l.opening),
                              'got': _qty(l.received - l.opening),
                              'used': _qty(l.used),
                            })
                          : trf('Received {got} · Used {used}', {'got': _qty(l.received), 'used': _qty(l.used)}),
                      if (l.transferredIn > 0) trf('Came in {qty}', {'qty': _qty(l.transferredIn)}),
                      if (l.transferredOut > 0) trf('Sent {qty}', {'qty': _qty(l.transferredOut)}),
                    ].join(' · ')),
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

  void _refresh(WidgetRef ref) {
    ref.invalidate(siteStockProvider(projectId));
    ref.invalidate(siteIncomingProvider(projectId));
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

  /// Material already in the store when the site started using FieldOS,
  /// so the balance is right from day one. It costs nothing here (it was
  /// paid for before), so it never adds to the site's spending.
  Future<void> _addOpeningStock(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final qty = TextEditingController();
    final unit = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Stock already on site')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('What is in the store today, before any GRN in FieldOS. It is not counted as money spent.'),
              style: Theme.of(ctx).textTheme.bodySmall),
          TextField(
              key: const Key('opening-name'),
              controller: name,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Material (e.g. Cement)'))),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('opening-qty'),
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Quantity')),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 90,
                child: TextField(
                    key: const Key('opening-unit'), controller: unit, decoration: InputDecoration(labelText: tr('Unit')))),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('opening-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final q = double.tryParse(qty.text.trim().replaceAll(',', ''));
    if (ok != true || q == null || q <= 0 || name.text.trim().isEmpty) return;
    await ref.read(appDatabaseProvider).materialDao.createReceipt(MaterialReceiptsCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          materialName: name.text.trim(),
          quantity: q,
          unit: Value(unit.text.trim().isEmpty ? null : unit.text.trim()),
          amount: 0,
          receivedBy: userId,
          receivedOn: DateTime.now(),
          notes: const Value(openingStockNote),
        ));
    ref.invalidate(siteStockProvider(projectId));
    ref.invalidate(receiptsProvider(projectId));
  }

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
