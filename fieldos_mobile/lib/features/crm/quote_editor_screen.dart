/// Make or change a quotation: items with unit, quantity and rate, a
/// discount, GST, validity and terms. The total updates as you type, and
/// the PDF goes out on WhatsApp from the same screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/crm/quote_pdf.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart' show BillLine;
import 'package:fieldos_mobile/features/money/bills_view.dart' show billingProfileProvider;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class _LineCtl {
  _LineCtl([BillLine? l])
      : description = TextEditingController(text: l?.description),
        unit = TextEditingController(text: l?.unit),
        qty = TextEditingController(text: l == null ? '' : fmtQty(l.qty)),
        rate = TextEditingController(text: l == null ? '' : fmtQty(l.rate));
  final TextEditingController description;
  final TextEditingController unit;
  final TextEditingController qty;
  final TextEditingController rate;

  static double _n(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  BillLine get line => BillLine(description: description.text.trim(), unit: unit.text.trim(), rate: _n(rate), qty: _n(qty));

  void dispose() {
    for (final c in [description, unit, qty, rate]) {
      c.dispose();
    }
  }
}

class QuoteEditorScreen extends ConsumerStatefulWidget {
  const QuoteEditorScreen({super.key, required this.companyId, required this.lead, this.quote, this.copyFrom});
  final String companyId;
  final CrmLead lead;

  /// The quote to change; null for a new one.
  final CrmQuote? quote;

  /// A new quote starts from this one's items (a revised offer).
  final CrmQuote? copyFrom;

  @override
  ConsumerState<QuoteEditorScreen> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends ConsumerState<QuoteEditorScreen> {
  late CrmQuote? _quote = widget.quote;
  late final List<_LineCtl> _lines;
  late final _discount = TextEditingController(
      text: (_source?.discount ?? 0) == 0 ? '' : fmtQty(_source!.discount));
  late final _terms = TextEditingController(text: _source?.terms ?? defaultQuoteTerms);
  late double _gst = _source?.gstRate ?? 18;
  late bool _interState = _source?.interState ?? false;
  late DateTime? _validUntil = widget.quote?.validUntil ?? DateTime.now().add(const Duration(days: 30));
  String? _error;
  bool _busy = false;

  CrmQuote? get _source => widget.quote ?? widget.copyFrom;
  bool get _locked => _quote?.status == 'accepted';

  @override
  void initState() {
    super.initState();
    final src = _source;
    _lines = src == null ? [_LineCtl()] : [for (final l in decodeQuoteLines(src.linesJson)) _LineCtl(l)];
    if (_lines.isEmpty) _lines.add(_LineCtl());
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    _discount.dispose();
    _terms.dispose();
    super.dispose();
  }

  QuoteTotals get _totals => quoteTotals([for (final l in _lines) l.line],
      discount: double.tryParse(_discount.text.replaceAll(',', '').trim()) ?? 0, gstRate: _gst, interState: _interState);

  Future<CrmQuote?> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final q = await ref.read(appDatabaseProvider).crmDao.saveQuote(
            id: _quote?.id,
            leadId: widget.lead.id,
            lines: [for (final l in _lines) l.line],
            by: ref.read(sessionProvider).user!.id,
            gstRate: _gst,
            interState: _interState,
            discount: double.tryParse(_discount.text.replaceAll(',', '').trim()) ?? 0,
            quoteDate: _quote?.quoteDate,
            validUntil: _validUntil,
            terms: _terms.text,
          );
      setState(() => _quote = q);
      return q;
    } catch (e, st) {
      setState(() => _error = friendlyError(e, st));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final q = _locked ? _quote : await _save();
    if (q == null || !mounted) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final company = ref.read(sessionProvider).activeCompany;
      final profile = await ref.read(billingProfileProvider(widget.companyId).future);
      await shareQuote(
        quote: q,
        lead: widget.lead,
        companyName: company?.name ?? '',
        profile: profile,
        branding: await loadBranding(db, widget.companyId),
      );
      if (q.status == 'draft') {
        final sent = await db.crmDao.setQuoteStatus(q.id, 'sent', by: ref.read(sessionProvider).user!.id);
        if (mounted) setState(() => _quote = sent);
      }
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _status(String status) async {
    final q = _quote;
    if (q == null) return;
    try {
      final row = await ref.read(appDatabaseProvider).crmDao.setQuoteStatus(q.id, status, by: ref.read(sessionProvider).user!.id);
      setState(() => _quote = row);
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = _totals;
    final half = fmtQty(_gst / 2);
    Widget sum(String label, double v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)),
            Text(rupees(v, paise: true), style: bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium),
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(_quote == null ? tr('New quote') : _quote!.quoteNumber),
        actions: [
          if (_quote != null && !_locked)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'delete') {
                  try {
                    await ref.read(appDatabaseProvider).crmDao.deleteQuote(_quote!.id);
                    if (context.mounted) Navigator.of(context).pop();
                  } catch (e, st) {
                    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
                  }
                } else {
                  await _status(v);
                }
              },
              itemBuilder: (_) => [
                if (_quote!.status != 'accepted')
                  PopupMenuItem(value: 'accepted', child: Text(tr('Client accepted'))),
                if (_quote!.status != 'rejected')
                  PopupMenuItem(value: 'rejected', child: Text(tr('Client said no'))),
                PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
              ],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 120), children: [
        Text(widget.lead.name, style: theme.textTheme.titleMedium),
        if (_quote != null) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(quoteStatusLabels[_quote!.status]!,
                tone: _quote!.status == 'accepted' ? PillTone.ok : PillTone.neutral),
          ),
        ],
        if (_locked)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr('Accepted quotes are kept as agreed. Make a new version to change the price.')),
          ),
        SectionHeader('Items'),
        for (final (i, l) in _lines.indexed)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: l.description,
                      enabled: !_locked,
                      decoration: InputDecoration(labelText: trf('Item {n}', {'n': i + 1})),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (!_locked && _lines.length > 1)
                    IconButton(
                      tooltip: tr('Remove item'),
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _lines.removeAt(i).dispose()),
                    ),
                ]),
                Row(children: [
                  Expanded(
                    child: TextField(
                        controller: l.qty,
                        enabled: !_locked,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: tr('Qty')),
                        onChanged: (_) => setState(() {})),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: l.unit,
                        enabled: !_locked,
                        decoration: InputDecoration(labelText: tr('Unit'), hintText: 'sq.ft'),
                        onChanged: (_) => setState(() {})),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                        controller: l.rate,
                        enabled: !_locked,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: tr('Rate'), prefixText: '₹ '),
                        onChanged: (_) => setState(() {})),
                  ),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8),
                    child: Text(rupees(l.line.amount, paise: true), style: theme.textTheme.bodySmall),
                  ),
                ),
              ]),
            ),
          ),
        if (!_locked)
          TextButton.icon(
            onPressed: () => setState(() => _lines.add(_LineCtl())),
            icon: const Icon(Icons.add),
            label: Text(tr('Add item')),
          ),
        SectionHeader('Price'),
        TextField(
          controller: _discount,
          enabled: !_locked,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: tr('Discount (optional)'), prefixText: '₹ '),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<double>(
              isExpanded: true,
              initialValue: const [0.0, 5.0, 12.0, 18.0, 28.0].contains(_gst) ? _gst : 18,
              decoration: InputDecoration(labelText: tr('GST')),
              items: [for (final r in const [0.0, 5.0, 12.0, 18.0, 28.0]) DropdownMenuItem(value: r, child: Text('${fmtQty(r)}%'))],
              onChanged: _locked ? null : (v) => setState(() => _gst = v ?? 18),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Other state (IGST)')),
              value: _interState,
              onChanged: _locked ? null : (v) => setState(() => _interState = v),
            ),
          ),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text(tr('Valid until')),
          subtitle: Text(_validUntil == null ? tr('Not set') : fmtDate(_validUntil!)),
          onTap: _locked
              ? null
              : () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _validUntil ?? now.add(const Duration(days: 30)),
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2));
                  if (d != null) setState(() => _validUntil = d);
                },
        ),
        TextField(
          controller: _terms,
          enabled: !_locked,
          maxLines: 4,
          maxLength: 2000,
          decoration: InputDecoration(labelText: tr('Terms')),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              sum(tr('Subtotal'), t.subtotal),
              if (t.discount > 0) sum(tr('Less discount'), -t.discount),
              if (_interState)
                sum('IGST ${fmtQty(_gst)}%', t.igst)
              else if (_gst > 0) ...[
                sum('CGST $half%', t.cgst),
                sum('SGST $half%', t.sgst),
              ],
              const Divider(),
              sum(tr('Total'), t.total, bold: true),
            ]),
          ),
        ),
        if (_error != null) FormMessage(_error!),
      ]),
      bottomNavigationBar: SystemNavBarSafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            if (!_locked)
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final q = await _save();
                          if (q != null && context.mounted) showSnack(context, trf('{n} saved', {'n': q.quoteNumber}));
                        },
                  child: Text(tr('Save')),
                ),
              ),
            if (!_locked) const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.share_outlined),
                label: Text(tr('Send PDF')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
