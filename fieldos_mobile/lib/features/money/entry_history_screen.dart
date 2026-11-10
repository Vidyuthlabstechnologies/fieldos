/// A site's change history: every correction, cancel and delete of money
/// and material entries, with what it was, what it became and who did it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/cash_book_screen.dart' show cashPeopleProvider, CashPerson;
import 'package:fieldos_mobile/features/money/entry_history.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

final _historyProvider = FutureProvider.autoDispose.family<List<HistoryItem>, String>(
    (ref, projectId) => loadSiteHistory(ref.watch(appDatabaseProvider), projectId));

String _kind(String k) => switch (k) {
      'Expense' => tr('Expense'),
      'Payment received' => tr('Payment received'),
      'Material received' => tr('Material received'),
      'Material used' => tr('Material used'),
      'Client bill' => tr('Client bill'),
      'Attendance punch' => tr('Attendance punch'),
      'Supplier invoice' => tr('Supplier invoice'),
      'Work measurement' => tr('Work measurement'),
      _ => k,
    };

String _field(String f) {
  final l = fieldLabel(f);
  return switch (l) {
    'Amount' => tr('Amount'),
    'Category' => tr('Category'),
    'Date' => tr('Date'),
    'Paid to' => tr('Paid to'),
    'Paid by' => tr('Paid by'),
    'Note' => tr('Note'),
    'GST %' => tr('GST %'),
    'Material' => tr('Material'),
    'Quantity' => tr('Quantity'),
    'Unit' => tr('Unit'),
    'From' => tr('From'),
    'Worker' => tr('Worker'),
    'In' => tr('In'),
    'Out' => tr('Out'),
    'Inside the site fence' => tr('Inside the site fence'),
    'Cancelled' => tr('Cancelled'),
    'Reason' => tr('Reason'),
    'Work' => tr('Work'),
    'Rate' => tr('Rate'),
    'Location' => tr('Location'),
    'Invoice number' => tr('Invoice number'),
    'Bill number' => tr('Bill number'),
    'GST' => tr('GST'),
    'Gross' => tr('Gross'),
    'Net payable' => tr('Net payable'),
    'Status' => tr('Status'),
    'Client' => tr('Client'),
    _ => l,
  };
}

final _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _isoTime = RegExp(r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}');

String showValue(String field, Object? v) {
  if (v == null || (v is String && v.isEmpty)) return tr('(empty)');
  if (v is bool) return v ? tr('Yes') : tr('No');
  if (v is num) return moneyFields.contains(field) ? rupees(v, paise: true) : fmtQty(v);
  if (v is String && _isoDay.hasMatch(v)) return fmtDate(DateTime.parse(v));
  if (v is String && _isoTime.hasMatch(v)) {
    final t = DateTime.tryParse(v);
    if (t != null) return fmtDateTime(t.toLocal());
  }
  return '$v';
}

enum _Show { all, deletes }

class EntryHistoryScreen extends ConsumerStatefulWidget {
  const EntryHistoryScreen({super.key, required this.project});
  final Project project;

  @override
  ConsumerState<EntryHistoryScreen> createState() => _EntryHistoryScreenState();
}

class _EntryHistoryScreenState extends ConsumerState<EntryHistoryScreen> {
  _Show _show = _Show.all;

  String _who(List<CashPerson> people, String? id) {
    if (id == null) return 'FieldOS';
    for (final p in people) {
      if (p.id == id) return p.name;
    }
    return tr('Someone on the team');
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(_historyProvider(widget.project.id));
    final people = ref.watch(cashPeopleProvider).value ?? const <CashPerson>[];
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Change history'))),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st, onRetry: () => ref.invalidate(_historyProvider(widget.project.id))),
        data: (all) {
          final shown = _show == _Show.all ? all : all.where((h) => h.deleted || h.cancelled).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_historyProvider(widget.project.id)),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: Text(tr('All changes')),
                      selected: _show == _Show.all,
                      onSelected: (_) => setState(() => _show = _Show.all)),
                  ChoiceChip(
                      label: Text(tr('Deletes and cancels')),
                      selected: _show == _Show.deletes,
                      onSelected: (_) => setState(() => _show = _Show.deletes)),
                ]),
                if (shown.isEmpty)
                  EmptyState(
                    compact: true,
                    icon: Icons.history,
                    title: tr('No changes yet'),
                    message: tr(
                        'When an expense, payment, delivery, bill or attendance entry is changed or deleted, what it was and who changed it shows here. It syncs from the cloud.'),
                  ),
                for (final h in shown)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(
                            child: Text(
                                [_kind(h.kind), if (h.summary.isNotEmpty) h.summary].join(' · '),
                                style: theme.textTheme.titleSmall),
                          ),
                          if (h.deleted)
                            StatusPill(tr('Deleted'), tone: PillTone.danger)
                          else if (h.cancelled)
                            StatusPill(tr('Cancelled'), tone: PillTone.warn)
                          else
                            StatusPill(tr('Changed')),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                            '${_who(people, h.row.changedBy)}, ${fmtDateTime(h.row.changedAt)}',
                            style: theme.textTheme.bodySmall),
                        const SizedBox(height: 6),
                        if (h.deleted && h.amountBefore != null)
                          Text(trf('It was {amount}', {'amount': rupees(h.amountBefore!, paise: true)})),
                        for (final c in h.changes.take(8))
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text.rich(TextSpan(children: [
                              TextSpan(text: '${_field(c.field)}: ', style: theme.textTheme.bodySmall),
                              TextSpan(
                                  text: showValue(c.field, c.before),
                                  style: const TextStyle(decoration: TextDecoration.lineThrough)),
                              const TextSpan(text: '  →  '),
                              TextSpan(text: showValue(c.field, c.after), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ])),
                          ),
                      ]),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
