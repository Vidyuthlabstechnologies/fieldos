/// Who the company owes, and for how long: every supplier with a balance,
/// split into 0-30, 31-60, 61-90 and 90+ days, oldest debts first. A
/// supplier owed for 90 days stops giving credit; this shows that coming.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/features/procurement/supplier_statement.dart';
import 'package:fieldos_mobile/features/procurement/supplier_statement_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

class Payable {
  const Payable(this.supplier, this.ageing);
  final Supplier supplier;
  final Ageing ageing;
}

/// Suppliers with something owed, the longest-owed first.
Future<List<Payable>> loadPayables(AppDatabase db, String companyId, {DateTime? now}) async {
  final at = now ?? DateTime.now();
  final suppliers = await db.supplierDao.forCompany(companyId);
  final sites = await db.projectDao.forCompany(companyId);
  final receipts = <MaterialReceipt>[];
  final orders = <PurchaseOrder>[];
  final expenses = <SiteExpense>[];
  for (final p in sites) {
    receipts.addAll(await db.materialDao.forProject(p.id));
    orders.addAll(await db.purchaseDao.ordersFor(p.id));
    expenses.addAll(await db.expenseDao.forProject(p.id));
  }
  final out = <Payable>[];
  for (final s in suppliers) {
    final lines = supplierStatement(supplier: s, receipts: receipts, orders: orders, expenses: expenses);
    final a = ageStatement(lines, at);
    if (a.total >= 1) out.add(Payable(s, a));
  }
  return out
    ..sort((x, y) {
      final o = y.ageing.over90.compareTo(x.ageing.over90);
      return o != 0 ? o : y.ageing.total.compareTo(x.ageing.total);
    });
}

final payablesProvider = FutureProvider.autoDispose.family<List<Payable>, String>(
    (ref, companyId) => loadPayables(ref.watch(appDatabaseProvider), companyId));

String _bucketLabel(int i) => switch (i) {
      0 => tr('0-30 days'),
      1 => tr('31-60 days'),
      2 => tr('61-90 days'),
      _ => tr('Over 90 days'),
    };

Color _bucketColor(BuildContext context, int i) {
  final scheme = Theme.of(context).colorScheme;
  return switch (i) {
    0 => toneColor(context, PillTone.ok),
    1 => scheme.secondary,
    2 => toneColor(context, PillTone.warn),
    _ => toneColor(context, PillTone.danger),
  };
}

Future<void> openPayables(BuildContext context, String companyId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PayablesScreen(companyId: companyId)));

class PayablesScreen extends ConsumerWidget {
  const PayablesScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(payablesProvider(companyId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Who you owe'))),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(payablesProvider(companyId))),
        data: (rows) {
          if (rows.isEmpty) {
            return MitraEmpty(
              tr('Every supplier is paid up'),
              hint: tr('Deliveries and payments to suppliers show here, oldest debts first.'),
              mood: MitraMood.thumbsUp,
            );
          }
          final totals = List<double>.generate(4, (i) => rows.fold(0.0, (s, r) => s + r.ageing.buckets[i]));
          final total = totals.fold(0.0, (s, v) => s + v);
          return RefreshIndicator(
            onRefresh: () => ref.refresh(payablesProvider(companyId).future),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                Text(tr('Owed to suppliers'), style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(rupees(total), style: theme.textTheme.headlineMedium),
                const SizedBox(height: 10),
                _AgeBar(buckets: totals, height: 14),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  for (var i = 0; i < 4; i++)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _bucketColor(context, i), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('${_bucketLabel(i)} ${rupees(totals[i])}', style: theme.textTheme.bodySmall),
                    ]),
                ]),
                const SizedBox(height: 16),
                for (final r in rows) ...[
                  _PayableCard(row: r, companyId: companyId),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PayableCard extends StatelessWidget {
  const _PayableCard({required this.row, required this.companyId});
  final Payable row;
  final String companyId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = row.ageing;
    final old = a.openingUnpaid
        ? tr('Includes the opening balance')
        : a.oldestDays == null
            ? ''
            : a.oldestDays == 1
                ? tr('Oldest unpaid: 1 day')
                : trf('Oldest unpaid: {n} days', {'n': a.oldestDays!});
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupplierStatementScreen(companyId: companyId, supplierId: row.supplier.id),
        )),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(row.supplier.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
              Text(rupees(a.total), style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            _AgeBar(buckets: a.buckets, height: 8),
            const SizedBox(height: 6),
            Row(children: [
              if (old.isNotEmpty) Expanded(child: Text(old, style: theme.textTheme.bodySmall)),
              if (a.over90 >= 1)
                StatusPill(trf('{amount} over 90 days', {'amount': rupees(a.over90)}), tone: PillTone.danger),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _AgeBar extends StatelessWidget {
  const _AgeBar({required this.buckets, required this.height});
  final List<double> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = buckets.fold(0.0, (s, v) => s + v);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(children: [
          for (var i = 0; i < buckets.length; i++)
            if (buckets[i] > 0)
              Expanded(
                flex: (buckets[i] / (total == 0 ? 1 : total) * 1000).round().clamp(1, 1000),
                child: ColoredBox(color: _bucketColor(context, i)),
              ),
        ]),
      ),
    );
  }
}
