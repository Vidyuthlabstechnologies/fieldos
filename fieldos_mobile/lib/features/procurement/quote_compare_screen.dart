/// Quotes for one purchase request: ask several suppliers on WhatsApp,
/// enter what each quoted, see them side by side at their landed cost, and
/// give the order to the best one as a PO.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fieldos_mobile/auth/auth_service.dart' show Roles;
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

typedef QuoteData = ({PurchaseRequest request, List<SupplierQuote> quotes, List<Supplier> suppliers, Project? site});

final quoteDataProvider = FutureProvider.autoDispose.family<QuoteData, ({String requestId, String companyId})>((ref, k) async {
  final db = ref.watch(appDatabaseProvider);
  final request = await (db.select(db.purchaseRequests)..where((r) => r.id.equals(k.requestId))).getSingle();
  return (
    request: request,
    quotes: await db.supplierQuoteDao.forRequest(k.requestId),
    suppliers: await db.supplierDao.forCompany(k.companyId),
    site: await db.projectDao.byId(request.projectId),
  );
});

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', ''));

class QuoteCompareScreen extends ConsumerWidget {
  const QuoteCompareScreen({super.key, required this.requestId, required this.companyId, required this.userId});
  final String requestId;
  final String companyId;
  final String userId;

  ({String requestId, String companyId}) get _key => (requestId: requestId, companyId: companyId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(quoteDataProvider(_key));
    final session = ref.watch(sessionProvider);
    final canAward = Roles.canApprove(session.role);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Compare quotes'))),
      floatingActionButton: async.value?.request.status == 'pending'
          ? FloatingActionButton.extended(
              key: const Key('add-quote'),
              icon: const Icon(Icons.add),
              label: Text(tr('Add quote')),
              onPressed: () => _addQuote(context, ref, async.value!),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (d) {
          final now = DateTime.now();
          final c = compareQuotes(d.request, d.quotes, now);
          final names = {for (final s in d.suppliers) s.id: s.name};
          final theme = Theme.of(context);
          final vsNext = c.savingVsNext(now);
          final vsEst = c.savingVsEstimate();
          final fastest = c.fastestDays(now);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            Text(d.request.materialName, style: theme.textTheme.titleLarge),
            Text([
              '${fmtQty(d.request.quantity)} ${d.request.unit}'.trim(),
              if (d.site != null) d.site!.name,
              if (d.request.estimatedAmount != null)
                trf('about {amount}', {'amount': rupees(d.request.estimatedAmount!)}),
            ].join(' · ')),
            const SizedBox(height: 8),
            if (d.request.status == 'pending')
              OutlinedButton.icon(
                key: const Key('ask-suppliers'),
                icon: const Icon(Icons.send_outlined),
                label: Text(tr('Ask suppliers for rates')),
                onPressed: () => _ask(context, ref, d),
              ),
            if (c.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tr('No quotes yet. Ask two or three suppliers, then add what each one quoted.'),
                    textAlign: TextAlign.center),
              )
            else ...[
              if (vsNext != null && vsNext > 0 && c.best?.quote.status == 'received')
                Card(
                  color: theme.colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(trf('{supplier} is cheapest, {amount} less than the next quote.',
                        {'supplier': names[c.best!.quote.supplierId] ?? '?', 'amount': rupees(vsNext)})),
                  ),
                ),
              const SectionHeader('Quotes, cheapest first'),
              for (final (i, l) in c.lines.indexed)
                _QuoteCard(
                  line: l,
                  supplier: names[l.quote.supplierId] ?? '?',
                  cheapest: i == 0 && l.quote.status != 'rejected' && !l.expired(now),
                  slow: fastest != null && l.quote.deliveryDays != null && l.quote.deliveryDays! > fastest,
                  expired: l.expired(now),
                  canAward: canAward && d.request.status == 'pending' && l.quote.status == 'received' && !l.expired(now),
                  onAward: () => _award(context, ref, l, names[l.quote.supplierId] ?? '?'),
                  onReject: canAward && l.quote.status == 'received'
                      ? () async {
                          await ref.read(appDatabaseProvider).supplierQuoteDao.reject(l.quote.id);
                          ref.invalidate(quoteDataProvider(_key));
                        }
                      : null,
                ),
              if (vsEst != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      vsEst >= 0
                          ? trf('Best quote is {amount} under the estimate.', {'amount': rupees(vsEst)})
                          : trf('Best quote is {amount} over the estimate.', {'amount': rupees(-vsEst)}),
                      style: theme.textTheme.bodySmall),
                ),
            ],
          ]);
        },
      ),
    );
  }

  Future<void> _ask(BuildContext context, WidgetRef ref, QuoteData d) async {
    final company = ref.read(sessionProvider).activeCompany;
    final text = rfqMessage(
      request: d.request,
      siteName: d.site?.name ?? '',
      siteLocation: d.site?.locationLat == null || d.site?.locationLng == null
          ? null
          : 'https://maps.google.com/?q=${d.site!.locationLat},${d.site!.locationLng}',
      companyName: company?.name ?? '',
    );
    final withPhone = [for (final s in d.suppliers) if ((s.contactPhone ?? '').replaceAll(RegExp(r'\D'), '').length >= 10) s];
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(tr('Share the message')),
              onTap: () => Navigator.pop(ctx, '')),
          for (final s in withPhone)
            ListTile(
                leading: const Icon(Icons.chat_outlined),
                title: Text(trf('WhatsApp {name}', {'name': s.name})),
                onTap: () => Navigator.pop(ctx, s.contactPhone)),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice.isEmpty) {
      await SharePlus.instance.share(ShareParams(text: text));
      return;
    }
    var digits = choice.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) digits = '91$digits';
    await launchUrl(Uri.parse('https://wa.me/$digits?text=${Uri.encodeComponent(text)}'),
        mode: LaunchMode.externalApplication);
  }

  Future<void> _addQuote(BuildContext context, WidgetRef ref, QuoteData d) async {
    if (d.suppliers.isEmpty) {
      showSnack(context, tr('Add a supplier first.'), error: true);
      return;
    }
    final saved = await showModalBottomSheet<SupplierQuote>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _QuoteForm(request: d.request, suppliers: d.suppliers, userId: userId),
    );
    if (saved != null) ref.invalidate(quoteDataProvider(_key));
  }

  Future<void> _award(BuildContext context, WidgetRef ref, QuoteLine l, String supplier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Give the order?')),
        content: Text(trf('A PO for {amount} goes to {supplier}. The other quotes are turned down.',
            {'amount': rupees(l.landed), 'supplier': supplier})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('award-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Make PO'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(appDatabaseProvider).supplierQuoteDao.award(l.quote.id, by: userId);
      ref.invalidate(quoteDataProvider(_key));
      ref.invalidate(requestsProvider(l.quote.projectId));
      ref.invalidate(ordersProvider(l.quote.projectId));
      if (context.mounted) showSnack(context, trf('PO made for {supplier}', {'supplier': supplier}));
    } on ArgumentError catch (e) {
      if (context.mounted) showSnack(context, tr('${e.message}'), error: true);
    }
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.line,
    required this.supplier,
    required this.cheapest,
    required this.slow,
    required this.expired,
    required this.canAward,
    required this.onAward,
    this.onReject,
  });
  final QuoteLine line;
  final String supplier;
  final bool cheapest;
  final bool slow;
  final bool expired;
  final bool canAward;
  final VoidCallback onAward;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final q = line.quote;
    final t = Theme.of(context).textTheme;
    return Card(
      key: Key('quote-${q.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(supplier, style: t.titleMedium)),
            if (q.status == 'accepted')
              const StatusPill('Ordered', tone: PillTone.ok)
            else if (q.status == 'rejected')
              const StatusPill('Turned down')
            else if (expired)
              const StatusPill('Expired', tone: PillTone.warn)
            else if (cheapest)
              const StatusPill('Cheapest', tone: PillTone.ok),
          ]),
          const SizedBox(height: 4),
          Text(rupees(line.landed), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(trf('{rate} a unit + GST {gst}% · landed {perUnit} a unit',
              {'rate': rupees(q.rate, paise: true), 'gst': fmtQty(q.gstPct), 'perUnit': rupees(line.perUnit, paise: true)})),
          Text([
            if (q.transport > 0) trf('Transport {amount}', {'amount': rupees(q.transport)}) else tr('Transport included'),
            if (q.deliveryDays != null) trf('{n} days to deliver', {'n': q.deliveryDays!}),
            if (q.paymentTerms != null) q.paymentTerms!,
          ].join(' · '), style: slow ? t.bodyMedium?.copyWith(color: toneColor(context, PillTone.warn)) : t.bodyMedium),
          if (q.notes != null) Text(q.notes!, style: t.bodySmall),
          if (canAward || onReject != null)
            OverflowBar(alignment: MainAxisAlignment.end, spacing: 8, overflowAlignment: OverflowBarAlignment.end, children: [
              if (onReject != null) TextButton(onPressed: onReject, child: Text(tr('Turn down'))),
              if (canAward)
                FilledButton(key: Key('award-${q.id}'), onPressed: onAward, child: Text(tr('Give order'))),
            ]),
        ]),
      ),
    );
  }
}

class _QuoteForm extends ConsumerStatefulWidget {
  const _QuoteForm({required this.request, required this.suppliers, required this.userId});
  final PurchaseRequest request;
  final List<Supplier> suppliers;
  final String userId;

  @override
  ConsumerState<_QuoteForm> createState() => _QuoteFormState();
}

class _QuoteFormState extends ConsumerState<_QuoteForm> {
  late String _supplier = widget.suppliers.first.id;
  final _rate = TextEditingController();
  final _transport = TextEditingController();
  final _days = TextEditingController();
  final _terms = TextEditingController();
  final _notes = TextEditingController();
  double _gst = 18;
  String? _error;

  @override
  void dispose() {
    for (final c in [_rate, _transport, _days, _terms, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final q = await ref.read(appDatabaseProvider).supplierQuoteDao.addQuote(
            requestId: widget.request.id,
            supplierId: _supplier,
            rate: _num(_rate.text) ?? 0,
            gstPct: _gst,
            transport: _num(_transport.text) ?? 0,
            deliveryDays: int.tryParse(_days.text.trim()),
            paymentTerms: _terms.text,
            notes: _notes.text,
            by: widget.userId,
          );
      if (mounted) Navigator.pop(context, q);
    } on ArgumentError catch (e) {
      setState(() => _error = tr('${e.message}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate = _num(_rate.text) ?? 0;
    final material = rate * widget.request.quantity;
    final landed = material * (1 + _gst / 100) + (_num(_transport.text) ?? 0);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Add quote'), style: Theme.of(context).textTheme.titleLarge),
          DropdownButtonFormField<String>(
            key: const Key('quote-supplier'),
            initialValue: _supplier,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Supplier')),
            items: [
              for (final s in widget.suppliers)
                DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _supplier = v ?? _supplier),
          ),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('quote-rate'),
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: trf('Rate a {unit} (₹)', {'unit': widget.request.unit.isEmpty ? tr('unit') : widget.request.unit})),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: DropdownButtonFormField<double>(
                initialValue: _gst,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('GST')),
                items: [for (final g in gstChoices) DropdownMenuItem(value: g, child: Text('${fmtQty(g)}%'))],
                onChanged: (v) => setState(() => _gst = v ?? 18),
              ),
            ),
          ]),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('quote-transport'),
                controller: _transport,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tr('Transport (₹)')),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const Key('quote-days'),
                controller: _days,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr('Days to deliver')),
              ),
            ),
          ]),
          TextField(controller: _terms, decoration: InputDecoration(labelText: tr('Payment terms (e.g. 30 days credit)'))),
          TextField(controller: _notes, decoration: InputDecoration(labelText: tr('Note'))),
          if (rate > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(trf('Landed at site: {amount}', {'amount': rupees(landed)}),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: FormMessage(_error!)),
          const SizedBox(height: 12),
          FilledButton(key: const Key('quote-save'), onPressed: _save, child: Text(tr('Save'))),
        ]),
      ),
    );
  }
}
