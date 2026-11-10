/// The measurement book: work measured on site against the BOQ, approved
/// by the owner or a project manager, and billed to the client from the
/// approved quantity. Rules in billing_reconcile.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/billing_reconcile.dart';
import 'package:fieldos_mobile/features/money/bills_view.dart';
import 'package:fieldos_mobile/features/team/site_team_screen.dart' show mySiteAccessProvider;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class MeasurementBook {
  const MeasurementBook({required this.measurements, required this.decisions, required this.boq, required this.approved});
  final List<WorkMeasurement> measurements;
  final Map<String, WorkMeasurementDecision> decisions;

  /// The site's priced BOQ items (cost heads), to measure against.
  final List<CostHead> boq;
  final Map<String, ApprovedItem> approved;
}

final measurementBookProvider = FutureProvider.autoDispose.family<MeasurementBook, String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  final heads = <CostHead>[];
  for (final e in await db.estimationDao.forProject(projectId)) {
    heads.addAll(await db.estimationDao.costHeadsFor(e.id));
  }
  final ms = await db.billingRecordsDao.measurementsFor(projectId);
  final ds = await db.billingRecordsDao.decisionsFor(projectId);
  return MeasurementBook(
    measurements: ms,
    decisions: ds,
    boq: heads,
    approved: approvedToDate(ms, ds, boqRates: {for (final h in heads) if (h.ratePerUnit != null) h.id: h.ratePerUnit!}),
  );
});

class MeasurementBookScreen extends ConsumerStatefulWidget {
  const MeasurementBookScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<MeasurementBookScreen> createState() => _MeasurementBookScreenState();
}

class _MeasurementBookScreenState extends ConsumerState<MeasurementBookScreen> {
  bool _busy = false;
  String get _pid => widget.project.id;
  String get _me => ref.read(sessionProvider).user?.id ?? '';

  Future<void> _run(Future<void> Function() job, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      ref.invalidate(measurementBookProvider(_pid));
      if (mounted && done != null) showSnack(context, done);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _measure(MeasurementBook book) async {
    CostHead? head;
    final desc = TextEditingController();
    final unit = TextEditingController();
    final rate = TextEditingController();
    final qty = TextEditingController();
    final where = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Measure work')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (book.boq.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: head?.id ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('BOQ item')),
                  items: [
                    DropdownMenuItem(value: '', child: Text(tr('Not in the BOQ'))),
                    for (final h in book.boq) DropdownMenuItem(value: h.id, child: Text(h.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setLocal(() {
                    head = book.boq.where((h) => h.id == v).firstOrNull;
                    if (head != null) {
                      desc.text = head!.name;
                      unit.text = head!.billingUnit;
                      rate.text = head!.ratePerUnit == null ? '' : fmtQty(head!.ratePerUnit!);
                    }
                  }),
                ),
              TextField(controller: desc, decoration: InputDecoration(labelText: tr('Item (e.g. Brickwork in CM 1:6)'))),
              TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit (cum, sqm, rft, nos)'))),
              TextField(
                controller: rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(labelText: tr('Rate (₹ per unit)')),
              ),
              TextField(
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                decoration: InputDecoration(
                    labelText: tr('Quantity measured'), helperText: tr('A minus quantity corrects an earlier one.')),
              ),
              TextField(controller: where, decoration: InputDecoration(labelText: tr('Where (e.g. Block A, 2nd floor)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = double.tryParse(qty.text.trim());
    if (q == null || q == 0 || desc.text.trim().isEmpty || unit.text.trim().isEmpty) {
      if (mounted) showSnack(context, tr('Give the item, its unit and a quantity.'), error: true);
      return;
    }
    await _run(
      () => ref.read(appDatabaseProvider).billingRecordsDao.measure(
            projectId: _pid,
            costHeadId: head?.id,
            description: desc.text,
            unit: unit.text,
            rate: double.tryParse(rate.text.trim()),
            qty: q,
            on: DateTime.now(),
            by: _me,
            location: where.text.trim().isEmpty ? null : where.text.trim(),
          ),
      done: tr('Measurement saved. It waits for approval.'),
    );
  }

  Future<void> _decide(WorkMeasurement m) async {
    final qty = TextEditingController(text: fmtQty(m.qty));
    final note = TextEditingController();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.description),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(trf('Measured {qty} {unit}', {'qty': fmtQty(m.qty), 'unit': m.unit})),
          TextField(
            controller: qty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: tr('Quantity approved')),
          ),
          TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'reject'), child: Text(tr('Reject'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'approve'), child: Text(tr('Approve'))),
        ],
      ),
    );
    if (choice == null) return;
    await _run(
      () => ref.read(appDatabaseProvider).billingRecordsDao.decide(m.id,
          approve: choice == 'approve',
          approvedQty: double.tryParse(qty.text.trim()),
          by: _me,
          note: note.text.trim().isEmpty ? null : note.text.trim()),
      done: choice == 'approve' ? tr('Approved.') : tr('Rejected.'),
    );
  }

  Future<void> _bill(MeasurementBook book) async {
    final bills = await ref.read(billsProvider(_pid).future);
    final draft = nextRaLines(
      approved: book.approved,
      earlierBills: bills.where((b) => b.kind == 'ra').map((b) => decodeLines(b.linesJson)),
    );
    if (!mounted) return;
    if (draft.lines.isEmpty) {
      showSnack(
          context,
          draft.noRate.isEmpty
              ? tr('Everything approved has been billed already.')
              : trf('Set a rate for {items} first.', {'items': draft.noRate.join(', ')}),
          error: draft.noRate.isNotEmpty);
      return;
    }
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => NewBillScreen(project: widget.project, userId: _me, initialLines: draft.lines)));
    if (saved == true) ref.invalidate(billsProvider(_pid));
  }

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(measurementBookProvider(_pid));
    final canDecide = ref.watch(mySiteAccessProvider(_pid)).value?.managesSite ?? false;
    return Scaffold(
      appBar: AppBar(title: Text('${tr('Measurement book')} · ${widget.project.name}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy || book.value == null ? null : () => _measure(book.value!),
        icon: const Icon(Icons.straighten),
        label: Text(tr('Measure work')),
      ),
      body: book.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(measurementBookProvider(_pid))),
        data: (b) {
          final waiting = b.measurements.where((m) => b.decisions[m.id] == null).length;
          return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Approved to date'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  if (b.approved.isEmpty) Text(tr('Nothing approved yet.')),
                  for (final a in b.approved.values)
                    Row(children: [
                      Expanded(child: Text(a.description)),
                      Text('${fmtQty(a.qty)} ${a.unit}'),
                    ]),
                  if (canDecide && b.approved.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _bill(b),
                      icon: const Icon(Icons.request_quote_outlined),
                      label: Text(tr('Make the next RA bill')),
                    ),
                  ],
                ]),
              ),
            ),
            if (waiting > 0) SectionHeader(trf('{n} waiting for approval', {'n': waiting})),
            if (b.measurements.isEmpty)
              EmptyState(
                compact: true,
                icon: Icons.straighten,
                title: tr('No measurements yet'),
                message: tr('Measure work done against the BOQ. Approved quantities go on the next RA bill.'),
              ),
            for (final m in b.measurements.reversed)
              Card(
                child: ListTile(
                  title: Text(m.description),
                  subtitle: Text([
                    '${fmtQty(m.qty)} ${m.unit}',
                    if (m.rate != null) '@ ${rupees(m.rate!)}',
                    fmtDate(m.measuredOn, short: true),
                    if (m.location != null) m.location!,
                  ].join(' · ')),
                  trailing: switch (b.decisions[m.id]) {
                    null => canDecide
                        ? FilledButton.tonal(onPressed: _busy ? null : () => _decide(m), child: Text(tr('Decide')))
                        : StatusPill(tr('Waiting'), tone: PillTone.warn),
                    final d when d.decision == 'approved' => StatusPill(
                        d.approvedQty == m.qty
                            ? tr('Approved')
                            : trf('Approved {qty}', {'qty': fmtQty(d.approvedQty!)}),
                        tone: PillTone.ok),
                    _ => StatusPill(tr('Rejected'), tone: PillTone.danger),
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}
