/// Worker directory per project (name, role, phone, daily wage, active/inactive).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/features/workers/worker_calendar.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

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
                ? Center(child: Text(tr('No workers yet.')))
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
            error: (e, st) => ErrorState(error: e, stack: st),
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
        title: Text(tr('Add worker')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: tr('Name'))),
            TextField(controller: role, decoration: InputDecoration(labelText: tr('Role'))),
            TextField(controller: phone, decoration: InputDecoration(labelText: tr('Phone'))),
            TextField(
              controller: dailyWage,
              decoration: InputDecoration(labelText: tr('Daily wage')),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
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
          IconButton(icon: const Icon(Icons.add), tooltip: tr('Add'), onPressed: onAdd),
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
        onTap: () => openWorkerCalendar(context, worker),
        title: Text(worker.name),
        subtitle: Text([
          worker.role ?? '',
          worker.phone ?? '',
          worker.dailyWage != null ? '${rupees(worker.dailyWage!)} a day' : '',
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
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'active', child: Text(tr('Active'))),
                PopupMenuItem(value: 'inactive', child: Text(tr('Inactive'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status) =>
      status == 'active' ? const StatusPill('Active', tone: PillTone.ok) : const StatusPill('Not active');
}