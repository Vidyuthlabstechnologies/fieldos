/// Procurement flow: Suppliers -> RFQ (purchase requests) -> PO -> GRN.
///
/// Unlike Onsite (which treats these as static records), saving a GRN here
/// feeds the cost engine's material actuals, so budget-vs-actuals updates the
/// moment goods hit the site.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/stock_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';

class ProcurementView extends ConsumerStatefulWidget {
  const ProcurementView({
    super.key,
    required this.projectId,
    required this.companyId,
    required this.userId,
  });
  final String projectId;
  final String companyId;
  final String userId;

  @override
  ConsumerState<ProcurementView> createState() => _ProcurementViewState();
}

class _ProcurementViewState extends ConsumerState<ProcurementView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  void Function()? _vendorsLiveCallback;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _maybeSubscribeToVendorUpdates();
  }

  /// Same pattern as ProjectDetailScreen's task subscription: if cloud sync
  /// is on, a colleague adding a vendor refreshes the Suppliers tab live.
  Future<void> _maybeSubscribeToVendorUpdates() async {
    final service = ref.read(cloudSyncServiceProvider);
    if (!service.isSignedIn) return;
    final engine = ref.read(cloudSyncEngineProvider);
    _vendorsLiveCallback = () {
      if (mounted) ref.invalidate(suppliersProvider(widget.companyId));
    };
    engine.onVendorsChanged = _vendorsLiveCallback;
    try {
      await engine.subscribeToCompanyVendors(widget.companyId);
    } catch (_) {
      // Periodic/manual sync still covers this data; a failed live channel
      // isn't actionable from here.
    }
  }

  @override
  void dispose() {
    final engine = ref.read(cloudSyncEngineProvider);
    if (identical(engine.onVendorsChanged, _vendorsLiveCallback)) {
      engine.onVendorsChanged = null;
    }
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'Suppliers'),
              Tab(text: 'RFQ'),
              Tab(text: 'PO'),
              Tab(text: 'GRN'),
              Tab(text: 'Stock'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _SuppliersTab(companyId: widget.companyId),
                _RfqTab(
                  projectId: widget.projectId,
                  companyId: widget.companyId,
                  userId: widget.userId,
                ),
                _PoTab(
                  projectId: widget.projectId,
                  companyId: widget.companyId,
                  userId: widget.userId,
                ),
                _GrnTab(
                  projectId: widget.projectId,
                  userId: widget.userId,
                ),
                StockView(projectId: widget.projectId, userId: widget.userId),
              ],
            ),
          ),
        ],
      );
}

Widget _sectionHeader(BuildContext context, String title, VoidCallback onAdd) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: onAdd),
        ],
      ),
    );

// --- Suppliers ------------------------------------------------------------

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider(companyId));
    return Column(
      children: [
        _sectionHeader(context, 'Suppliers', () => _add(context, ref)),
        Expanded(
          child: suppliers.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No suppliers yet.'))
                : ListView(
                    children: [
                      for (final s in rows)
                        ListTile(
                          title: Text(s.name),
                          subtitle: Text([s.contactPhone, s.email]
                              .where((e) => e != null && e.isNotEmpty)
                              .join(' · ')),
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add supplier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await ref.read(appDatabaseProvider).supplierDao.create(SuppliersCompanion.insert(
          id: const Uuid().v4(),
          companyId: companyId,
          name: name.text.trim(),
          contactPhone: Value(phone.text.trim()),
          email: Value(email.text.trim()),
        ));
    ref.invalidate(suppliersProvider(companyId));
  }
}

// --- RFQ ------------------------------------------------------------------

class _RfqTab extends ConsumerWidget {
  const _RfqTab(
      {required this.projectId, required this.companyId, required this.userId});
  final String projectId;
  final String companyId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(requestsProvider(projectId));
    final suppliers = ref.watch(suppliersProvider(companyId));
    return Column(
      children: [
        _sectionHeader(context, 'Purchase requests (RFQ)', () => _add(context, ref)),
        Expanded(
          child: requests.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No RFQs yet.'))
                : ListView(
                    children: [
                      for (final r in rows)
                        ListTile(
                          title: Text(r.materialName),
                          subtitle: Text([
                            '${fmtQty(r.quantity)} ${r.unit}',
                            if (r.estimatedAmount != null) 'about ${rupees(r.estimatedAmount!)}',
                            _statusLabel(r.status),
                          ].join(' · ')),
                          trailing: r.status == 'pending'
                              ? FilledButton(
                                  child: const Text('Make PO'),
                                  onPressed: () => _makePo(context, ref, r, suppliers),
                                )
                              : null,
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final qty = TextEditingController();
    final unit = TextEditingController();
    final est = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise RFQ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Material')),
            TextField(controller: qty, decoration: const InputDecoration(labelText: 'Qty'), keyboardType: TextInputType.number),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit')),
            TextField(controller: est, decoration: const InputDecoration(labelText: 'Est. amount'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await ref.read(appDatabaseProvider).purchaseDao.createRequest(PurchaseRequestsCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          raisedBy: userId,
          materialName: name.text.trim(),
          quantity: Value(double.tryParse(qty.text) ?? 1),
          unit: Value(unit.text.trim()),
          estimatedAmount: Value(double.tryParse(est.text)),
        ));
    ref.invalidate(requestsProvider(projectId));
  }

  Future<void> _makePo(BuildContext context, WidgetRef ref, PurchaseRequest r,
      AsyncValue<List<Supplier>> suppliers) async {
    final supplierId = await _pickSupplier(context, suppliers);
    if (supplierId == null || !context.mounted) return;
    final amount = TextEditingController(text: (r.estimatedAmount ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create PO'),
        content: TextField(
            controller: amount, decoration: const InputDecoration(labelText: 'PO amount'), keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    final db = ref.read(appDatabaseProvider);
    await db.purchaseDao.createOrder(PurchaseOrdersCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          supplierId: supplierId,
          requestId: Value(r.id),
          raisedBy: userId,
          totalAmount: Value(double.tryParse(amount.text)),
        ));
    await db.purchaseDao.setRequestStatus(r.id, 'ordered');
    ref.invalidate(requestsProvider(projectId));
    ref.invalidate(ordersProvider(projectId));
  }

  Future<String?> _pickSupplier(BuildContext context, AsyncValue<List<Supplier>> suppliers) async {
    final rows = suppliers.valueOrNull ?? [];
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a supplier first.')));
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pick supplier'),
        children: [
          for (final s in rows)
            SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(s.id), child: Text(s.name)),
        ],
      ),
    );
  }
}

// --- PO -------------------------------------------------------------------

class _PoTab extends ConsumerWidget {
  const _PoTab({required this.projectId, required this.companyId, required this.userId});
  final String projectId;
  final String companyId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider(projectId));
    final suppliers = ref.watch(suppliersProvider(companyId));
    return Column(
      children: [
        Expanded(
          child: orders.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No purchase orders yet.'))
                : ListView(
                    children: [
                      for (final o in rows)
                        ListTile(
                          title: Text(o.totalAmount == null ? 'Purchase order' : 'Purchase order · ${rupees(o.totalAmount!)}'),
                          subtitle: Text('${_supName(suppliers, o.supplierId)} · ${_statusLabel(o.status)}'),
                          trailing: o.status == 'issued'
                              ? FilledButton(
                                  child: const Text('Receive'),
                                  onPressed: () => _receive(context, ref, o, suppliers),
                                )
                              : null,
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _receive(BuildContext context, WidgetRef ref, PurchaseOrder o,
      AsyncValue<List<Supplier>> suppliers) async {
    final qty = TextEditingController();
    final unit = TextEditingController();
    final amount = TextEditingController(text: (o.totalAmount ?? '').toString());
    final photoPath = ValueNotifier<String?>(null);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setGrnState) => AlertDialog(
          title: const Text('Goods receipt (GRN)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qty, decoration: const InputDecoration(labelText: 'Qty received'), keyboardType: TextInputType.number),
              TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit')),
              TextField(controller: amount, decoration: const InputDecoration(labelText: 'Invoice amount'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: Text(photoPath.value == null ? 'Attach delivery photo' : 'Photo attached'),
                onPressed: () async {
                  final path = await captureCameraFirst(ctx, prefix: 'grn');
                  if (path != null) {
                    photoPath.value = path;
                    setGrnState(() {});
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Receive')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final db = ref.read(appDatabaseProvider);
    
    // Store photo path in notes field for now (material_receipts table doesn't have a dedicated photo_path column)
    final notes = photoPath.value != null ? 'Photo: ${photoPath.value}' : null;
    
    await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          poId: Value(o.id),
          supplierId: Value(o.supplierId),
          costHeadId: const Value(null),
          materialName: 'Goods from PO',
          quantity: double.tryParse(qty.text) ?? 1,
          unit: Value(unit.text.trim()),
          amount: double.tryParse(amount.text) ?? 0,
          receivedBy: userId,
          receivedOn: DateTime.now(),
          notes: Value(notes),
        ));
    await db.purchaseDao.setOrderStatus(o.id, 'delivered');
    ref.invalidate(ordersProvider(projectId));
    ref.invalidate(receiptsProvider(projectId));
    ref.invalidate(siteStockProvider(projectId));
    ref.invalidate(costSummaryProvider(projectId));
  }
}

String _supName(AsyncValue<List<Supplier>> suppliers, String id) {
  for (final s in suppliers.valueOrNull ?? const <Supplier>[]) {
    if (s.id == id) return s.name;
  }
  return 'Supplier not on this phone';
}

/// Request and order stages in plain words.
String _statusLabel(String status) => switch (status) {
      'pending' => 'Waiting for a PO',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'ordered' => 'Ordered',
      'issued' => 'Sent to supplier',
      'acknowledged' => 'Supplier confirmed',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      _ => status.isEmpty ? status : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}',
    };

// --- GRN ------------------------------------------------------------------

class _GrnTab extends ConsumerWidget {
  const _GrnTab({required this.projectId, required this.userId});
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider(projectId));
    return receipts.when(
      data: (rows) => rows.isEmpty
          ? const Center(child: Text('No goods receipts yet.'))
          : ListView(
              children: [
                for (final m in rows)
                  ListTile(
                    leading: const Icon(Icons.inventory),
                    title: Text(m.materialName),
                    subtitle: Text([
                      '${fmtQty(m.quantity)} ${m.unit ?? ''}'.trim(),
                      rupees(m.amount),
                      'received ${fmtDate(m.receivedOn, short: true)}',
                    ].join(' · ')),
                  ),
              ],
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorState(error: e, stack: st),
    );
  }
}
