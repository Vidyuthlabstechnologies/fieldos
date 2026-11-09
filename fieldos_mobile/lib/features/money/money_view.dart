/// Site money: every rupee spent on site (petty cash, labour, transport,
/// hire...) and, for owners and project managers, every rupee received from
/// the client, with the site's balance at the top. Expenses tagged to a
/// worker are their wages or advances and show on the wage sheet.
///
/// The money book (v10) answers what Onsite customers ask for in their
/// Play reviews: voucher numbers and a printable voucher, GST worked out,
/// the company's own categories, filters with the filtered total and its
/// Excel, a breakdown by category, and corrections that keep a trail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'dart:io';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/data_export.dart' show exportFileName;
import 'package:fieldos_mobile/features/export/xlsx_writer.dart';
import 'package:fieldos_mobile/features/money/bills_view.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/money/expense_bills.dart';
import 'package:fieldos_mobile/features/money/voucher_pdf.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart' show CapturedFile;
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

const paymentModes = {'cash': 'Cash', 'upi': 'UPI', 'bank': 'Bank transfer', 'cheque': 'Cheque'};

/// Expenses that count (cancelled ones left out), for totals elsewhere.
final expensesProvider = FutureProvider.autoDispose.family<List<SiteExpense>, String>((ref, projectId) async {
  final rows = await ref.watch(appDatabaseProvider).expenseDao.forProject(projectId);
  rows.sort((a, b) => b.incurredOn.compareTo(a.incurredOn) != 0
      ? b.incurredOn.compareTo(a.incurredOn)
      : b.createdAt.compareTo(a.createdAt));
  return rows;
});

/// Every expense of the site, cancelled ones too, for the money book.
final moneyBookExpensesProvider = FutureProvider.autoDispose.family<List<SiteExpense>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).expenseDao.allForProject(projectId));

final paymentsReceivedProvider = FutureProvider.autoDispose.family<List<PaymentsReceivedData>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).paymentDao.forProject(projectId));

final moneyBookPaymentsProvider = FutureProvider.autoDispose.family<List<PaymentsReceivedData>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).paymentDao.allForProject(projectId));

/// The company's categories (defaults, its own, and any used on the site).
final expenseCategoriesProvider = FutureProvider.autoDispose.family<List<String>, String>((ref, projectId) async {
  final db = ref.watch(appDatabaseProvider);
  final companyId = ref.watch(sessionProvider).activeCompany?.id;
  final custom = companyId == null ? const <String>[] : await loadCustomCategories(db, companyId);
  return categoriesToOffer(custom: custom, used: await db.expenseDao.allForProject(projectId));
});

String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "6 Nov 2026", like every other date in the app.
String shortDay(DateTime d) => fmtDate(d);

bool canSeeMoneyIn(String? role) => role == Roles.owner || role == Roles.manager;

/// Whoever wrote an entry may correct or cancel it; so may the owner and
/// project managers (the cloud enforces the same rule).
bool canCorrect({required String? role, required String recordedBy, required String userId}) =>
    recordedBy == userId || role == Roles.owner || role == Roles.manager;

void _refreshMoney(WidgetRef ref, String projectId) {
  ref.invalidate(expensesProvider(projectId));
  ref.invalidate(moneyBookExpensesProvider(projectId));
  ref.invalidate(paymentsReceivedProvider(projectId));
  ref.invalidate(moneyBookPaymentsProvider(projectId));
  ref.invalidate(expenseCategoriesProvider(projectId));
  ref.invalidate(expenseBillCountsProvider(projectId));
}

IconData _iconFor(String c) => switch (c) {
      'Material' => Icons.inventory_2,
      'Labour' => Icons.engineering,
      'Transport' => Icons.local_shipping,
      'Equipment hire' => Icons.construction,
      'Food & tea' => Icons.local_cafe,
      'Fuel' => Icons.local_gas_station,
      _ => Icons.receipt_long,
    };

String _periodLabel(MoneyPeriod p) => switch (p) {
      MoneyPeriod.all => tr('All dates'),
      MoneyPeriod.thisWeek => tr('This week'),
      MoneyPeriod.thisMonth => tr('This month'),
      MoneyPeriod.lastMonth => tr('Last month'),
      MoneyPeriod.custom => tr('Pick dates'),
    };

class MoneyView extends ConsumerWidget {
  const MoneyView({super.key, required this.projectId, required this.userId, this.project});
  final String projectId;
  final String userId;

  /// Needed for the Bills tab (owners and project managers only) and the
  /// site name on vouchers.
  final Project? project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider).role;
    final showIn = canSeeMoneyIn(role);
    final showBills = showIn && project != null;
    final expenses = ref.watch(expensesProvider(projectId));
    final received = showIn ? ref.watch(paymentsReceivedProvider(projectId)) : const AsyncValue.data(<PaymentsReceivedData>[]);

    final spent = expenses.value?.fold<double>(0, (s, e) => s + e.amount) ?? 0;
    final inTotal = received.value?.fold<double>(0, (s, p) => s + p.amount) ?? 0;

    return DefaultTabController(
      length: 1 + (showIn ? 1 : 0) + (showBills ? 1 : 0),
      child: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (showIn) _Figure(tr('Received'), rupees(inTotal), toneColor(context, PillTone.ok)),
                  _Figure(tr('Spent'), rupees(spent), toneColor(context, PillTone.danger)),
                  if (showIn)
                    _Figure(tr('Balance'), rupees(inTotal - spent),
                        inTotal - spent < 0 ? toneColor(context, PillTone.danger) : Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
          TabBar(tabs: [
            Tab(text: tr('Spent')),
            if (showIn) Tab(text: tr('Received')),
            if (showBills) Tab(text: tr('Bills')),
          ]),
          Expanded(
            child: TabBarView(children: [
              _SpentTab(projectId: projectId, userId: userId, project: project),
              if (showIn) _ReceivedTab(projectId: projectId, userId: userId, project: project),
              if (showBills) BillsView(project: project!, userId: userId),
            ]),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spent
// ---------------------------------------------------------------------------

class _SpentTab extends ConsumerStatefulWidget {
  const _SpentTab({required this.projectId, required this.userId, this.project});
  final String projectId;
  final String userId;
  final Project? project;

  @override
  ConsumerState<_SpentTab> createState() => _SpentTabState();
}

class _SpentTabState extends ConsumerState<_SpentTab> {
  var _filter = const MoneyFilter();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickPeriod() async {
    final picked = await showModalBottomSheet<MoneyPeriod>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final p in MoneyPeriod.values)
            ListTile(
              title: Text(_periodLabel(p)),
              trailing: p == _filter.period ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == MoneyPeriod.custom) {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year, now.month, now.day),
        initialDateRange: _filter.from != null && _filter.to != null
            ? DateTimeRange(start: _filter.from!, end: _filter.to!)
            : null,
      );
      if (range == null || !mounted) return;
      setState(() => _filter = _filter.copyWith(period: MoneyPeriod.custom, from: range.start, to: range.end));
    } else {
      setState(() => _filter = _filter.copyWith(period: picked));
    }
  }

  String _periodChip() {
    if (_filter.period != MoneyPeriod.custom) return _periodLabel(_filter.period);
    final f = _filter.from, t = _filter.to;
    return f == null || t == null ? _periodLabel(MoneyPeriod.custom) : '${fmtDate(f, short: true)} – ${fmtDate(t, short: true)}';
  }

  Future<void> _pickCategory(List<String> categories) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: Text(tr('All categories')),
            trailing: _filter.category == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final c in categories)
            ListTile(
              leading: Icon(_iconFor(c)),
              title: Text(tr(c)),
              trailing: c == _filter.category ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(category: picked.isEmpty ? null : picked));
  }

  Future<void> _pickWorker(List<Worker> workers) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: Text(tr('Everyone')),
            trailing: _filter.workerId == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final w in workers)
            ListTile(
              title: Text(w.name),
              subtitle: w.role == null ? null : Text(w.role!),
              trailing: w.id == _filter.workerId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, w.id),
            ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _filter = _filter.copyWith(workerId: picked.isEmpty ? null : picked));
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(moneyBookExpensesProvider(widget.projectId));
    final workers = ref.watch(workersProvider(widget.projectId)).value ?? const <Worker>[];
    final workerName = {for (final w in workers) w.id: w.name};
    final categories = ref.watch(expenseCategoriesProvider(widget.projectId)).value ?? defaultExpenseCategories;
    final theme = Theme.of(context);

    return Stack(children: [
      rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          final shown = _filter.expenses(all, workerName: workerName);
          final total = totalOf(shown);
          final cancelled = shown.where((e) => e.voided).length;
          final billCounts = ref.watch(expenseBillCountsProvider(widget.projectId)).value ?? const {};
          return Column(children: [
            if (all.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: TextField(
                  key: const Key('money-search'),
                  controller: _search,
                  onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v)),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Search note, paid to, voucher no.'),
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: tr('Clear'),
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() {
                              _search.clear();
                              _filter = _filter.copyWith(query: '');
                            }),
                          ),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  _FilterChip(
                    key: const Key('money-filter-period'),
                    icon: Icons.date_range,
                    label: _periodChip(),
                    active: _filter.period != MoneyPeriod.all,
                    onTap: _pickPeriod,
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    key: const Key('money-filter-category'),
                    icon: Icons.category_outlined,
                    label: _filter.category == null ? tr('All categories') : tr(_filter.category!),
                    active: _filter.category != null,
                    onTap: () => _pickCategory(categories),
                  ),
                  if (workers.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _FilterChip(
                      icon: Icons.person_outline,
                      label: _filter.workerId == null ? tr('Everyone') : (workerName[_filter.workerId] ?? tr('Worker')),
                      active: _filter.workerId != null,
                      onTap: () => _pickWorker(workers),
                    ),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 0),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      key: const Key('money-filtered-total'),
                      shown.length - cancelled == 1
                          ? trf('1 entry · {total}', {'total': rupees(total, paise: true)})
                          : trf('{n} entries · {total}', {'n': shown.length - cancelled, 'total': rupees(total, paise: true)}),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (!_filter.isEmpty) TextButton(onPressed: _clearFilters, child: Text(tr('Clear filters'))),
                  IconButton(
                    key: const Key('money-breakdown'),
                    tooltip: tr('Breakdown by category'),
                    icon: const Icon(Icons.bar_chart),
                    onPressed: shown.isEmpty ? null : () => _showBreakdown(context, shown),
                  ),
                  IconButton(
                    key: const Key('money-excel'),
                    tooltip: tr('Export this list to Excel'),
                    icon: const Icon(Icons.table_view_outlined),
                    onPressed: shown.isEmpty
                        ? null
                        : () => _exportExpenses(context, shown, workerName: workerName, siteName: widget.project?.name),
                  ),
                ]),
              ),
            ],
            Expanded(
              child: all.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('No expenses yet. Tap + to add petty cash, labour, transport and more.'),
                            textAlign: TextAlign.center),
                      ),
                    )
                  : shown.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text(tr('Nothing matches these filters.'), textAlign: TextAlign.center),
                              const SizedBox(height: 8),
                              OutlinedButton(onPressed: _clearFilters, child: Text(tr('Clear filters'))),
                            ]),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 80),
                          children: [
                            for (final e in shown)
                              _ExpenseTile(
                                expense: e,
                                bills: billCounts[e.id] ?? 0,
                                workerName: e.workerId == null ? null : workerName[e.workerId],
                                onTap: () => _openExpense(context, e, workerName: workerName),
                              ),
                          ],
                        ),
            ),
          ]);
        },
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'Add expense',
          onPressed: () => addExpense(context, ref, projectId: widget.projectId, userId: widget.userId),
          icon: const Icon(Icons.add),
          label: Text(tr('Add expense')),
        ),
      ),
    ]);
  }

  void _clearFilters() => setState(() {
        _search.clear();
        _filter = const MoneyFilter();
      });

  Future<void> _openExpense(BuildContext context, SiteExpense e, {required Map<String, String> workerName}) async {
    final session = ref.read(sessionProvider);
    final users = await ref.read(appDatabaseProvider).select(ref.read(appDatabaseProvider).users).get();
    final userName = {for (final u in users) u.id: u.name};
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ExpenseSheet(
        expense: e,
        workerName: e.workerId == null ? null : workerName[e.workerId],
        enteredBy: userName[e.recordedBy],
        editedBy: e.editedBy == null ? null : userName[e.editedBy],
        canCorrect: canCorrect(role: session.role, recordedBy: e.recordedBy, userId: widget.userId),
        onVoucher: () async => shareVoucher(
          expense: e,
          companyName: session.activeCompany?.name ?? 'FieldOS',
          siteName: widget.project?.name ?? '',
          workerName: e.workerId == null ? null : workerName[e.workerId],
          enteredBy: userName[e.recordedBy],
          branding: await loadBranding(ref.read(appDatabaseProvider), session.activeCompany?.id),
        ),
        onEdit: () async {
          Navigator.pop(ctx);
          await addExpense(context, ref, projectId: widget.projectId, userId: widget.userId, existing: e);
        },
        onCancel: () async {
          Navigator.pop(ctx);
          await _cancelOrRestore(context, e);
        },
      ),
    );
  }

  Future<void> _cancelOrRestore(BuildContext context, SiteExpense e) async {
    final db = ref.read(appDatabaseProvider);
    if (e.voided) {
      await db.expenseDao.setVoided(e.id, voided: false, by: widget.userId);
      _refreshMoney(ref, widget.projectId);
      if (context.mounted) showSnack(context, 'Entry restored.');
      return;
    }
    final reason = await _askReason(context, title: tr('Cancel this entry?'));
    if (reason == null) return;
    await db.expenseDao.setVoided(e.id, voided: true, reason: reason, by: widget.userId);
    _refreshMoney(ref, widget.projectId);
    if (context.mounted) showSnack(context, 'Entry cancelled. It stays in the list, struck through.');
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({super.key, required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
        avatar: Icon(icon, size: 18),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
        selected: active,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      );
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.onTap, this.workerName, this.bills = 0});
  final SiteExpense expense;
  final int bills;
  final String? workerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final strike = e.voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    final who = workerName ?? e.paidTo;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(child: Icon(_iconFor(e.category), size: 20)),
      title: Text('${tr(e.category)}${who == null || who.isEmpty ? '' : ' · $who'}', style: strike),
      subtitle: Text([
        if (e.voucherNo != null) voucherLabel(e.voucherNo),
        shortDay(expenseDay(e)),
        if (e.mode != null) tr(paymentModes[e.mode] ?? e.mode!),
        if ((e.gstPct ?? 0) > 0) 'GST ${_rate(e.gstPct!)}%',
        if (e.voided) tr('Cancelled'),
        if (e.note != null && e.note!.isNotEmpty) e.note!,
      ].join(' · ')),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (bills > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              label: bills == 1 ? tr('1 bill attached') : trf('{n} bills attached', {'n': '$bills'}),
              child: Icon(Icons.attach_file, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        Text(rupees(e.amount),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              decoration: e.voided ? TextDecoration.lineThrough : null,
              color: e.voided ? Theme.of(context).colorScheme.onSurfaceVariant : null,
            )),
      ]),
    );
  }
}

String _rate(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _ExpenseSheet extends StatelessWidget {
  const _ExpenseSheet({
    required this.expense,
    required this.canCorrect,
    required this.onVoucher,
    required this.onEdit,
    required this.onCancel,
    this.workerName,
    this.enteredBy,
    this.editedBy,
  });

  final SiteExpense expense;
  final String? workerName;
  final String? enteredBy;
  final String? editedBy;
  final bool canCorrect;
  final VoidCallback onVoucher;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final theme = Theme.of(context);
    final gst = (e.gstPct ?? 0) > 0 ? gstSplit(e.amount, e.gstPct!, interState: e.gstInterState) : null;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(label, style: theme.textTheme.bodySmall)),
            Expanded(child: Text(value)),
          ]),
        );
    final payee = voucherPayee(e, workerName: workerName);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                [if (e.voucherNo != null) voucherLabel(e.voucherNo), tr(e.category)].join(' · '),
                style: theme.textTheme.titleLarge,
              ),
            ),
            if (e.voided) StatusPill(tr('Cancelled'), tone: PillTone.danger),
          ]),
          const SizedBox(height: 4),
          Text(rupees(e.amount, paise: true),
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700, decoration: e.voided ? TextDecoration.lineThrough : null)),
          const SizedBox(height: 8),
          row(tr('Date'), shortDay(expenseDay(e))),
          if (payee.isNotEmpty) row(tr('Paid to'), payee),
          if (e.mode != null) row(tr('Paid by'), tr(paymentModes[e.mode] ?? e.mode!)),
          if (gst != null) ...[
            row(tr('Before GST'), rupees(gst.taxable, paise: true)),
            if (gst.igst > 0)
              row('IGST ${_rate(e.gstPct!)}%', rupees(gst.igst, paise: true))
            else
              row('CGST + SGST ${_rate(e.gstPct!)}%',
                  '${rupees(gst.cgst, paise: true)} + ${rupees(gst.sgst, paise: true)}'),
          ],
          if (e.note != null && e.note!.isNotEmpty) row(tr('Note'), e.note!),
          if (enteredBy != null) row(tr('Entered by'), enteredBy!),
          if (e.editedAt != null)
            row(tr('Last changed'), [fmtDateTime(e.editedAt!), ?editedBy].join(' · ')),
          if (e.voided && e.voidReason != null) row(tr('Why cancelled'), e.voidReason!),
          ExpenseBills(
            expense: e,
            canChange: canCorrect && !e.voided,
            shareText: [if (e.voucherNo != null) voucherLabel(e.voucherNo), tr(e.category), rupees(e.amount, paise: true)]
                .join(' · '),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
              key: const Key('expense-voucher'),
              onPressed: onVoucher,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(tr('Voucher PDF')),
            ),
            if (canCorrect && !e.voided)
              OutlinedButton.icon(
                key: const Key('expense-edit'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: Text(tr('Edit')),
              ),
            if (canCorrect)
              OutlinedButton.icon(
                key: const Key('expense-cancel'),
                onPressed: onCancel,
                icon: Icon(e.voided ? Icons.undo : Icons.block),
                label: Text(e.voided ? tr('Restore entry') : tr('Cancel entry')),
              ),
          ]),
          if (!canCorrect) ...[
            const SizedBox(height: 8),
            Text(tr('Only the person who entered this, the owner or a project manager can change it.'),
                style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context, {required String title}) async {
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('It stays in the list, struck through, and counts in no total. You can restore it later.')),
        const SizedBox(height: 8),
        TextField(
          key: const Key('cancel-reason'),
          controller: c,
          autofocus: true,
          maxLength: 200,
          decoration: InputDecoration(labelText: tr('Reason (e.g. entered twice)')),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep it'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cancel entry'))),
      ],
    ),
  );
  if (ok != true) return null;
  return c.text.trim();
}

void _showBreakdown(BuildContext context, List<SiteExpense> shown) {
  final parts = categoryBreakdown(shown);
  final total = totalOf(shown);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Where the money went'), style: theme.textTheme.titleLarge),
            Text(trf('{total} across {n} categories', {'total': rupees(total), 'n': parts.length}),
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            for (final c in parts) _BreakdownBar(part: c),
          ]),
        ),
      );
    },
  );
}

class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({required this.part});
  final CategoryShare part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (part.share * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_iconFor(part.category), size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(part.category), style: theme.textTheme.titleSmall)),
          Text(rupees(part.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(width: 48, child: Text('$pct%', textAlign: TextAlign.right, style: theme.textTheme.bodySmall)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: part.share.clamp(0.0, 1.0),
            minHeight: 10,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ]),
    );
  }
}

/// The filtered list as its own Excel file, with the total at the bottom.
Future<void> _exportExpenses(BuildContext context, List<SiteExpense> shown,
    {required Map<String, String> workerName, String? siteName}) async {
  try {
    final rows = <List<Object?>>[
      for (final e in shown)
        () {
          final gst = (e.gstPct ?? 0) > 0 ? gstSplit(e.amount, e.gstPct!, interState: e.gstInterState) : null;
          return <Object?>[
            voucherLabel(e.voucherNo),
            expenseDay(e),
            e.category,
            e.workerId != null ? workerName[e.workerId] : e.paidTo,
            paymentModes[e.mode],
            e.voided ? 0.0 : e.amount,
            gst?.taxable,
            gst?.tax,
            e.gstPct,
            e.note,
            e.voided ? 'Cancelled${e.voidReason == null ? '' : ': ${e.voidReason}'}' : null,
          ];
        }(),
      [null, null, null, null, 'Total', totalOf(shown)],
    ];
    final bytes = buildXlsx([
      XlsxSheet('Money spent', [
        'Voucher', 'Date', 'Category', 'Paid to', 'Paid by', 'Amount (₹)', 'Before GST (₹)', 'GST (₹)', 'GST %',
        'Note', 'Status',
      ], rows),
    ]);
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, exportFileName('${siteName ?? 'Site'} money spent', DateTime.now())));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: '${siteName ?? 'Site'}: money spent',
    ));
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}

// ---------------------------------------------------------------------------
// Received
// ---------------------------------------------------------------------------

class _ReceivedTab extends ConsumerStatefulWidget {
  const _ReceivedTab({required this.projectId, required this.userId, this.project});
  final String projectId;
  final String userId;
  final Project? project;

  @override
  ConsumerState<_ReceivedTab> createState() => _ReceivedTabState();
}

class _ReceivedTabState extends ConsumerState<_ReceivedTab> {
  var _filter = const MoneyFilter();

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(moneyBookPaymentsProvider(widget.projectId));
    return Stack(children: [
      rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (all) {
          final shown = _filter.payments(all);
          return Column(children: [
            if (all.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  _FilterChip(
                    icon: Icons.date_range,
                    label: _periodLabel(_filter.period),
                    active: _filter.period != MoneyPeriod.all,
                    onTap: () async {
                      final picked = await showModalBottomSheet<MoneyPeriod>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            for (final p in MoneyPeriod.values.where((p) => p != MoneyPeriod.custom))
                              ListTile(
                                title: Text(_periodLabel(p)),
                                trailing: p == _filter.period ? const Icon(Icons.check) : null,
                                onTap: () => Navigator.pop(ctx, p),
                              ),
                          ]),
                        ),
                      );
                      if (picked != null && mounted) setState(() => _filter = _filter.copyWith(period: picked));
                    },
                  ),
                  const Spacer(),
                  Text(
                    trf('{n} entries · {total}', {
                      'n': shown.where((p) => !p.voided).length,
                      'total': rupees(totalReceived(shown), paise: true),
                    }),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ]),
              ),
            Expanded(
              child: all.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(tr('Record each payment the client makes (running bills, advances).'),
                            textAlign: TextAlign.center),
                      ),
                    )
                  : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                      for (final pay in shown)
                        ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.call_received, size: 20)),
                          title: Text(pay.fromParty,
                              style: pay.voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                          subtitle: Text([
                            shortDay(pay.receivedOn),
                            tr(paymentModes[pay.mode] ?? pay.mode),
                            if (pay.voided) tr('Cancelled'),
                            if (pay.note != null) pay.note!,
                          ].join(' · ')),
                          trailing: Text(rupees(pay.amount),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: pay.voided ? null : toneColor(context, PillTone.ok),
                                decoration: pay.voided ? TextDecoration.lineThrough : null,
                              )),
                          onTap: () => _openPayment(context, pay),
                        ),
                    ]),
            ),
          ]);
        },
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'Add payment received',
          onPressed: () => _editReceived(context),
          icon: const Icon(Icons.add),
          label: Text(tr('Add payment received')),
        ),
      ),
    ]);
  }

  Future<void> _openPayment(BuildContext context, PaymentsReceivedData pay) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(pay.fromParty, style: Theme.of(ctx).textTheme.titleMedium),
            subtitle: Text('${rupees(pay.amount, paise: true)} · ${shortDay(pay.receivedOn)}'
                '${pay.voided && pay.voidReason != null ? '\n${tr('Why cancelled')}: ${pay.voidReason}' : ''}'),
          ),
          if (!pay.voided)
            ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(tr('Edit')),
                onTap: () => Navigator.pop(ctx, 'edit')),
          ListTile(
            leading: Icon(pay.voided ? Icons.undo : Icons.block),
            title: Text(pay.voided ? tr('Restore entry') : tr('Cancel entry')),
            onTap: () => Navigator.pop(ctx, 'cancel'),
          ),
        ]),
      ),
    );
    if (!context.mounted || choice == null) return;
    final db = ref.read(appDatabaseProvider);
    if (choice == 'edit') {
      await _editReceived(context, existing: pay);
    } else if (pay.voided) {
      await db.paymentDao.setVoided(pay.id, voided: false, by: widget.userId);
      _refreshMoney(ref, widget.projectId);
    } else {
      final reason = await _askReason(context, title: tr('Cancel this entry?'));
      if (reason == null) return;
      await db.paymentDao.setVoided(pay.id, voided: true, reason: reason, by: widget.userId);
      _refreshMoney(ref, widget.projectId);
    }
  }

  Future<void> _editReceived(BuildContext context, {PaymentsReceivedData? existing}) async {
    final amount = TextEditingController(text: existing == null ? '' : _plain(existing.amount));
    final party = TextEditingController(text: existing?.fromParty ?? '');
    final note = TextEditingController(text: existing?.note ?? '');
    var mode = existing?.mode ?? 'bank';
    var on = existing?.receivedOn ?? DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? tr('Payment received') : tr('Edit payment received')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: party,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('From (client name)'))),
              TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Amount (₹)'))),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: InputDecoration(labelText: tr('Paid by')),
                items: [for (final m in paymentModes.entries) DropdownMenuItem(value: m.key, child: Text(tr(m.value)))],
                onChanged: (v) => set(() => mode = v ?? mode),
              ),
              _DateRow(value: on, onChanged: (d) => set(() => on = d)),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (e.g. RA bill 3)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    final value = parseAmount(amount.text);
    if (ok != true || value == null || value <= 0 || party.text.trim().isEmpty) return;
    final db = ref.read(appDatabaseProvider);
    final n = note.text.trim();
    if (existing == null) {
      await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: const Uuid().v4(),
        projectId: widget.projectId,
        amount: value,
        receivedOn: on,
        fromParty: _cut(party.text.trim(), 120),
        mode: mode,
        recordedBy: widget.userId,
        note: Value(n.isEmpty ? null : _cut(n, 300)),
      ));
    } else {
      await db.paymentDao.edit(
        existing.id,
        PaymentsReceivedCompanion(
          amount: Value(value),
          receivedOn: Value(on),
          fromParty: Value(_cut(party.text.trim(), 120)),
          mode: Value(mode),
          note: Value(n.isEmpty ? null : _cut(n, 300)),
        ),
        by: widget.userId,
      );
    }
    _refreshMoney(ref, widget.projectId);
  }
}

String _cut(String s, int max) => s.length > max ? s.substring(0, max) : s;

/// "1,250.50" or "1250.5" typed in a money field; null when it isn't a number.
double? parseAmount(String typed) {
  final v = double.tryParse(typed.trim().replaceAll(',', '').replaceAll('₹', '').trim());
  if (v == null || v.isNaN || v.isInfinite) return null;
  return (v * 100).roundToDouble() / 100;
}

/// An amount as typed back into a field: "1250", "1250.5".
String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

// ---------------------------------------------------------------------------
// Add or edit an expense
// ---------------------------------------------------------------------------

/// Add-expense dialog, also used by the wage sheet's "Pay" button (with
/// [category] Labour and [workerId] preset), and to correct an entry
/// ([existing]). Returns true when saved.
Future<bool> addExpense(BuildContext context, WidgetRef ref,
    {required String projectId,
    required String userId,
    String? category,
    String? workerId,
    double? suggestedAmount,
    String? note,
    String? paidTo,
    SiteExpense? existing}) async {
  final db = ref.read(appDatabaseProvider);
  final companyId = ref.read(sessionProvider).activeCompany?.id;
  final amount = TextEditingController(
      text: existing != null
          ? _plain(existing.amount)
          : suggestedAmount == null
              ? ''
              : _plain((suggestedAmount * 100).roundToDouble() / 100));
  final noteC = TextEditingController(text: existing?.note ?? note ?? '');
  final paidToC = TextEditingController(text: existing?.paidTo ?? paidTo ?? '');
  // Suppliers to pick as "Paid to", so payments land on their statement.
  final supplierNames = companyId == null
      ? const <String>[]
      : [for (final s in await db.supplierDao.forCompany(companyId)) s.name];
  var categories = await ref.read(expenseCategoriesProvider(projectId).future);
  var cat = existing?.category ?? category ?? categories.first;
  if (!categories.contains(cat)) categories = [cat, ...categories];
  String? worker = existing?.workerId ?? workerId;
  var on = existing == null ? DateTime.now() : expenseDay(existing);
  var mode = existing?.mode ?? 'cash';
  var gst = existing?.gstPct ?? 0.0;
  var interState = existing?.gstInterState ?? false;
  var includesGst = true;
  // Bills picked before the expense exists; kept with it once saved.
  final bills = <CapturedFile>[];
  final workers = (await ref.read(workersProvider(projectId).future))
      .where((w) => w.status == 'active' || w.id == worker)
      .toList();
  if (!context.mounted) return false;

  Future<void> newCategory(StateSetter set) async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('New category')),
        content: TextField(
          key: const Key('new-category-name'),
          controller: c,
          autofocus: true,
          maxLength: 50,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Name (e.g. Electrician, Plumber, Shuttering hire)')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('Add'))),
        ],
      ),
    );
    if (name == null || companyId == null) return;
    final saved = await addCustomCategory(db, companyId, name);
    final pick = saved ?? categories.firstWhere((x) => x.toLowerCase() == name.trim().toLowerCase(), orElse: () => cat);
    ref.invalidate(expenseCategoriesProvider(projectId));
    set(() {
      if (saved != null) categories = [...categories.where((x) => x != 'Other'), saved, 'Other'];
      cat = pick;
    });
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final typed = parseAmount(amount.text) ?? 0;
        final total = gst > 0 && !includesGst ? withGst(typed, gst) : typed;
        final split = gst > 0 && total > 0 ? gstSplit(total, gst, interState: interState) : null;
        final muted = Theme.of(ctx).textTheme.bodySmall;
        return AlertDialog(
          title: Text(existing != null
              ? trf('Edit {voucher}', {'voucher': voucherLabel(existing.voucherNo)})
              : workerId != null
                  ? tr('Pay worker')
                  : tr('Add expense')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final c in categories)
                  ChoiceChip(label: Text(tr(c)), selected: cat == c, onSelected: (_) => set(() => cat = c)),
                if (companyId != null)
                  ActionChip(
                    key: const Key('expense-new-category'),
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(tr('New category')),
                    onPressed: () => newCategory(set),
                  ),
              ]),
              TextField(
                key: const Key('expense-amount'),
                controller: amount,
                autofocus: existing == null,
                onChanged: (_) => set(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: gst > 0 && !includesGst ? tr('Amount before GST (₹)') : tr('Amount (₹)')),
              ),
              if (cat == 'Labour' && workers.isNotEmpty)
                DropdownButtonFormField<String?>(
                  initialValue: worker,
                  decoration: InputDecoration(labelText: tr('Paid to (for wages or an advance)')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(tr('Not one worker'))),
                    for (final w in workers) DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (v) => set(() => worker = v),
                ),
              if (!(cat == 'Labour' && worker != null))
                TextField(
                  key: const Key('expense-paid-to'),
                  controller: paidToC,
                  onChanged: (_) => set(() {}),
                  textCapitalization: TextCapitalization.words,
                  maxLength: 120,
                  decoration: InputDecoration(labelText: tr('Paid to (shop, driver, person)'), counterText: ''),
                ),
              if (!(cat == 'Labour' && worker != null))
                () {
                  final typed = paidToC.text.trim().toLowerCase();
                  final matches = supplierNames
                      .where((n) => n.toLowerCase() != typed && (typed.isEmpty || n.toLowerCase().contains(typed)))
                      .take(4)
                      .toList();
                  if (matches.isEmpty || (typed.isEmpty && supplierNames.length > 6)) return const SizedBox.shrink();
                  return Wrap(spacing: 6, children: [
                    for (final n in matches)
                      ActionChip(
                        avatar: const Icon(Icons.storefront_outlined, size: 16),
                        label: Text(n),
                        onPressed: () => set(() => paidToC.text = n),
                      ),
                  ]);
                }(),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: InputDecoration(labelText: tr('Paid by')),
                items: [for (final m in paymentModes.entries) DropdownMenuItem(value: m.key, child: Text(tr(m.value)))],
                onChanged: (v) => set(() => mode = v ?? mode),
              ),
              const SizedBox(height: 10),
              Text(tr('GST on the bill'), style: muted),
              Wrap(spacing: 6, children: [
                ChoiceChip(label: Text(tr('No GST')), selected: gst == 0, onSelected: (_) => set(() => gst = 0)),
                for (final r in gstRates)
                  ChoiceChip(
                    key: Key('gst-${r.toInt()}'),
                    label: Text('${r.toInt()}%'),
                    selected: gst == r,
                    onSelected: (_) => set(() => gst = r),
                  ),
              ]),
              if (gst > 0) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(tr('Amount includes GST')),
                  value: includesGst,
                  onChanged: (v) => set(() => includesGst = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(tr('Supplier in another state (IGST)')),
                  value: interState,
                  onChanged: (v) => set(() => interState = v),
                ),
                if (split != null)
                  Text(
                    key: const Key('expense-gst-split'),
                    split.igst > 0
                        ? '${rupees(split.total, paise: true)} = ${rupees(split.taxable, paise: true)}'
                            ' + IGST ${rupees(split.igst, paise: true)}'
                        : '${rupees(split.total, paise: true)} = ${rupees(split.taxable, paise: true)}'
                            ' + CGST ${rupees(split.cgst, paise: true)} + SGST ${rupees(split.sgst, paise: true)}',
                    style: muted,
                  ),
              ],
              _DateRow(value: on, onChanged: (d) => set(() => on = d)),
              TextField(controller: noteC, decoration: InputDecoration(labelText: tr('Note (optional)'))),
              if (existing == null) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final b in bills)
                    InputChip(
                      avatar: Icon(b.isPdf ? Icons.picture_as_pdf_outlined : Icons.receipt_long_outlined, size: 18),
                      label: Text(billFileName(b.path), overflow: TextOverflow.ellipsis),
                      onDeleted: () {
                        set(() => bills.remove(b));
                        deleteFileQuietly(b.path);
                      },
                    ),
                  ActionChip(
                    key: const Key('expense-add-bill'),
                    avatar: const Icon(Icons.attach_file, size: 18),
                    label: Text(bills.isEmpty ? tr('Attach bill photo or PDF') : tr('Add another bill')),
                    onPressed: () async {
                      final picked = await pickBills(ctx);
                      if (picked.isNotEmpty) set(() => bills.addAll(picked));
                    },
                  ),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(
                key: const Key('expense-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        );
      },
    ),
  );
  final typed = parseAmount(amount.text);
  if (ok != true || typed == null || typed <= 0) {
    for (final b in bills) {
      await deleteFileQuietly(b.path);
    }
    return false;
  }
  final value = gst > 0 && !includesGst ? withGst(typed, gst) : typed;
  final n = noteC.text.trim();
  final payee = paidToC.text.trim();
  final toWorker = cat == 'Labour' ? worker : null;
  final fields = SiteExpensesCompanion(
    category: Value(_cut(cat, 50)),
    amount: Value(value),
    incurredOn: Value(isoDay(on)),
    note: Value(n.isEmpty ? null : _cut(n, 300)),
    workerId: Value(toWorker),
    paidTo: Value(toWorker != null || payee.isEmpty ? null : _cut(payee, 120)),
    mode: Value(mode),
    gstPct: Value(gst > 0 ? gst : null),
    gstInterState: Value(gst > 0 && interState),
  );
  if (existing == null) {
    final saved = await db.expenseDao.create(fields.copyWith(
      id: Value(const Uuid().v4()),
      projectId: Value(projectId),
      recordedBy: Value(userId),
    ));
    for (final b in bills) {
      await db.expenseDao.attach(saved.id, b.path);
    }
  } else {
    await db.expenseDao.edit(existing.id, fields, by: userId);
  }
  _refreshMoney(ref, projectId);
  return true;
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(trf('Date: {date}', {'date': shortDay(value)}))),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
                context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d != null) onChanged(d);
          },
          child: Text(tr('Change')),
        ),
      ]);
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      ]);
}
