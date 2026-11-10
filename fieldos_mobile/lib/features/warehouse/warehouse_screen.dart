/// Stores and tools: the company's own stores (yard, godown), material
/// bought into them, sent to sites and counted on arrival, and the tools
/// register with who has what and what is overdue.
///
/// Owners and project managers run this screen. Sites see transfers on
/// their way in their Stock tab, count them in there, and send leftover
/// material on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/warehouse/tools_rules.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

typedef WarehouseData = ({
  List<Store> stores,
  List<StockMove> moves,
  List<Tool> tools,
  List<ToolIssue> issues,
  List<Project> sites,
});

final warehouseDataProvider = FutureProvider.autoDispose.family<WarehouseData, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final dao = db.warehouseDao;
  return (
    stores: await dao.storesFor(companyId),
    moves: await dao.movesFor(companyId),
    tools: await dao.toolsFor(companyId),
    issues: await dao.issuesFor(companyId),
    sites: await db.projectDao.forCompany(companyId),
  );
});

/// Places names for a move's route, loaded once per company.
final _placeNamesProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  return {
    for (final s in await db.warehouseDao.storesFor(companyId, includeArchived: true)) s.id: s.name,
    for (final p in await db.projectDao.forCompany(companyId)) p.id: p.name,
  };
});

void refreshWarehouse(WidgetRef ref, String companyId) {
  ref.invalidate(warehouseDataProvider(companyId));
  ref.invalidate(_placeNamesProvider(companyId));
}

String _qty(double v) => fmtQty(v);

/// "Main store -> Narapally" for a move. With no names (a site's own
/// screen), the far end is described in words.
String moveRouteText(StockMove m, Map<String, String>? names) {
  String place(String? storeId, String? projectId) {
    final id = storeId ?? projectId;
    if (id == null) return '';
    return names?[id] ?? (storeId != null ? tr('Store') : tr('Another site'));
  }

  final from = m.kind == 'inward' ? (m.supplierName ?? tr('Supplier')) : place(m.fromStoreId, m.fromProjectId);
  final to = place(m.toStoreId, m.toProjectId);
  final when = fmtDate(m.sentOn, short: true);
  if (m.kind == 'adjust') {
    return '${m.toStoreId != null ? tr('Count was more') : tr('Count was short')} · ${place(m.fromStoreId ?? m.toStoreId, null)} · $when';
  }
  final vehicle = m.vehicle == null ? '' : ' · ${m.vehicle}';
  return '$from → $to · $when$vehicle';
}

PillTone _moveTone(String status) => switch (status) {
      'in_transit' => PillTone.warn,
      'cancelled' => PillTone.neutral,
      _ => PillTone.ok,
    };

class WarehouseScreen extends ConsumerStatefulWidget {
  const WarehouseScreen({super.key, required this.companyId, required this.userId});
  final String companyId;
  final String userId;

  @override
  ConsumerState<WarehouseScreen> createState() => _WarehouseScreenState();
}

class _WarehouseScreenState extends ConsumerState<WarehouseScreen> {
  String? _storeId;

  Future<void> _addStore() async {
    final s = await showStoreForm(context, ref, companyId: widget.companyId, userId: widget.userId);
    if (s != null && mounted) {
      setState(() => _storeId = s.id);
      refreshWarehouse(ref, widget.companyId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(warehouseDataProvider(widget.companyId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('Stores and tools')),
          bottom: TabBar(tabs: [
            Tab(text: tr('Stock')),
            Tab(text: tr('On the way')),
            Tab(text: tr('Tools')),
          ]),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
          data: (d) {
            final store = d.stores.where((s) => s.id == _storeId).firstOrNull ?? d.stores.firstOrNull;
            return TabBarView(children: [
              store == null
                  ? EmptyState(
                      icon: Icons.warehouse_outlined,
                      title: tr('No store yet'),
                      message: tr('Add the yard or godown where material is kept before it goes to sites. '
                          'Buy into it, send to sites, and see what each store holds and what it is worth.'),
                      actionLabel: tr('Add store'),
                      onAction: _addStore,
                    )
                  : _StockTab(
                      data: d,
                      store: store,
                      companyId: widget.companyId,
                      userId: widget.userId,
                      onPickStore: (id) => setState(() => _storeId = id),
                      onAddStore: _addStore,
                    ),
              _OnTheWayTab(data: d, companyId: widget.companyId, userId: widget.userId),
              _ToolsTab(data: d, companyId: widget.companyId, userId: widget.userId),
            ]);
          },
        ),
      ),
    );
  }
}

class _StockTab extends ConsumerWidget {
  const _StockTab({
    required this.data,
    required this.store,
    required this.companyId,
    required this.userId,
    required this.onPickStore,
    required this.onAddStore,
  });
  final WarehouseData data;
  final Store store;
  final String companyId;
  final String userId;
  final ValueChanged<String> onPickStore;
  final VoidCallback onAddStore;

  Future<void> _move(BuildContext context, WidgetRef ref, String kind, {StoreStockLine? line, bool gain = false}) async {
    final m = await showMoveForm(
      context,
      ref,
      companyId: companyId,
      userId: userId,
      kind: kind,
      fromStoreId: kind == 'transfer' || (kind == 'adjust' && !gain) ? store.id : null,
      toStoreId: kind == 'inward' || (kind == 'adjust' && gain) ? store.id : null,
      materialName: line?.name,
      unit: line?.unit,
    );
    if (m != null) refreshWarehouse(ref, companyId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = storeStock(data.moves, store.id);
    final value = lines.fold(0.0, (s, l) => s + l.value);
    final coming = onTheWayTo(data.moves, storeId: store.id).length;
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: const Key('store-picker'),
            initialValue: store.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Store'), border: const OutlineInputBorder()),
            items: [for (final s in data.stores) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : onPickStore(v),
          ),
        ),
        IconButton(tooltip: tr('Add store'), icon: const Icon(Icons.add_business_outlined), onPressed: onAddStore),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(spacing: 24, runSpacing: 8, children: [
            _Figure(label: tr('Worth'), value: rupees(value)),
            _Figure(label: tr('Materials'), value: '${lines.where((l) => l.balance > 0).length}'),
            _Figure(label: tr('On the way in'), value: '$coming'),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilledButton.icon(
          key: const Key('store-inward'),
          icon: const Icon(Icons.move_to_inbox_outlined),
          label: Text(tr('Material in')),
          onPressed: () => _move(context, ref, 'inward'),
        ),
        OutlinedButton.icon(
          key: const Key('store-send'),
          icon: const Icon(Icons.local_shipping_outlined),
          label: Text(tr('Send to site')),
          onPressed: lines.any((l) => l.balance > 0) ? () => _move(context, ref, 'transfer') : null,
        ),
        TextButton.icon(
          key: const Key('store-adjust'),
          icon: const Icon(Icons.tune),
          label: Text(tr('Correct count')),
          onPressed: () async {
            final gain = await showDialog<bool>(
              context: context,
              builder: (ctx) => SimpleDialog(title: Text(tr('Correct count')), children: [
                SimpleDialogOption(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Less than the app shows'))),
                SimpleDialogOption(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('More than the app shows'))),
              ]),
            );
            if (gain != null && context.mounted) await _move(context, ref, 'adjust', gain: gain);
          },
        ),
      ]),
      if (lines.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(tr('Nothing in this store yet. Use Material in when a load arrives.'),
              textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
        )
      else ...[
        const SectionHeader('In this store'),
        for (final l in lines)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.name),
            subtitle: Text([
              trf('In {inQty} · Out {outQty}', {'inQty': _qty(l.inQty), 'outQty': _qty(l.outQty)}),
              if (l.avgRate != null) trf('{rate} a unit', {'rate': rupees(l.avgRate!, paise: true)}),
            ].join(' · ')),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${_qty(l.balance)} ${l.unit ?? ''}'.trim(),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: l.balance < 0 ? toneColor(context, PillTone.danger) : null)),
              if (l.value > 0) Text(rupees(l.value), style: theme.textTheme.bodySmall),
            ]),
            onTap: l.balance > 0 ? () => _move(context, ref, 'transfer', line: l) : null,
          ),
      ],
      const SectionHeader('Recent moves'),
      for (final m in data.moves.where((m) => m.fromStoreId == store.id || m.toStoreId == store.id).take(30))
        _MoveTile(move: m, companyId: companyId, userId: userId),
    ]);
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: t.bodySmall),
      Text(value, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

class _MoveTile extends ConsumerWidget {
  const _MoveTile({required this.move, required this.companyId, required this.userId});
  final StockMove move;
  final String companyId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(_placeNamesProvider(companyId)).value;
    final m = move;
    final short = shortage(m);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${m.materialName} · ${_qty(m.quantity)} ${m.unit ?? ''}'.trim()),
      subtitle: Text([
        moveRouteText(m, names),
        if (short > 0) trf('Short by {qty}', {'qty': _qty(short)}),
        if (m.note != null) m.note!,
      ].join('\n')),
      isThreeLine: short > 0 || m.note != null,
      trailing: StatusPill(moveStatusLabels[m.status] ?? m.status, tone: short > 0 ? PillTone.danger : _moveTone(m.status)),
    );
  }
}

class _OnTheWayTab extends ConsumerWidget {
  const _OnTheWayTab({required this.data, required this.companyId, required this.userId});
  final WarehouseData data;
  final String companyId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(_placeNamesProvider(companyId)).value;
    final open = [for (final m in data.moves) if (m.status == 'in_transit') m]..sort((a, b) => a.sentOn.compareTo(b.sentOn));
    final short = [for (final m in data.moves) if (shortage(m) > 0) m];
    if (open.isEmpty && short.isEmpty) {
      return EmptyState(
        icon: Icons.local_shipping_outlined,
        title: tr('Nothing on the way'),
        message: tr('Material sent from a store or a site shows here until the other end counts it in.'),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
      if (open.isNotEmpty) const SectionHeader('Not yet received'),
      for (final m in open)
        Card(
          child: ListTile(
            key: Key('transit-${m.id}'),
            title: Text('${m.materialName} · ${_qty(m.quantity)} ${m.unit ?? ''}'.trim()),
            subtitle: Text(moveRouteText(m, names)),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'receive') {
                  if (await showReceiveDialog(context, ref, m, userId) != null) refreshWarehouse(ref, companyId);
                } else if (v == 'cancel') {
                  try {
                    await ref.read(appDatabaseProvider).warehouseDao.cancelMove(m.id, reason: tr('Called back'));
                    refreshWarehouse(ref, companyId);
                  } on ArgumentError catch (e) {
                    if (context.mounted) showSnack(context, tr('${e.message}'), error: true);
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'receive', child: Text(tr('Receive'))),
                PopupMenuItem(value: 'cancel', child: Text(tr('Call back'))),
              ],
            ),
          ),
        ),
      if (short.isNotEmpty) ...[
        const SectionHeader('Arrived short'),
        for (final m in short.take(30)) _MoveTile(move: m, companyId: companyId, userId: userId),
      ],
    ]);
  }
}

// --- Forms -----------------------------------------------------------------

Future<Store?> showStoreForm(BuildContext context, WidgetRef ref,
    {required String companyId, required String userId}) async {
  final name = TextEditingController();
  final location = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Add store')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
            key: const Key('store-name'),
            controller: name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Store name (e.g. Main yard)'))),
        TextField(controller: location, decoration: InputDecoration(labelText: tr('Where it is'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(key: const Key('store-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  return ref
      .read(appDatabaseProvider)
      .warehouseDao
      .addStore(companyId: companyId, name: name.text, location: location.text, by: userId);
}

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', ''));

/// The form for every kind of move. Fixed ends ([fromStoreId] and so on)
/// are not asked; the open end is picked from the company's stores and
/// sites. Returns the saved move.
Future<StockMove?> showMoveForm(
  BuildContext context,
  WidgetRef ref, {
  required String companyId,
  required String userId,
  required String kind,
  String? fromStoreId,
  String? fromProjectId,
  String? toStoreId,
  String? materialName,
  String? unit,
}) async {
  final db = ref.read(appDatabaseProvider);
  final stores = await db.warehouseDao.storesFor(companyId);
  final sites = await db.projectDao.forCompany(companyId);
  if (!context.mounted) return null;
  return showModalBottomSheet<StockMove>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MoveForm(
      companyId: companyId,
      userId: userId,
      kind: kind,
      fromStoreId: fromStoreId,
      fromProjectId: fromProjectId,
      toStoreId: toStoreId,
      materialName: materialName,
      unit: unit,
      stores: stores,
      sites: sites,
    ),
  );
}

class _MoveForm extends ConsumerStatefulWidget {
  const _MoveForm({
    required this.companyId,
    required this.userId,
    required this.kind,
    required this.stores,
    required this.sites,
    this.fromStoreId,
    this.fromProjectId,
    this.toStoreId,
    this.materialName,
    this.unit,
  });
  final String companyId;
  final String userId;
  final String kind;
  final String? fromStoreId;
  final String? fromProjectId;
  final String? toStoreId;
  final String? materialName;
  final String? unit;
  final List<Store> stores;
  final List<Project> sites;

  @override
  ConsumerState<_MoveForm> createState() => _MoveFormState();
}

class _MoveFormState extends ConsumerState<_MoveForm> {
  late final _name = TextEditingController(text: widget.materialName ?? '');
  late final _unit = TextEditingController(text: widget.unit ?? '');
  final _qty = TextEditingController();
  final _rate = TextEditingController();
  final _supplier = TextEditingController();
  final _vehicle = TextEditingController();
  final _note = TextEditingController();
  String? _to;
  String? _error;
  bool _saving = false;

  bool get _fixedFrom => widget.fromStoreId != null || widget.fromProjectId != null;
  String? get _fromId => widget.fromStoreId ?? widget.fromProjectId;

  List<DropdownMenuItem<String>> get _places => [
        for (final s in widget.stores)
          if (s.id != _fromId) DropdownMenuItem(value: 's:${s.id}', child: Text('${tr('Store')}: ${s.name}', overflow: TextOverflow.ellipsis)),
        for (final p in widget.sites)
          if (p.id != _fromId) DropdownMenuItem(value: 'p:${p.id}', child: Text(p.name, overflow: TextOverflow.ellipsis)),
      ];

  String get _title => switch (widget.kind) {
        'inward' => tr('Material into store'),
        'adjust' => widget.toStoreId != null ? tr('Count was more') : tr('Count was short'),
        _ => tr('Send material'),
      };

  Future<void> _save() async {
    final qty = _num(_qty.text) ?? 0;
    final rate = _rate.text.trim().isEmpty ? null : _num(_rate.text);
    String? toStore = widget.toStoreId, toProject;
    if (widget.kind == 'transfer') {
      if (_to == null) {
        setState(() => _error = tr('Pick where it goes.'));
        return;
      }
      if (_to!.startsWith('s:')) {
        toStore = _to!.substring(2);
      } else {
        toProject = _to!.substring(2);
      }
    }
    final problem = checkMove(
      kind: widget.kind,
      fromStoreId: widget.fromStoreId,
      fromProjectId: widget.fromProjectId,
      toStoreId: toStore,
      toProjectId: toProject,
      materialName: _name.text,
      quantity: qty,
      note: _note.text,
    );
    if (problem != null) {
      setState(() => _error = tr(problem));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final m = await ref.read(appDatabaseProvider).warehouseDao.addMove(
            companyId: widget.companyId,
            kind: widget.kind,
            materialName: _name.text,
            quantity: qty,
            unit: _unit.text,
            by: widget.userId,
            fromStoreId: widget.fromStoreId,
            fromProjectId: widget.fromProjectId,
            toStoreId: toStore,
            toProjectId: toProject,
            supplierName: _supplier.text,
            rate: rate,
            vehicle: _vehicle.text,
            note: _note.text,
          );
      if (mounted) Navigator.pop(context, m);
    } on ArgumentError catch (e) {
      setState(() {
        _saving = false;
        _error = tr('${e.message}');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + inset),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(_title, style: Theme.of(context).textTheme.titleLarge),
          if (widget.kind == 'transfer' && _fixedFrom) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: const Key('move-to'),
              initialValue: _to,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Send to')),
              items: _places,
              onChanged: (v) => setState(() => _to = v),
            ),
          ],
          if (widget.kind == 'inward')
            TextField(
                key: const Key('move-supplier'),
                controller: _supplier,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Supplier'))),
          TextField(
              key: const Key('move-material'),
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Material (e.g. Cement)'))),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('move-qty'),
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Quantity')),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 90,
                child: TextField(key: const Key('move-unit'), controller: _unit, decoration: InputDecoration(labelText: tr('Unit')))),
          ]),
          if (widget.kind != 'adjust')
            TextField(
              key: const Key('move-rate'),
              controller: _rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr('Rate a unit (₹)'),
                helperText: widget.fromStoreId != null ? tr('Leave empty to use the store average') : null,
              ),
            ),
          if (widget.kind == 'transfer')
            TextField(
                key: const Key('move-vehicle'),
                controller: _vehicle,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: tr('Vehicle number'))),
          if (widget.kind == 'adjust')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 4, children: [
                for (final r in adjustReasonChoices)
                  ActionChip(label: Text(tr(r)), onPressed: () => setState(() => _note.text = tr(r))),
              ]),
            ),
          TextField(
              key: const Key('move-note'),
              controller: _note,
              decoration: InputDecoration(labelText: widget.kind == 'adjust' ? tr('Why the count changed') : tr('Note'))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: FormMessage(_error!)),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('move-save'),
            onPressed: _saving ? null : _save,
            child: Text(widget.kind == 'transfer' ? tr('Send') : tr('Save')),
          ),
        ]),
      ),
    );
  }
}

/// Counts a transfer in. Returns the received move, or null when closed.
Future<StockMove?> showReceiveDialog(BuildContext context, WidgetRef ref, StockMove m, String userId) async {
  final qty = TextEditingController(text: _qty(m.quantity));
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Receive')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(trf('{qty} {unit} of {name} were sent. Count what arrived.',
            {'qty': _qty(m.quantity), 'unit': m.unit ?? '', 'name': m.materialName})),
        TextField(
          key: const Key('receive-qty'),
          controller: qty,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Quantity that arrived')),
        ),
        TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(key: const Key('receive-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Receive'))),
      ],
    ),
  );
  if (ok != true) return null;
  try {
    return await ref
        .read(appDatabaseProvider)
        .warehouseDao
        .receive(m.id, by: userId, arrived: _num(qty.text), note: note.text);
  } on ArgumentError catch (e) {
    if (context.mounted) showSnack(context, tr('${e.message}'), error: true);
    return null;
  }
}

// --- Tools -----------------------------------------------------------------

PillTone _toolTone(ToolState s) => switch (s) {
      ToolState.available => PillTone.ok,
      ToolState.issued => PillTone.neutral,
      ToolState.overdue || ToolState.lost => PillTone.danger,
      ToolState.repair => PillTone.warn,
      ToolState.retired => PillTone.neutral,
    };

class _ToolsTab extends ConsumerStatefulWidget {
  const _ToolsTab({required this.data, required this.companyId, required this.userId});
  final WarehouseData data;
  final String companyId;
  final String userId;

  @override
  ConsumerState<_ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends ConsumerState<_ToolsTab> {
  String _query = '';

  Future<void> _addTool() async {
    if (await showToolForm(context, ref, data: widget.data, companyId: widget.companyId, userId: widget.userId) != null) {
      refreshWarehouse(ref, widget.companyId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final now = DateTime.now();
    final c = toolCounts(d.tools, d.issues, now);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final t in d.tools)
        if (q.isEmpty || t.name.toLowerCase().contains(q) || (t.code ?? '').toLowerCase().contains(q) ||
            (openIssueOf(t.id, d.issues)?.issuedTo.toLowerCase().contains(q) ?? false))
          t
    ]..sort((a, b) {
        final sa = toolState(a, d.issues, now), sb = toolState(b, d.issues, now);
        int rank(ToolState s) => s == ToolState.overdue ? 0 : (s == ToolState.retired ? 2 : 1);
        final r = rank(sa).compareTo(rank(sb));
        return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final recover = toRecover(d.issues);
    final sites = {for (final p in d.sites) p.id: p.name};
    return Stack(children: [
      if (d.tools.isEmpty)
        EmptyState(
          icon: Icons.handyman_outlined,
          title: tr('No tools yet'),
          message: tr('Add drills, vibrators, levels and other tools. Hand them to people with a return date, '
              'see who has what, and keep what is to be recovered for a lost one.'),
          actionLabel: tr('Add tool'),
          onAction: _addTool,
        )
      else
        ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Wrap(spacing: 24, runSpacing: 8, children: [
                _Figure(label: tr('Tools'), value: '${c.total}'),
                _Figure(label: tr('With someone'), value: '${c.out}'),
                _Figure(label: tr('Overdue'), value: '${c.overdue}'),
                _Figure(label: tr('Worth'), value: rupees(c.value)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('tool-search'),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Search tool, tag or person')),
            onChanged: (v) => setState(() => _query = v),
          ),
          for (final t in shown)
            Builder(builder: (context) {
              final s = toolState(t, d.issues, now);
              final open = openIssueOf(t.id, d.issues);
              return ListTile(
                key: Key('tool-${t.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text([t.name, if (t.code != null) t.code!].join(' · ')),
                subtitle: open == null
                    ? null
                    : Text([
                        open.issuedTo,
                        if (open.projectId != null && sites[open.projectId] != null) sites[open.projectId]!,
                        if (open.dueBack != null) trf('due {date}', {'date': fmtDate(open.dueBack!, short: true)}),
                      ].join(' · ')),
                trailing: StatusPill(toolStateLabels[s]!, tone: _toolTone(s)),
                onTap: () => _toolActions(context, t, s, open),
              );
            }),
          if (recover.isNotEmpty) ...[
            const SectionHeader('To recover'),
            for (final i in recover)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(i.issuedTo),
                subtitle: Text([
                  d.tools.where((t) => t.id == i.toolId).firstOrNull?.name ?? '',
                  tr(returnConditionLabels[i.returnCondition] ?? ''),
                ].where((x) => x.isNotEmpty).join(' · ')),
                trailing: Text(rupees(i.recoverAmount!), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ]),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'add-tool',
          onPressed: _addTool,
          icon: const Icon(Icons.add),
          label: Text(tr('Add tool')),
        ),
      ),
    ]);
  }

  Future<void> _toolActions(BuildContext context, Tool t, ToolState s, ToolIssue? open) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (open == null && s != ToolState.lost && s != ToolState.retired)
            ListTile(
                key: const Key('tool-issue'),
                leading: const Icon(Icons.outbox),
                title: Text(tr('Hand over')),
                onTap: () => Navigator.pop(ctx, 'issue')),
          if (open != null)
            ListTile(
                key: const Key('tool-return'),
                leading: const Icon(Icons.move_to_inbox_outlined),
                title: Text(tr('Take back')),
                onTap: () => Navigator.pop(ctx, 'return')),
          if (s == ToolState.repair)
            ListTile(
                leading: const Icon(Icons.build_circle_outlined),
                title: Text(tr('Repaired, back in use')),
                onTap: () => Navigator.pop(ctx, 'repaired')),
          ListTile(leading: const Icon(Icons.history), title: Text(tr('History')), onTap: () => Navigator.pop(ctx, 'history')),
          ListTile(
              leading: const Icon(Icons.edit_outlined), title: Text(tr('Edit')), onTap: () => Navigator.pop(ctx, 'edit')),
          if (s != ToolState.retired && open == null)
            ListTile(
                leading: const Icon(Icons.block), title: Text(tr('Retire')), onTap: () => Navigator.pop(ctx, 'retire')),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    final dao = ref.read(appDatabaseProvider).warehouseDao;
    try {
      switch (choice) {
        case 'issue':
          await showIssueTool(context, ref, tool: t, sites: widget.data.sites, userId: widget.userId);
        case 'return':
          await showReturnTool(context, ref, issue: open!, tool: t);
        case 'repaired' || 'retire':
          await dao.updateTool(t.id,
              name: t.name,
              code: t.code,
              category: t.category,
              value: t.value,
              storeId: t.storeId,
              notes: t.notes,
              condition: choice == 'retire' ? 'retired' : 'in_use');
        case 'edit':
          await showToolForm(context, ref, data: widget.data, companyId: widget.companyId, userId: widget.userId, tool: t);
        case 'history':
          await _showHistory(context, t);
      }
    } on ArgumentError catch (e) {
      if (context.mounted) showSnack(context, tr('${e.message}'), error: true);
    }
    refreshWarehouse(ref, widget.companyId);
  }

  Future<void> _showHistory(BuildContext context, Tool t) async {
    final issues = await ref.read(appDatabaseProvider).warehouseDao.issuesForTool(t.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.name),
        content: SizedBox(
          width: double.maxFinite,
          child: issues.isEmpty
              ? Text(tr('Not handed over yet.'))
              : ListView(shrinkWrap: true, children: [
                  for (final i in issues)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(i.issuedTo),
                      subtitle: Text([
                        fmtDate(i.issuedOn, short: true),
                        if (i.returnedOn != null) '→ ${fmtDate(i.returnedOn!, short: true)}',
                        if (i.returnCondition != null) tr(returnConditionLabels[i.returnCondition]!),
                        if (i.recoverAmount != null) rupees(i.recoverAmount!),
                      ].join(' · ')),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close')))],
      ),
    );
  }
}

Future<Tool?> showToolForm(BuildContext context, WidgetRef ref,
    {required WarehouseData data, required String companyId, required String userId, Tool? tool}) async {
  final name = TextEditingController(text: tool?.name ?? '');
  final code = TextEditingController(text: tool?.code ?? '');
  final category = TextEditingController(text: tool?.category ?? '');
  final value = TextEditingController(text: tool?.value == null ? '' : fmtQty(tool!.value!));
  String? storeId = tool?.storeId ?? data.stores.firstOrNull?.id;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tool == null ? tr('Add tool') : tr('Edit tool')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('tool-name'),
                controller: name,
                autofocus: tool == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Tool (e.g. Drill machine)'))),
            TextField(
                controller: code,
                decoration: InputDecoration(
                    labelText: tr('Tag number'), helperText: tool == null ? tr('Leave empty for the next number') : null)),
            TextField(controller: category, decoration: InputDecoration(labelText: tr('Kind (e.g. Power tool)'))),
            TextField(
                key: const Key('tool-value'),
                controller: value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Worth (₹)'))),
            if (data.stores.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: storeId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Kept at')),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(tr('No store'))),
                  for (final s in data.stores) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => storeId = v),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('tool-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  final dao = ref.read(appDatabaseProvider).warehouseDao;
  if (tool == null) {
    return dao.addTool(
        companyId: companyId,
        name: name.text,
        code: code.text,
        category: category.text,
        value: _num(value.text),
        storeId: storeId,
        by: userId);
  }
  await dao.updateTool(tool.id,
      name: name.text,
      code: code.text,
      category: category.text,
      value: _num(value.text),
      storeId: storeId,
      notes: tool.notes);
  return dao.toolById(tool.id);
}

Future<ToolIssue?> showIssueTool(BuildContext context, WidgetRef ref,
    {required Tool tool, required List<Project> sites, required String userId, String? projectId}) async {
  final person = TextEditingController();
  String? site = projectId;
  DateTime? due = DateTime.now().add(const Duration(days: 7));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(trf('Hand over {tool}', {'tool': tool.name})),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('issue-person'),
                controller: person,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: tr('Given to'))),
            if (sites.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: site,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('For site')),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(tr('Not for a site'))),
                  for (final p in sites)
                    DropdownMenuItem<String?>(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => site = v),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Due back')),
              subtitle: Text(due == null ? tr('No date') : fmtDate(due!)),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: due ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                setState(() => due = d);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('issue-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Hand over'))),
        ],
      ),
    ),
  );
  if (ok != true || person.text.trim().isEmpty) return null;
  return ref
      .read(appDatabaseProvider)
      .warehouseDao
      .issueTool(toolId: tool.id, issuedTo: person.text, by: userId, projectId: site, dueBack: due);
}

Future<ToolIssue?> showReturnTool(BuildContext context, WidgetRef ref,
    {required ToolIssue issue, required Tool tool}) async {
  var condition = 'ok';
  final recover = TextEditingController();
  final note = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(trf('Take back {tool}', {'tool': tool.name})),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trf('From {person}', {'person': issue.issuedTo})),
            const SizedBox(height: 8),
            Wrap(spacing: 6, children: [
              for (final c in returnConditions)
                ChoiceChip(
                  key: Key('return-$c'),
                  label: Text(tr(returnConditionLabels[c]!)),
                  selected: condition == c,
                  onSelected: (_) => setState(() {
                    condition = c;
                    if (c == 'lost' && recover.text.isEmpty && tool.value != null) recover.text = fmtQty(tool.value!);
                  }),
                ),
            ]),
            if (condition != 'ok')
              TextField(
                key: const Key('return-recover'),
                controller: recover,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('To recover from them (₹)')),
              ),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Note'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('return-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  return ref
      .read(appDatabaseProvider)
      .warehouseDao
      .returnTool(issue.id, condition: condition, recoverAmount: _num(recover.text), note: note.text);
}
