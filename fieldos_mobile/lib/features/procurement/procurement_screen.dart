/// Procurement flow: Suppliers -> RFQ (purchase requests) -> PO -> GRN.
///
/// Unlike Onsite (which treats these as static records), saving a GRN here
/// feeds the cost engine's material actuals, so budget-vs-actuals updates the
/// moment goods hit the site.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/po_share.dart';
import 'package:fieldos_mobile/features/procurement/purchase_screens.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/features/procurement/rate_hint.dart';
import 'package:fieldos_mobile/features/procurement/supplier_statement_screen.dart';
import 'package:fieldos_mobile/features/procurement/stock_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';

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
  late final _engine = ref.read(cloudSyncEngineProvider);
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
    final engine = _engine;
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
    // ref can't be used in dispose, so the engine read in initState is used.
    if (_vendorsLiveCallback != null && identical(_engine.onVendorsChanged, _vendorsLiveCallback)) {
      _engine.onVendorsChanged = null;
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
            tabs: [
              Tab(text: tr('Suppliers')),
              Tab(text: tr('RFQ')),
              Tab(text: tr('PO')),
              Tab(text: tr('GRN')),
              Tab(text: tr('Stock')),
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
                  companyId: widget.companyId,
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
          IconButton(icon: const Icon(Icons.add), tooltip: tr('Add'), onPressed: onAdd),
        ],
      ),
    );

// --- Suppliers ------------------------------------------------------------

/// Every site's orders and deliveries, per supplier.
final supplierLedgerProvider = FutureProvider.autoDispose.family<Map<String, SupplierLedger>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final orders = <PurchaseOrder>[];
  final receipts = <MaterialReceipt>[];
  final expenses = <SiteExpense>[];
  for (final p in await db.projectDao.forCompany(companyId)) {
    orders.addAll(await db.purchaseDao.ordersFor(p.id));
    receipts.addAll(await db.materialDao.forProject(p.id));
    expenses.addAll(await db.expenseDao.forProject(p.id));
  }
  return supplierLedgers(orders, receipts, DateTime.now(),
      suppliers: await db.supplierDao.forCompany(companyId), expenses: expenses);
});

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab({required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider(companyId));
    final ledgers = ref.watch(supplierLedgerProvider(companyId)).valueOrNull ?? const <String, SupplierLedger>{};
    return Column(
      children: [
        _sectionHeader(context, tr('Suppliers'), () => _add(context, ref)),
        Expanded(
          child: suppliers.when(
            data: (rows) => rows.isEmpty
                ? MitraEmpty(tr('No suppliers yet.'))
                : ListView(
                    children: [
                      for (final s in rows)
                        ListTile(
                          title: Text(s.name),
                          subtitle: Text([
                            ...[s.contactPhone, s.email].where((e) => e != null && e.isNotEmpty).cast<String>(),
                            if (ledgers[s.id] case final l?) ...[
                              if (l.ordered > 0) trf('ordered {amount}', {'amount': rupees(l.ordered)}),
                              if (l.received > 0) trf('delivered {amount}', {'amount': rupees(l.received)}),
                              if (l.toCome > 0) trf('{amount} still to come', {'amount': rupees(l.toCome)}),
                              if (l.balance > 0.005) trf('you owe {amount}', {'amount': rupees(l.balance)}),
                              if (l.balance < -0.005) trf('advance {amount}', {'amount': rupees(-l.balance)}),
                            ],
                          ].join(' · ')),
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SupplierStatementScreen(companyId: companyId, supplierId: s.id),
                            ));
                            ref.invalidate(supplierLedgerProvider(companyId));
                          },
                          trailing: switch (ledgers[s.id]) {
                            final l? when l.lateOrders > 0 =>
                              StatusPill(trf('{n} late', {'n': l.lateOrders}), tone: PillTone.danger),
                            final l? when l.openOrders > 0 => StatusPill(trf('{n} open', {'n': l.openOrders})),
                            _ => null,
                          },
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
        title: Text(tr('Add supplier')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
            TextField(controller: phone, decoration: InputDecoration(labelText: tr('Phone'))),
            TextField(controller: email, decoration: InputDecoration(labelText: tr('Email'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
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
        _sectionHeader(context, tr('Purchase requests (RFQ)'), () => _add(context, ref)),
        Expanded(
          child: requests.when(
            data: (rows) => rows.isEmpty
                ? MitraEmpty(tr('No RFQs yet.'))
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
                                  child: Text(tr('Make PO')),
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
        title: Text(tr('Raise RFQ')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Material'))),
            TextField(controller: qty, decoration: InputDecoration(labelText: tr('Qty')), keyboardType: TextInputType.number),
            TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit'))),
            TextField(controller: est, decoration: InputDecoration(labelText: tr('Est. amount')), keyboardType: TextInputType.number),
            RateHint(companyId: companyId, material: name, unit: unit, qty: qty, amount: est),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
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
        title: Text(tr('Create PO')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
              controller: amount, decoration: InputDecoration(labelText: tr('PO amount')), keyboardType: TextInputType.number),
          RateHint(
            companyId: companyId,
            material: null,
            unit: null,
            qty: null,
            amount: amount,
            fixedMaterial: r.materialName,
            fixedUnit: r.unit,
            fixedQty: r.quantity,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Create'))),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Add a supplier first.'))));
      return null;
    }
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Pick supplier')),
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
    final requests = ref.watch(requestsProvider(projectId)).valueOrNull ?? const <PurchaseRequest>[];
    final receipts = ref.watch(receiptsProvider(projectId)).valueOrNull ?? const <MaterialReceipt>[];
    final now = DateTime.now();
    return Column(
      children: [
        Expanded(
          child: orders.when(
            data: (rows) => rows.isEmpty
                ? MitraEmpty(tr('No purchase orders yet.'))
                : ListView(
                    children: [
                      for (final o in rows)
                        ListTile(
                          title: Text(_poTitle(o, requests.where((r) => r.id == o.requestId).firstOrNull)),
                          subtitle: Text([
                            _supName(suppliers, o.supplierId),
                            _poStage(o, poProgress(o, requests.where((r) => r.id == o.requestId).firstOrNull, receipts)),
                            if (poIsLate(o, now)) trf('late since {date}', {'date': fmtDate(o.deliveryDate!, short: true)}),
                          ].join(' · ')),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              tooltip: tr('Send to supplier'),
                              icon: const Icon(Icons.share_outlined),
                              onPressed: () => _sharePo(ref, o, suppliers),
                            ),
                            if (o.status == 'issued')
                              FilledButton(
                                child: Text(tr('Receive')),
                                onPressed: () => _receive(context, ref, o, requests.where((r) => r.id == o.requestId).firstOrNull,
                                    poProgress(o, requests.where((r) => r.id == o.requestId).firstOrNull, receipts)),
                              ),
                          ]),
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

  Future<void> _sharePo(WidgetRef ref, PurchaseOrder o, AsyncValue<List<Supplier>> suppliers) async {
    final requests = ref.read(requestsProvider(projectId)).valueOrNull ?? const <PurchaseRequest>[];
    final projects = ref.read(projectsProvider(companyId)).valueOrNull ?? const <Project>[];
    final text = poShareText(
      order: o,
      companyName: ref.read(sessionProvider).activeCompany?.name ?? '',
      projectName: projects.where((p) => p.id == projectId).firstOrNull?.name,
      supplierName: (suppliers.valueOrNull ?? const <Supplier>[]).where((s) => s.id == o.supplierId).firstOrNull?.name,
      request: requests.where((r) => r.id == o.requestId).firstOrNull,
    );
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _receive(BuildContext context, WidgetRef ref, PurchaseOrder o, PurchaseRequest? request, PoProgress progress) async {
    final pending = progress.pending;
    final material = TextEditingController(text: request?.materialName ?? '');
    final qty = TextEditingController(text: pending == null || pending <= 0 ? '' : fmtQty(pending));
    final unit = TextEditingController(text: request?.unit ?? '');
    final leftToPay = o.totalAmount == null ? null : o.totalAmount! - progress.amountReceived;
    final amount = TextEditingController(text: leftToPay == null || leftToPay <= 0 ? '' : fmtQty(leftToPay));
    final photoPath = ValueNotifier<String?>(null);
    var closeOrder = true;
    void updateClose() {
      final q = double.tryParse(qty.text.trim());
      closeOrder = pending == null || q == null || q >= pending - 0.0001;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setGrnState) => AlertDialog(
          title: Text(tr('Goods receipt (GRN)')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (progress.received > 0 && progress.ordered != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(trf('{got} of {ordered} {unit} already received', {
                    'got': fmtQty(progress.received),
                    'ordered': fmtQty(progress.ordered!),
                    'unit': progress.unit,
                  }).replaceAll('  ', ' ')),
                ),
              TextField(controller: material, decoration: InputDecoration(labelText: tr('Material (e.g. Cement)'))),
              TextField(
                controller: qty,
                decoration: InputDecoration(labelText: tr('Qty received')),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setGrnState(updateClose),
              ),
              TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit'))),
              TextField(controller: amount, decoration: InputDecoration(labelText: tr('Invoice amount')), keyboardType: TextInputType.number),
              RateHint(companyId: companyId, material: material, unit: unit, qty: qty, amount: amount),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera),
                label: Text(photoPath.value == null ? tr('Attach delivery photo') : tr('Photo attached')),
                onPressed: () async {
                  final path = await captureCameraFirst(ctx, prefix: 'grn');
                  if (path != null) {
                    photoPath.value = path;
                    setGrnState(() {});
                  }
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: closeOrder,
                onChanged: (v) => setGrnState(() => closeOrder = v ?? true),
                title: Text(tr('Everything on this order has come')),
                subtitle: closeOrder ? null : Text(tr('The order stays open for the rest.')),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Receive'))),
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
          materialName: material.text.trim().isEmpty ? tr('Goods from PO') : material.text.trim(),
          quantity: double.tryParse(qty.text.trim()) ?? 1,
          unit: Value(unit.text.trim()),
          amount: double.tryParse(amount.text.trim()) ?? 0,
          receivedBy: userId,
          receivedOn: DateTime.now(),
          notes: Value(notes),
        ));
    if (closeOrder) await db.purchaseDao.setOrderStatus(o.id, 'delivered');
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
  return tr('Supplier not on this phone');
}

String _poTitle(PurchaseOrder o, PurchaseRequest? request) {
  final what = request == null
      ? tr('Purchase order')
      : [request.materialName.trim(), fmtQty(request.quantity), request.unit.trim()].where((e) => e.isNotEmpty).join(' ');
  return o.totalAmount == null ? what : '$what · ${rupees(o.totalAmount!)}';
}

/// "Sent to supplier", or how much of it has come when it came in parts.
String _poStage(PurchaseOrder o, PoProgress p) {
  if (p.partlyReceived && !closedOrderStatuses.contains(o.status)) {
    return trf('{got} of {ordered} received, {left} to come',
        {'got': fmtQty(p.received), 'ordered': fmtQty(p.ordered!), 'left': fmtQty(p.pending!)});
  }
  return _statusLabel(o.status);
}

/// Request and order stages in plain words.
String _statusLabel(String status) => switch (status) {
      'pending' => tr('Waiting for a PO'),
      'approved' => tr('Approved'),
      'rejected' => tr('Rejected'),
      'ordered' => tr('Ordered'),
      'issued' => tr('Sent to supplier'),
      'acknowledged' => tr('Supplier confirmed'),
      'delivered' => tr('Delivered'),
      'cancelled' => tr('Cancelled'),
      _ => status.isEmpty ? status : '${status[0].toUpperCase()}${status.substring(1).replaceAll('_', ' ')}',
    };

// --- GRN ------------------------------------------------------------------

class _GrnTab extends ConsumerWidget {
  const _GrnTab({required this.projectId, required this.companyId, required this.userId});
  final String projectId;
  final String companyId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receipts = ref.watch(receiptsProvider(projectId));
    return receipts.when(
      data: (rows) => rows.isEmpty
          ? MitraEmpty(tr('No goods receipts yet.'))
          : ListView(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: TextButton.icon(
                      icon: const Icon(Icons.trending_up),
                      label: Text(tr('Material rates')),
                      onPressed: () => openMaterialRates(context, projectId, companyId),
                    ),
                  ),
                ),
                for (final m in rows)
                  ListTile(
                    leading: const Icon(Icons.inventory),
                    title: Text(m.materialName),
                    subtitle: Text([
                      '${fmtQty(m.quantity)} ${m.unit ?? ''}'.trim(),
                      rupees(m.amount),
                      trf('received {date}', {'date': fmtDate(m.receivedOn, short: true)}),
                    ].join(' · ')),
                  ),
              ],
            ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => ErrorState(error: e, stack: st),
    );
  }
}
