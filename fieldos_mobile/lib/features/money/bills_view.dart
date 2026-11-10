/// Bills to the client, for owners and project managers: the project's
/// profit and loss at the top, the list of RA bills and tax invoices, and
/// the screen that makes a new one.
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/billing_reconcile.dart';
import 'package:fieldos_mobile/features/money/measurement_book_screen.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

final billsProvider = FutureProvider.autoDispose.family<List<ClientBill>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).billDao.forProject(projectId));

final billAllocationsProvider = FutureProvider.autoDispose.family<List<BillAllocation>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).billingRecordsDao.allocationsFor(projectId));

String _profileKey(String companyId) => 'billing_profile:$companyId';

final billingProfileProvider = FutureProvider.autoDispose.family<BillingProfile, String>((ref, companyId) async {
  final raw = await ref.watch(appDatabaseProvider).settingsDao.get(_profileKey(companyId));
  if (raw == null || raw.isEmpty) return const BillingProfile();
  final j = jsonDecode(raw) as Map<String, dynamic>;
  return BillingProfile(
    gstin: j['gstin'] as String? ?? '',
    address: j['address'] as String? ?? '',
    upiId: j['upi'] as String? ?? '',
  );
});

Future<void> saveBillingProfile(AppDatabase db, String companyId, BillingProfile p) => db.settingsDao.set(
      _profileKey(companyId),
      jsonEncode({'gstin': p.gstin.trim().toUpperCase(), 'address': p.address.trim(), 'upi': p.upiId.trim()}),
    );

/// Previous quantities for [bill]: what earlier RA bills of the project
/// (by date, then creation) billed for each item.
Map<String, double> previousFor(ClientBill bill, List<ClientBill> all) {
  final earlier = all.where((b) =>
      b.kind == 'ra' &&
      b.id != bill.id &&
      (b.billDate.isBefore(bill.billDate) || (b.billDate == bill.billDate && b.createdAt.isBefore(bill.createdAt))));
  return previousQuantities(earlier.map((b) => decodeLines(b.linesJson)));
}

ProjectPnl pnlFrom({required List<ClientBill> bills, required double received, required double spent}) => ProjectPnl(
      billed: bills.fold<double>(0, (s, b) => s + b.gross),
      received: received,
      spent: spent,
      owed: bills.where((b) => b.status != 'paid').fold<double>(0, (s, b) => s + b.netPayable),
    );

class BillsView extends ConsumerWidget {
  const BillsView({super.key, required this.project, required this.userId});
  final Project project;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(billsProvider(project.id));
    final payments = ref.watch(paymentsReceivedProvider(project.id)).value ?? const <PaymentsReceivedData>[];
    final allocations = ref.watch(billAllocationsProvider(project.id)).value ?? const <BillAllocation>[];
    final received = payments.fold<double>(0, (s, p) => s + p.amount);
    final spent = ref.watch(costSummaryProvider(project.id)).value?.actual ?? 0;
    return Stack(children: [
      bills.when(
        data: (list) {
          final pnl = pnlFrom(bills: list, received: received, spent: spent);
          final balances = billBalances(list, allocations);
          final byId = {for (final b in balances) b.bill.id: b};
          final free = unallocated(payments, allocations).values.where((v) => v > 0.005).fold<double>(0, (s, v) => s + v);
          final due = balances.fold<double>(0, (s, b) => s + b.outstanding);
          final held = balances.fold<double>(0, (s, b) => s + b.retentionHeld);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            _PnlCard(pnl: pnl),
            Wrap(spacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.straighten, size: 18),
                label: Text(tr('Measurement book')),
                onPressed: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => MeasurementBookScreen(project: project)));
                  ref.invalidate(billsProvider(project.id));
                },
              ),
            ]),
            if (free > 0.005 && due > 0.005)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(trf('{amount} received is not against a bill yet', {'amount': rupees(free)})),
                  subtitle: Text(tr('Put it against the oldest bills still due.')),
                  trailing: FilledButton.tonal(
                    onPressed: () => _autoAllocate(context, ref, payments, allocations, balances),
                    child: Text(tr('Put against bills')),
                  ),
                ),
              ),
            if (held > 0.005)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                child: Text(trf('Retention held by the client: {amount}', {'amount': rupees(held)}),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (list.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr('Make running bills of measured work, or GST tax invoices, and send them as PDF. '
                  'Previous and to-date quantities are worked out for you.'),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final b in list)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Icon(b.kind == 'ra' ? Icons.request_quote_outlined : Icons.receipt_outlined)),
                  title: Text('${b.billNumber} · ${rupees(b.netPayable)}'),
                  subtitle: Text([
                    '${billKinds[b.kind]} · ${fmtDate(b.billDate)} · ${b.clientName}',
                    if (byId[b.id] case final bal? when bal.paid > 0.005 && !bal.settled)
                      trf('{paid} received, {due} due', {'paid': rupees(bal.paid), 'due': rupees(bal.outstanding)}),
                    if (byId[b.id] case final bal? when bal.retentionHeld > 0.005)
                      trf('retention held {amount}', {'amount': rupees(bal.retentionHeld)}),
                  ].join(' · ')),
                  trailing: StatusPill(
                      b.status == 'paid'
                          ? 'Paid'
                          : (byId[b.id]?.paid ?? 0) > 0.005
                              ? 'Part paid'
                              : 'Due',
                      tone: b.status == 'paid' ? PillTone.ok : PillTone.warn),
                  onTap: () => _openBill(context, ref, b, list, byId[b.id], payments, allocations),
                ),
              ),
          ]);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(billsProvider(project.id))),
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'new_bill',
          icon: const Icon(Icons.add),
          label: Text(tr('New bill')),
          onPressed: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => NewBillScreen(project: project, userId: userId)),
            );
            if (saved == true) ref.invalidate(billsProvider(project.id));
          },
        ),
      ),
    ]);
  }

  void _refresh(WidgetRef ref) {
    ref.invalidate(billsProvider(project.id));
    ref.invalidate(billAllocationsProvider(project.id));
  }

  /// Every payment's unallocated part, oldest payment first, against the
  /// oldest bills still due.
  Future<void> _autoAllocate(BuildContext context, WidgetRef ref, List<PaymentsReceivedData> payments,
      List<BillAllocation> allocations, List<BillBalance> balances) async {
    final free = unallocated(payments, allocations);
    final ordered = [...payments]..sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
    final dao = ref.read(appDatabaseProvider).billingRecordsDao;
    var n = 0;
    try {
      for (final p in ordered) {
        final left = free[p.id] ?? 0;
        if (left <= 0.005) continue;
        final current = billBalances(
            balances.map((b) => b.bill).toList(), await dao.allocationsFor(project.id));
        for (final (billId, amount) in planAllocation(left, current)) {
          await dao.allocate(paymentId: p.id, billId: billId, amount: amount, by: userId);
          n++;
        }
      }
      if (context.mounted) showSnack(context, trf('{n} amounts put against bills.', {'n': n}));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
    _refresh(ref);
  }

  /// Puts part of a payment against [bill] (its net amount or retention).
  Future<void> _allocateTo(BuildContext context, WidgetRef ref, ClientBill bill, BillBalance bal, String kind,
      List<PaymentsReceivedData> payments, List<BillAllocation> allocations) async {
    final free = unallocated(payments, allocations);
    final choices = [for (final p in payments) if ((free[p.id] ?? 0) > 0.005) p];
    if (choices.isEmpty) {
      showSnack(context, tr('Record the payment in the money book first. Every payment so far is already against a bill.'));
      return;
    }
    final need = kind == 'bill' ? bal.outstanding : bal.retentionHeld;
    var picked = choices.first;
    final amount = TextEditingController(text: fmtQty(need < free[picked.id]! ? need : free[picked.id]!));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(kind == 'bill' ? tr('Payment against this bill') : tr('Release retention')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: picked.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Payment received')),
              items: [
                for (final p in choices)
                  DropdownMenuItem(
                    value: p.id,
                    child: Text('${fmtDate(p.receivedOn, short: true)} · ${p.fromParty} · ${rupees(free[p.id]!)}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setLocal(() {
                picked = choices.firstWhere((p) => p.id == v);
                final f = free[picked.id]!;
                amount.text = fmtQty(need < f ? need : f);
              }),
            ),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Amount (₹)')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final a = double.tryParse(amount.text.trim().replaceAll(',', ''));
    if (a == null || a <= 0) return;
    try {
      await ref
          .read(appDatabaseProvider)
          .billingRecordsDao
          .allocate(paymentId: picked.id, billId: bill.id, kind: kind, amount: a, by: userId);
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
    _refresh(ref);
  }

  Future<void> _openBill(BuildContext context, WidgetRef ref, ClientBill b, List<ClientBill> all, BillBalance? bal,
      List<PaymentsReceivedData> payments, List<BillAllocation> allocations) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('${billKinds[b.kind]} ${b.billNumber}'),
            subtitle: Text([
              trf('{amount} payable', {'amount': rupees(b.netPayable, paise: true)}),
              if (currentLanguage == AppLanguage.en) rupeesInWords(b.netPayable),
            ].join(' · ')),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: Text(tr('Share PDF')),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          if (bal != null && bal.outstanding > 0.005)
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(tr('Payment against this bill')),
              subtitle: Text(trf('{amount} still due', {'amount': rupees(bal.outstanding)})),
              onTap: () => Navigator.pop(ctx, 'allocate'),
            ),
          if (bal != null && bal.retentionHeld > 0.005)
            ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: Text(tr('Release retention')),
              subtitle: Text(trf('retention held {amount}', {'amount': rupees(bal.retentionHeld)})),
              onTap: () => Navigator.pop(ctx, 'retention'),
            ),
          ListTile(
            leading: Icon(b.status == 'paid' ? Icons.undo : Icons.check_circle_outline),
            title: Text(b.status == 'paid' ? tr('Mark as not paid') : tr('Mark as paid')),
            onTap: () => Navigator.pop(ctx, 'paid'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'share':
        try {
          await shareBill(
            bill: b,
            companyName: ref.read(sessionProvider).activeCompany?.name ?? '',
            project: project,
            profile: await ref.read(billingProfileProvider(project.companyId).future),
            previousQty: previousFor(b, all),
            branding: await loadBranding(ref.read(appDatabaseProvider), project.companyId),
          );
        } catch (e, st) {
          if (context.mounted) showSnack(context, '${tr('Could not share the bill.')} ${friendlyError(e, st)}', error: true);
        }
      case 'paid':
        await ref.read(appDatabaseProvider).billDao.setStatus(b.id, b.status == 'paid' ? 'issued' : 'paid');
        ref.invalidate(billsProvider(project.id));
      case 'allocate' when bal != null:
        await _allocateTo(context, ref, b, bal, 'bill', payments, allocations);
      case 'retention' when bal != null:
        await _allocateTo(context, ref, b, bal, 'retention', payments, allocations);
    }
  }
}

class _PnlCard extends StatelessWidget {
  const _PnlCard({required this.pnl});
  final ProjectPnl pnl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget fig(String label, String value, {Color? color}) => Expanded(
          child: Column(children: [
            Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
            Text(tr(label), style: theme.textTheme.bodySmall),
          ]),
        );
    final pct = pnl.marginPct;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Profit and loss'), style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Row(children: [
            fig('Billed', rupees(pnl.billed)),
            fig('Spent', rupees(pnl.spent), color: toneColor(context, PillTone.danger)),
            fig('Margin', rupees(pnl.margin),
                color: pnl.margin < 0 ? toneColor(context, PillTone.danger) : toneColor(context, PillTone.ok)),
          ]),
          const SizedBox(height: 8),
          Text(
            [
              if (pct != null) trf('Margin {pct}% of billed work', {'pct': pct.toStringAsFixed(1)}),
              trf('Client owes {amount} on unpaid bills', {'amount': rupees(pnl.owed)}),
              trf('Received {amount}', {'amount': rupees(pnl.received)}),
            ].join(' · '),
            style: theme.textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }
}

class NewBillScreen extends ConsumerStatefulWidget {
  const NewBillScreen({super.key, required this.project, required this.userId, this.initialLines = const []});
  final Project project;
  final String userId;

  /// An RA bill's lines worked out from the approved measurements.
  final List<BillLine> initialLines;

  @override
  ConsumerState<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends ConsumerState<NewBillScreen> {
  String _kind = 'ra';
  DateTime _date = DateTime.now();
  late final _client = TextEditingController(text: widget.project.clientName ?? '');
  final _clientGstin = TextEditingController();
  final _number = TextEditingController();
  final _retention = TextEditingController(text: '5');
  final _tds = TextEditingController(text: '0');
  final _notes = TextEditingController();
  double _gstRate = 18;
  bool _interState = false;
  bool _interStateTouched = false;
  bool _numberTouched = false;
  final _lines = <BillLine>[];
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lines.addAll(widget.initialLines);
    _clientGstin.addListener(_gstinChanged);
  }

  @override
  void dispose() {
    for (final c in [_client, _clientGstin, _number, _retention, _tds, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _gstinChanged() {
    if (_interStateTouched) return;
    final ours = ref.read(billingProfileProvider(widget.project.companyId)).value?.gstin;
    final inter = isInterState(ours, _clientGstin.text);
    if (inter != _interState) setState(() => _interState = inter);
  }

  double _pct(TextEditingController c) => (double.tryParse(c.text.trim()) ?? 0).clamp(0, 100).toDouble();

  Map<String, double> _previous(List<ClientBill> bills) => previousQuantities(
      bills.where((b) => b.kind == 'ra' && !b.billDate.isAfter(_date)).map((b) => decodeLines(b.linesJson)));

  Future<void> _editLine({int? index, Map<String, double> previous = const {}}) async {
    final existing = index == null ? null : _lines[index];
    final desc = TextEditingController(text: existing?.description ?? '');
    final unit = TextEditingController(text: existing?.unit ?? '');
    final rate = TextEditingController(text: existing == null ? '' : fmtQty(existing.rate));
    final qty = TextEditingController(text: existing == null ? '' : fmtQty(existing.qty));
    final result = await showDialog<BillLine>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? tr('Add item') : tr('Edit item')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: desc,
              autofocus: index == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Item (e.g. Brickwork in CM 1:6)')),
            ),
            TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit (cum, sqm, rft, nos)'))),
            TextField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: tr('Rate (₹ per unit)')),
            ),
            TextField(
              controller: qty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(labelText: _kind == 'ra' ? tr('Quantity this bill') : tr('Quantity')),
            ),
          ]),
        ),
        actions: [
          if (index != null)
            TextButton(
              onPressed: () {
                setState(() => _lines.removeAt(index));
                Navigator.pop(ctx);
              },
              child: Text(tr('Remove')),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(
            onPressed: () {
              final d = desc.text.trim();
              final r = double.tryParse(rate.text.trim());
              final q = double.tryParse(qty.text.trim());
              if (d.isEmpty || r == null || q == null || r < 0 || q < 0) return;
              Navigator.pop(ctx, BillLine(description: d, unit: unit.text.trim(), rate: r, qty: q));
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _lines.add(result);
      } else {
        _lines[index] = result;
      }
    });
  }

  void _copyItems(List<ClientBill> bills) {
    final last = bills.where((b) => b.kind == _kind).firstOrNull;
    if (last == null) return;
    setState(() {
      _lines
        ..clear()
        ..addAll([
          for (final l in decodeLines(last.linesJson)) BillLine(description: l.description, unit: l.unit, rate: l.rate, qty: 0),
        ]);
      _client.text = last.clientName;
      _clientGstin.text = last.clientGstin ?? '';
      _gstRate = last.gstRate;
      _retention.text = fmtQty(last.retentionPct);
      _tds.text = fmtQty(last.tdsPct);
    });
  }

  Future<void> _save(List<ClientBill> bills) async {
    final client = _client.text.trim();
    final gstin = _clientGstin.text.trim().toUpperCase();
    final number = _number.text.trim().isEmpty ? nextBillNumber(bills.map((b) => b.billNumber), _kind) : _number.text.trim();
    final lines = _lines.where((l) => l.qty > 0).toList();
    String? error;
    if (client.isEmpty) error = tr('Who is the bill for? Add the client name.');
    if (gstin.isNotEmpty && !isValidGstin(gstin)) error = tr('That GSTIN doesn\'t look right. It has 15 characters, like 36ABCDE1234F1Z5.');
    if (lines.isEmpty) error = tr('Add at least one item with a quantity.');
    if (bills.any((b) => b.billNumber.toLowerCase() == number.toLowerCase())) error = trf('Bill {number} already exists.', {'number': number});
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    final totals = billTotals(lines,
        gstRate: _gstRate, interState: _interState, retentionPct: _pct(_retention), tdsPct: _pct(_tds));
    await ref.read(appDatabaseProvider).billDao.create(ClientBillsCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.project.id,
          kind: _kind,
          billNumber: number.length > 30 ? number.substring(0, 30) : number,
          billDate: DateTime(_date.year, _date.month, _date.day),
          clientName: client.length > 200 ? client.substring(0, 200) : client,
          clientGstin: Value(gstin.isEmpty ? null : gstin),
          linesJson: encodeLines(lines),
          gstRate: Value(_gstRate),
          interState: Value(_interState),
          retentionPct: Value(_pct(_retention)),
          tdsPct: Value(_pct(_tds)),
          gross: totals.gross,
          netPayable: totals.netPayable,
          notes: Value(_notes.text.trim().isEmpty ? null : _notes.text.trim()),
          recordedBy: widget.userId,
        ));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _editProfile(BillingProfile current) async {
    final gstin = TextEditingController(text: current.gstin);
    final address = TextEditingController(text: current.address);
    final upi = TextEditingController(text: current.upiId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Your details on bills')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: gstin,
              textCapitalization: TextCapitalization.characters,
              maxLength: 15,
              decoration: InputDecoration(labelText: tr('Your GSTIN')),
            ),
            TextField(controller: address, maxLines: 3, decoration: InputDecoration(labelText: tr('Address'))),
            TextField(controller: upi, decoration: InputDecoration(labelText: tr('UPI id for payments (optional)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true) return;
    final g = gstin.text.trim().toUpperCase();
    if (g.isNotEmpty && !isValidGstin(g)) {
      if (mounted) showSnack(context, 'That GSTIN doesn\'t look right, so it wasn\'t saved.', error: true);
      return;
    }
    await saveBillingProfile(ref.read(appDatabaseProvider), widget.project.companyId,
        BillingProfile(gstin: g, address: address.text, upiId: upi.text));
    ref.invalidate(billingProfileProvider(widget.project.companyId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bills = ref.watch(billsProvider(widget.project.id)).value ?? const <ClientBill>[];
    final profile = ref.watch(billingProfileProvider(widget.project.companyId)).value ?? const BillingProfile();
    final previous = _previous(bills);
    final totals = billTotals(_lines,
        gstRate: _gstRate, interState: _interState, retentionPct: _pct(_retention), tdsPct: _pct(_tds));
    final suggested = nextBillNumber(bills.map((b) => b.billNumber), _kind);
    if (!_numberTouched && _number.text != suggested) _number.text = suggested;
    final hasEarlier = bills.any((b) => b.kind == _kind);

    return Scaffold(
      appBar: AppBar(title: Text(tr('New bill'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          SegmentedButton<String>(
            segments: [for (final e in billKinds.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _numberTouched = false;
            }),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text(tr('Your details on bills')),
              subtitle: Text(profile.gstin.isEmpty ? tr('Add your GSTIN, address and UPI id') : 'GSTIN ${profile.gstin}'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editProfile(profile),
            ),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _number,
                onChanged: (_) => _numberTouched = true,
                decoration: InputDecoration(labelText: tr('Bill number')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined),
                label: Text(fmtDate(_date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
            ),
          ]),
          TextField(
            controller: _client,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Client name')),
          ),
          TextField(
            controller: _clientGstin,
            textCapitalization: TextCapitalization.characters,
            maxLength: 15,
            decoration: InputDecoration(labelText: tr('Client GSTIN (optional)'), counterText: ''),
          ),
          const SizedBox(height: 12),
          Text('GST', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<double>(
            segments: [
              ButtonSegment(value: 0, label: Text(tr('None'))),
              ButtonSegment(value: 5, label: Text('5%')),
              ButtonSegment(value: 12, label: Text('12%')),
              ButtonSegment(value: 18, label: Text('18%')),
            ],
            selected: {_gstRate},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _gstRate = s.first),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Client is in another state (IGST)')),
            subtitle: Text(tr('Inside the state, GST splits into CGST and SGST')),
            value: _interState,
            onChanged: (v) => setState(() {
              _interState = v;
              _interStateTouched = true;
            }),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _retention,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: tr('Retention %'), helperText: tr('Held back by the client')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _tds,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: tr('TDS %'), helperText: tr('Usually 1% or 2%')),
              ),
            ),
          ]),
          SectionHeader(_kind == 'ra' ? tr('Work measured this bill') : tr('Items')),
          if (_lines.isEmpty && hasEarlier)
            OutlinedButton.icon(
              icon: const Icon(Icons.content_copy_outlined),
              label: Text(tr('Copy items from the last bill')),
              onPressed: () => _copyItems(bills),
            ),
          for (final (i, l) in _lines.indexed)
            Card(
              child: ListTile(
                title: Text(l.description),
                subtitle: Text(_kind == 'ra'
                    ? '${trf('Previous {prev} + this bill {qty} = {total}', {'prev': fmtQty(previous[l.itemKey] ?? 0), 'qty': fmtQty(l.qty), 'total': fmtQty((previous[l.itemKey] ?? 0) + l.qty)})}'
                        ' ${l.unit} @ ${rupees(l.rate, paise: true)}'
                    : '${fmtQty(l.qty)} ${l.unit} @ ${rupees(l.rate, paise: true)}'),
                trailing: Text(rupees(l.amount)),
                onTap: () => _editLine(index: i, previous: previous),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('Add item')),
            onPressed: () => _editLine(previous: previous),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                _row('Value of work', rupees(totals.gross, paise: true)),
                if (_interState)
                  _row('IGST ${fmtQty(_gstRate)}%', rupees(totals.igst, paise: true))
                else if (_gstRate > 0) ...[
                  _row('CGST ${fmtQty(_gstRate / 2)}%', rupees(totals.cgst, paise: true)),
                  _row('SGST ${fmtQty(_gstRate / 2)}%', rupees(totals.sgst, paise: true)),
                ],
                if (totals.retention > 0) _row('Less retention', '- ${rupees(totals.retention, paise: true)}'),
                if (totals.tds > 0) _row('Less TDS', '- ${rupees(totals.tds, paise: true)}'),
                const Divider(),
                _row('Payable', rupees(totals.netPayable, paise: true), bold: true),
                const SizedBox(height: 4),
                Text(rupeesInWords(totals.netPayable), style: theme.textTheme.bodySmall),
              ]),
            ),
          ),
          TextField(controller: _notes, maxLength: 500, decoration: InputDecoration(labelText: tr('Notes (optional)'))),
          if (_error != null) ...[const SizedBox(height: 8), FormMessage(_error!)],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : () => _save(bills),
            child: Text(_saving ? tr('Saving…') : tr('Save bill')),
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(tr(label), style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null)),
          Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null),
        ]),
      );
}
