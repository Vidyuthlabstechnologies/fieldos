/// Suppliers' invoices for a site, each checked against its purchase order
/// and what actually came (the GRNs): the three-way match accounts does
/// before paying. Rules in money/billing_reconcile.dart.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_reconcile.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart' show mySiteAccessProvider;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class SupplierInvoiceBook {
  const SupplierInvoiceBook({required this.checks, required this.suppliers, required this.orders});
  final List<InvoiceCheck> checks;
  final Map<String, Supplier> suppliers;
  final List<PurchaseOrder> orders;
}

final supplierInvoicesProvider = FutureProvider.autoDispose.family<SupplierInvoiceBook, Project>((ref, project) async {
  final db = ref.watch(appDatabaseProvider);
  final invoices = await db.billingRecordsDao.supplierInvoicesFor(project.id);
  final orders = await db.purchaseDao.ordersFor(project.id);
  final receipts = await db.materialDao.forProject(project.id);
  final suppliers = {for (final s in await db.supplierDao.forCompany(project.companyId)) s.id: s};
  final byId = {for (final o in orders) o.id: o};
  return SupplierInvoiceBook(
    checks: [
      for (final i in invoices)
        checkSupplierInvoice(i, order: i.poId == null ? null : byId[i.poId], receipts: receipts, others: invoices),
    ],
    suppliers: suppliers,
    orders: orders,
  );
});

class SupplierInvoicesScreen extends ConsumerStatefulWidget {
  const SupplierInvoicesScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<SupplierInvoicesScreen> createState() => _SupplierInvoicesScreenState();
}

class _SupplierInvoicesScreenState extends ConsumerState<SupplierInvoicesScreen> {
  bool _busy = false;

  Future<void> _add(SupplierInvoiceBook book) async {
    if (book.suppliers.isEmpty) {
      showSnack(context, tr('Add the supplier first, under Procure > Suppliers.'), error: true);
      return;
    }
    String supplierId = book.suppliers.keys.first;
    String? poId;
    final number = TextEditingController();
    final amount = TextEditingController();
    final gst = TextEditingController();
    final qty = TextEditingController();
    var date = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final orders = book.orders.where((o) => o.supplierId == supplierId && o.status != 'cancelled').toList();
        return AlertDialog(
          title: Text(tr('Supplier invoice')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: supplierId,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Supplier')),
                items: [
                  for (final s in book.suppliers.values)
                    DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setLocal(() {
                  supplierId = v ?? supplierId;
                  poId = null;
                }),
              ),
              DropdownButtonFormField<String>(
                initialValue: poId ?? '',
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Purchase order')),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('No purchase order'))),
                  for (final o in orders)
                    DropdownMenuItem(
                        value: o.id,
                        child: Text('${o.poNumber ?? tr('PO')} · ${rupees(o.totalAmount ?? 0)}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setLocal(() => poId = (v == null || v.isEmpty) ? null : v),
              ),
              TextField(controller: number, decoration: InputDecoration(labelText: tr('Invoice number'))),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: tr('Invoice total with GST (₹)')),
              ),
              TextField(
                controller: gst,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: tr('GST in it (₹, optional)')),
              ),
              TextField(
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: tr('Quantity invoiced (optional)')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(fmtDate(date)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) setLocal(() => date = d);
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    final a = double.tryParse(amount.text.trim());
    final n = number.text.trim();
    if (a == null || n.isEmpty) {
      showSnack(context, tr('Give the invoice number and its total.'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(appDatabaseProvider).billingRecordsDao.recordSupplierInvoice(SupplierInvoicesCompanion.insert(
            id: const Uuid().v4(),
            projectId: widget.project.id,
            supplierId: supplierId,
            poId: Value(poId),
            invoiceNumber: n.length > 40 ? n.substring(0, 40) : n,
            invoiceDate: DateTime(date.year, date.month, date.day),
            amount: a,
            gstAmount: Value(double.tryParse(gst.text.trim()) ?? 0),
            qty: Value(double.tryParse(qty.text.trim())),
            recordedBy: ref.read(sessionProvider).user?.id ?? '',
          ));
      ref.invalidate(supplierInvoicesProvider(widget.project));
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(SupplierInvoice i) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cancel this invoice?')),
        content: TextField(controller: reason, decoration: InputDecoration(labelText: tr('Why'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep it'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cancel invoice'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appDatabaseProvider).billingRecordsDao.voidSupplierInvoice(i.id, reason.text);
      ref.invalidate(supplierInvoicesProvider(widget.project));
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(supplierInvoicesProvider(widget.project));
    final manager = ref.watch(mySiteAccessProvider(widget.project.id)).value?.managesSite ?? false;
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Supplier invoices')} · ${widget.project.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || book.value == null ? null : () => _add(book.value!),
        icon: const Icon(Icons.add),
        label: Text(tr('Add invoice')),
      ),
      body: book.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(supplierInvoicesProvider(widget.project))),
        data: (b) {
          if (b.checks.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: tr('No supplier invoices yet'),
              message: tr('Enter each invoice as it comes. It is checked against the purchase order and what was received.'),
            );
          }
          final live = b.checks.where((c) => !c.invoice.voided).toList();
          final problems = live.where((c) => !c.matched).length;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                  problems == 0
                      ? trf('All {n} invoices match their orders and deliveries.', {'n': live.length})
                      : trf('{m} of {n} invoices need checking before payment.', {'m': problems, 'n': live.length}),
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final c in b.checks)
              Card(
                child: ListTile(
                  title: Text('${b.suppliers[c.invoice.supplierId]?.name ?? tr('Supplier')} · ${c.invoice.invoiceNumber}'),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text([
                      rupees(c.invoice.amount),
                      fmtDate(c.invoice.invoiceDate, short: true),
                      if (c.ordered != null) trf('PO {amount}', {'amount': rupees(c.ordered!)}),
                      trf('received {amount}', {'amount': rupees(c.received)}),
                    ].join(' · ')),
                    if (c.invoice.voided)
                      Text(trf('Cancelled: {why}', {'why': c.invoice.voidReason ?? ''}))
                    else if (c.flags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(spacing: 6, runSpacing: 4, children: [
                          for (final f in c.flags)
                            StatusPill(
                                f == InvoiceFlag.overReceived
                                    ? trf('{amount} more than received', {'amount': rupees(c.overBy)})
                                    : invoiceFlagLabel(f),
                                tone: f == InvoiceFlag.noPo || f == InvoiceFlag.nothingReceived ? PillTone.warn : PillTone.danger),
                        ]),
                      ),
                  ]),
                  trailing: c.invoice.voided
                      ? null
                      : c.matched
                          ? StatusPill(tr('Matched'), tone: PillTone.ok)
                          : null,
                  onLongPress: manager && !c.invoice.voided ? () => _cancel(c.invoice) : null,
                ),
              ),
          ]);
        },
      ),
    );
  }
}
