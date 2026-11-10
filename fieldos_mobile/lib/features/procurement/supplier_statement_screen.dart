/// One supplier's statement on screen: what is owed or held as advance,
/// every delivery and payment, the opening balance, and a payment entry
/// that lands on the statement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show addExpense, canSeeMoneyIn, parseAmount;
import 'package:fieldos_mobile/features/portals/portal_share.dart';
import 'package:fieldos_mobile/features/procurement/supplier_statement.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class _Data {
  _Data(this.supplier, this.lines, this.sites);
  final Supplier supplier;
  final List<StatementLine> lines;
  final List<Project> sites;
}

final _statementProvider = FutureProvider.autoDispose.family<_Data, (String, String)>((ref, key) async {
  final (companyId, supplierId) = key;
  final db = ref.watch(appDatabaseProvider);
  final supplier = (await db.supplierDao.forCompany(companyId)).firstWhere((s) => s.id == supplierId);
  final sites = await db.projectDao.forCompany(companyId);
  final receipts = <MaterialReceipt>[];
  final orders = <PurchaseOrder>[];
  final expenses = <SiteExpense>[];
  for (final p in sites) {
    receipts.addAll(await db.materialDao.forProject(p.id));
    orders.addAll(await db.purchaseDao.ordersFor(p.id));
    expenses.addAll(await db.expenseDao.forProject(p.id));
  }
  return _Data(
    supplier,
    supplierStatement(
      supplier: supplier,
      receipts: receipts,
      orders: orders,
      expenses: expenses,
      siteName: {for (final p in sites) p.id: p.name},
    ),
    sites,
  );
});

class SupplierStatementScreen extends ConsumerWidget {
  const SupplierStatementScreen({super.key, required this.companyId, required this.supplierId});
  final String companyId;
  final String supplierId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_statementProvider((companyId, supplierId)));
    final session = ref.watch(sessionProvider);
    final canEdit = canSeeMoneyIn(session.role);
    final theme = Theme.of(context);
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: ErrorState(error: e, stack: st)),
      data: (d) {
        final balance = d.lines.isEmpty ? 0.0 : d.lines.last.balance;
        final (word, tone) = balance.abs() < 0.005
            ? (tr('Settled'), PillTone.ok)
            : balance > 0
                ? (trf('You owe {amount}', {'amount': rupees(balance, paise: true)}), PillTone.warn)
                : (trf('Advance with them {amount}', {'amount': rupees(-balance, paise: true)}), PillTone.neutral);
        return Scaffold(
          appBar: AppBar(title: Text(d.supplier.name), actions: [
            if (Roles.canApprove(session.role))
              IconButton(
                key: const Key('supplier-app-access'),
                tooltip: tr('App access for the supplier'),
                icon: const Icon(Icons.phonelink_lock_outlined),
                onPressed: () => shareSupplierAccess(context, ref, d.supplier),
              ),
            if (d.lines.isNotEmpty)
              IconButton(
                tooltip: tr('Send statement'),
                icon: const Icon(Icons.share),
                onPressed: () => SharePlus.instance.share(ShareParams(
                    text: statementText(d.supplier, d.lines, companyName: session.activeCompany?.name ?? 'FieldOS'))),
              ),
          ]),
          floatingActionButton: d.sites.isEmpty
              ? null
              : FloatingActionButton.extended(
                  key: const Key('supplier-pay'),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(tr('Record payment')),
                  onPressed: () => _pay(context, ref, d),
                ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  StatusPill(word, tone: tone),
                  const SizedBox(height: 8),
                  Text(
                    trf('Opening balance: {amount}', {'amount': rupees(d.supplier.openingBalance ?? 0, paise: true)}),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (canEdit)
                    TextButton(
                      key: const Key('supplier-opening'),
                      onPressed: () => _setOpening(context, ref, d.supplier),
                      child: Text(tr('Set opening balance')),
                    ),
                ]),
              ),
            ),
            if (d.lines.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  tr('Deliveries from this supplier and payments made to them appear here. Pick them as "Paid to" when you add an expense.'),
                  textAlign: TextAlign.center,
                ),
              ),
            for (final l in d.lines.reversed)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(switch (l.kind) {
                  StatementKind.opening => Icons.flag_outlined,
                  StatementKind.delivery => Icons.local_shipping_outlined,
                  StatementKind.payment => Icons.payments_outlined,
                }),
                title: Text(l.kind == StatementKind.opening ? tr('Opening balance') : l.label),
                subtitle: Text([
                  if (l.on != null) fmtDate(l.on!, short: true),
                  if (l.reference != null) l.reference!,
                  if (l.site != null) l.site!,
                ].join(' · ')),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${l.amount >= 0 ? '+' : '−'}${rupees(l.amount.abs(), paise: true)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: l.amount < 0 ? toneColor(context, PillTone.ok) : null)),
                  Text(rupees(l.balance, paise: true), style: theme.textTheme.bodySmall),
                ]),
              ),
          ]),
        );
      },
    );
  }

  Future<void> _setOpening(BuildContext context, WidgetRef ref, Supplier s) async {
    final c = TextEditingController(text: s.openingBalance == null ? '' : s.openingBalance!.abs().toString());
    var advance = (s.openingBalance ?? 0) < 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Opening balance')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('What stood with this supplier before you started using FieldOS.'), style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(tr('We owe them'))),
                ButtonSegment(value: true, label: Text(tr('Advance with them'))),
              ],
              selected: {advance},
              onSelectionChanged: (v) => set(() => advance = v.first),
            ),
            TextField(
              key: const Key('opening-amount'),
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Amount (₹)')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('opening-amount-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = c.text.trim().isEmpty ? 0.0 : parseAmount(c.text);
    if (v == null) return;
    final amount = (v * 100).roundToDouble() / 100;
    await ref.read(appDatabaseProvider).supplierDao.edit(
        s.id, SuppliersCompanion(openingBalance: Value(amount == 0 ? null : (advance ? -amount : amount))));
    ref.invalidate(_statementProvider((companyId, supplierId)));
  }

  Future<void> _pay(BuildContext context, WidgetRef ref, _Data d) async {
    var site = d.sites.length == 1 ? d.sites.first : null;
    site ??= await showDialog<Project>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Paid from which site?')),
        children: [
          for (final p in d.sites) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, p), child: Text(p.name)),
        ],
      ),
    );
    if (site == null || !context.mounted) return;
    final saved = await addExpense(context, ref,
        projectId: site.id,
        userId: ref.read(sessionProvider).user?.id ?? '',
        category: 'Material',
        paidTo: d.supplier.name);
    if (saved) ref.invalidate(_statementProvider((companyId, supplierId)));
  }
}
