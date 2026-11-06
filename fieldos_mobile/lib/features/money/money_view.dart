/// Site money: every rupee spent on site (petty cash, labour, transport,
/// hire...) and, for owners and project managers, every rupee received from
/// the client, with the site's balance at the top. Expenses tagged to a
/// worker are their wages or advances and show on the wage sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' hide Column;

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

const expenseCategories = ['Material', 'Labour', 'Transport', 'Equipment hire', 'Food & tea', 'Fuel', 'Other'];
const paymentModes = {'cash': 'Cash', 'upi': 'UPI', 'bank': 'Bank transfer', 'cheque': 'Cheque'};

final expensesProvider = FutureProvider.autoDispose.family<List<SiteExpense>, String>((ref, projectId) async {
  final rows = await ref.watch(appDatabaseProvider).expenseDao.forProject(projectId);
  rows.sort((a, b) => b.incurredOn.compareTo(a.incurredOn) != 0
      ? b.incurredOn.compareTo(a.incurredOn)
      : b.createdAt.compareTo(a.createdAt));
  return rows;
});

final paymentsReceivedProvider = FutureProvider.autoDispose.family<List<PaymentsReceivedData>, String>(
    (ref, projectId) => ref.watch(appDatabaseProvider).paymentDao.forProject(projectId));

/// Indian grouping: 12,34,567.
String rupees(double v) {
  final neg = v < 0;
  final whole = v.abs().round().toString();
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$grouped';
}

String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String shortDay(DateTime d) {
  final l = d.toLocal();
  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year}';
}

bool canSeeMoneyIn(String? role) => role == Roles.owner || role == Roles.manager;

class MoneyView extends ConsumerWidget {
  const MoneyView({super.key, required this.projectId, required this.userId});
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider).role;
    final showIn = canSeeMoneyIn(role);
    final expenses = ref.watch(expensesProvider(projectId));
    final received = showIn ? ref.watch(paymentsReceivedProvider(projectId)) : const AsyncValue.data(<PaymentsReceivedData>[]);
    final workers = ref.watch(workersProvider(projectId)).valueOrNull ?? const <Worker>[];
    final workerName = {for (final w in workers) w.id: w.name};

    final spent = expenses.valueOrNull?.fold<double>(0, (s, e) => s + e.amount) ?? 0;
    final inTotal = received.valueOrNull?.fold<double>(0, (s, p) => s + p.amount) ?? 0;

    return DefaultTabController(
      length: showIn ? 2 : 1,
      child: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (showIn) _Figure('Received', rupees(inTotal), Colors.green.shade700),
                  _Figure('Spent', rupees(spent), Colors.red.shade700),
                  if (showIn)
                    _Figure('Balance', rupees(inTotal - spent),
                        inTotal - spent < 0 ? Colors.red.shade700 : Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
          TabBar(tabs: [
            const Tab(text: 'Spent'),
            if (showIn) const Tab(text: 'Received'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _list<SiteExpense>(
                expenses,
                empty: 'No expenses yet. Tap + to add petty cash, labour, transport and more.',
                tile: (e) => ListTile(
                  leading: CircleAvatar(child: Icon(_iconFor(e.category), size: 20)),
                  title: Text('${e.category}${e.workerId != null ? ' · ${workerName[e.workerId] ?? 'worker'}' : ''}'),
                  subtitle: Text([e.incurredOn, if (e.note != null && e.note!.isNotEmpty) e.note!].join(' · ')),
                  trailing: Text(rupees(e.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                onAdd: () => addExpense(context, ref, projectId: projectId, userId: userId),
                addLabel: 'Add expense',
              ),
              if (showIn)
                _list<PaymentsReceivedData>(
                  received,
                  empty: 'Record each payment the client makes (running bills, advances).',
                  tile: (p) => ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.call_received, size: 20)),
                    title: Text(p.fromParty),
                    subtitle: Text([shortDay(p.receivedOn), paymentModes[p.mode] ?? p.mode, if (p.note != null) p.note!]
                        .join(' · ')),
                    trailing: Text(rupees(p.amount),
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                  ),
                  onAdd: () => _addReceived(context, ref),
                  addLabel: 'Add payment received',
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _list<T>(AsyncValue<List<T>> rows,
      {required String empty,
      required Widget Function(T) tile,
      required VoidCallback onAdd,
      required String addLabel}) {
    return Stack(children: [
      rows.when(
        data: (list) => list.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(empty, textAlign: TextAlign.center)))
            : ListView(padding: const EdgeInsets.only(bottom: 80), children: [for (final r in list) tile(r)]),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
            heroTag: addLabel, onPressed: onAdd, icon: const Icon(Icons.add), label: Text(addLabel)),
      ),
    ]);
  }

  static IconData _iconFor(String c) => switch (c) {
        'Material' => Icons.inventory_2,
        'Labour' => Icons.engineering,
        'Transport' => Icons.local_shipping,
        'Equipment hire' => Icons.construction,
        'Food & tea' => Icons.local_cafe,
        'Fuel' => Icons.local_gas_station,
        _ => Icons.receipt_long,
      };

  Future<void> _addReceived(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController();
    final party = TextEditingController();
    final note = TextEditingController();
    var mode = 'bank';
    var on = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Payment received'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: party,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'From (client name)')),
              TextField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount (₹)')),
              DropdownButtonFormField<String>(
                initialValue: mode,
                decoration: const InputDecoration(labelText: 'Paid by'),
                items: [for (final m in paymentModes.entries) DropdownMenuItem(value: m.key, child: Text(m.value))],
                onChanged: (v) => set(() => mode = v ?? mode),
              ),
              _DateRow(value: on, onChanged: (d) => set(() => on = d)),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (e.g. RA bill 3)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    final value = double.tryParse(amount.text.trim());
    if (ok != true || value == null || value <= 0 || party.text.trim().isEmpty) return;
    await ref.read(appDatabaseProvider).paymentDao.create(PaymentsReceivedCompanion.insert(
          id: const Uuid().v4(),
          projectId: projectId,
          amount: value,
          receivedOn: on,
          fromParty: party.text.trim(),
          mode: mode,
          recordedBy: userId,
          note: Value(note.text.trim().isEmpty ? null : note.text.trim()),
        ));
    ref.invalidate(paymentsReceivedProvider(projectId));
  }
}

/// Add-expense dialog, also used by the wage sheet's "Pay" button (with
/// [category] Labour and [workerId] preset). Returns true when saved.
Future<bool> addExpense(BuildContext context, WidgetRef ref,
    {required String projectId,
    required String userId,
    String? category,
    String? workerId,
    double? suggestedAmount,
    String? note}) async {
  final amount = TextEditingController(text: suggestedAmount == null ? '' : suggestedAmount.round().toString());
  final noteC = TextEditingController(text: note ?? '');
  var cat = category ?? expenseCategories.first;
  String? worker = workerId;
  var on = DateTime.now();
  final workers = (await ref.read(workersProvider(projectId).future)).where((w) => w.status == 'active').toList();
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(workerId != null ? 'Pay worker' : 'Add expense'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final c in expenseCategories)
                ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => set(() => cat = c)),
            ]),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            if (cat == 'Labour' && workers.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: worker,
                decoration: const InputDecoration(labelText: 'Paid to (for wages or an advance)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Not one worker')),
                  for (final w in workers) DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                ],
                onChanged: (v) => set(() => worker = v),
              ),
            _DateRow(value: on, onChanged: (d) => set(() => on = d)),
            TextField(controller: noteC, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  final value = double.tryParse(amount.text.trim());
  if (ok != true || value == null || value <= 0) return false;
  final n = noteC.text.trim();
  await ref.read(appDatabaseProvider).expenseDao.create(SiteExpensesCompanion.insert(
        id: const Uuid().v4(),
        projectId: projectId,
        category: cat,
        amount: value,
        incurredOn: isoDay(on),
        recordedBy: userId,
        note: Value(n.isEmpty ? null : (n.length > 300 ? n.substring(0, 300) : n)),
        workerId: Value(cat == 'Labour' ? worker : null),
      ));
  ref.invalidate(expensesProvider(projectId));
  return true;
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.value, required this.onChanged});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text('Date: ${shortDay(value)}')),
        TextButton(
          onPressed: () async {
            final d = await showDatePicker(
                context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d != null) onChanged(d);
          },
          child: const Text('Change'),
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
