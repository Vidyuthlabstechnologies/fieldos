/// Worker directory per project (name, role, phone, daily wage, active/inactive).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

class WorkersView extends ConsumerStatefulWidget {
  const WorkersView({
    super.key,
    required this.projectId,
    required this.userId,
  });
  final String projectId;
  final String userId;

  @override
  ConsumerState<WorkersView> createState() => _WorkersViewState();
}

class _WorkersViewState extends ConsumerState<WorkersView> {
  @override
  Widget build(BuildContext context) {
    final workersList = ref.watch(workersProvider(widget.projectId));
    return Column(
      children: [
        _sectionHeader(context, 'Workers', () => _addWorker(context, ref)),
        Expanded(
          child: workersList.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No workers yet.'))
                : ListView(
                    children: [
                      for (final w in rows)
                        _WorkerTile(
                          worker: w,
                          projectId: widget.projectId,
                        ),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ),
      ],
    );
  }

  Future<void> _addWorker(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final role = TextEditingController();
    final phone = TextEditingController();
    final dailyWage = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add worker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: role, decoration: const InputDecoration(labelText: 'Role')),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone')),
            TextField(
              controller: dailyWage,
              decoration: const InputDecoration(labelText: 'Daily wage'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).workerDao.create(WorkersCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          name: name.text.trim(),
          role: Value(role.text.trim()),
          phone: Value(phone.text.trim()),
          dailyWage: Value(double.tryParse(dailyWage.text)),
          status: const Value('active'),
        ));
    ref.invalidate(workersProvider(widget.projectId));
  }
}

Widget _sectionHeader(BuildContext context, String title, VoidCallback onAdd) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add', onPressed: onAdd),
        ],
      ),
    );

class _WorkerTile extends ConsumerWidget {
  const _WorkerTile({required this.worker, required this.projectId});
  final Worker worker;
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(worker.name),
        subtitle: Text([
          worker.role ?? '',
          worker.phone ?? '',
          worker.dailyWage != null ? '₹${worker.dailyWage!.toStringAsFixed(0)}/day' : '',
        ].where((e) => e.isNotEmpty).join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(worker.status),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              initialValue: worker.status,
              onSelected: (s) async {
                await ref.read(appDatabaseProvider).workerDao.setStatus(worker.id, s);
                ref.invalidate(workersProvider(projectId));
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'active', child: Text('Active')),
                PopupMenuItem(value: 'inactive', child: Text('Inactive')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = status == 'active' ? Colors.green : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}