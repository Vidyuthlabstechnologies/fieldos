/// Equipment tracking: list, add, status, and usage/maintenance logs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

class EquipmentView extends ConsumerStatefulWidget {
  const EquipmentView({
    super.key,
    required this.projectId,
    required this.userId,
  });
  final String projectId;
  final String userId;

  @override
  ConsumerState<EquipmentView> createState() => _EquipmentViewState();
}

class _EquipmentViewState extends ConsumerState<EquipmentView> {
  @override
  Widget build(BuildContext context) {
    final equipmentList = ref.watch(equipmentProvider(widget.projectId));
    return Column(
      children: [
        _sectionHeader(context, 'Equipment', () => _addEquipment(context, ref)),
        Expanded(
          child: equipmentList.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No equipment yet.'))
                : ListView(
                    children: [
                      for (final e in rows)
                        _EquipmentTile(
                          equipment: e,
                          projectId: widget.projectId,
                          userId: widget.userId,
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

  Future<void> _addEquipment(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final equipmentType = TextEditingController();
    final model = TextEditingController();
    final registrationNumber = TextEditingController();
    final dailyRate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add equipment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
            TextField(controller: equipmentType, decoration: const InputDecoration(labelText: 'Type')),
            TextField(controller: model, decoration: const InputDecoration(labelText: 'Model')),
            TextField(controller: registrationNumber, decoration: const InputDecoration(labelText: 'Registration No.')),
            TextField(
              controller: dailyRate,
              decoration: const InputDecoration(labelText: 'Daily rate'),
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
    await ref.read(appDatabaseProvider).equipmentDao.create(EquipmentCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          name: name.text.trim(),
          equipmentType: Value(equipmentType.text.trim()),
          model: Value(model.text.trim()),
          registrationNumber: Value(registrationNumber.text.trim()),
          dailyRate: Value(double.tryParse(dailyRate.text)),
          status: const Value('available'),
        ));
    ref.invalidate(equipmentProvider(widget.projectId));
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

class _EquipmentTile extends ConsumerWidget {
  const _EquipmentTile({
    required this.equipment,
    required this.projectId,
    required this.userId,
  });
  final EquipmentData equipment;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(equipment.name),
        subtitle: Text([
          equipment.equipmentType ?? '',
          equipment.model ?? '',
          equipment.registrationNumber ?? '',
        ].where((e) => e.isNotEmpty).join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(equipment.status),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              initialValue: equipment.status,
              onSelected: (s) async {
                await ref.read(appDatabaseProvider).equipmentDao.updateStatus(equipment.id, s);
                ref.invalidate(equipmentProvider(projectId));
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'available', child: Text('Available')),
                PopupMenuItem(value: 'in_use', child: Text('In use')),
                PopupMenuItem(value: 'maintenance', child: Text('Maintenance')),
                PopupMenuItem(value: 'breakdown', child: Text('Breakdown')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: 'View logs',
              onPressed: () => _showLogs(context, ref),
            ),
          ],
        ),
        onTap: () => _showLogs(context, ref),
      ),
    );
  }

  Widget _statusBadge(String status) => switch (status) {
        'available' => const StatusPill('Available', tone: PillTone.ok),
        'in_use' => const StatusPill('In use'),
        'maintenance' => const StatusPill('In maintenance', tone: PillTone.warn),
        'breakdown' => const StatusPill('Broken down', tone: PillTone.danger),
        _ => StatusPill(status.replaceAll('_', ' ')),
      };

  Future<void> _showLogs(BuildContext context, WidgetRef ref) async {
    final logs = await ref.read(equipmentLogsProvider(equipment.id).future);
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Logs — ${equipment.name}'),
        content: SizedBox(
          width: 400,
          child: logs.isEmpty
              ? const Text('No logs yet.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final l in logs)
                      ListTile(
                        dense: true,
                        title: Text('${fmtDate(l.logDate, short: true)} · ${l.logType.replaceAll('_', ' ')}'),
                        subtitle: Text([
                          l.hoursUsed != null ? '${l.hoursUsed} hrs' : '',
                          l.cost != null ? rupees(l.cost!) : '',
                          l.description ?? '',
                        ].where((e) => e.isNotEmpty).join(' · ')),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          FilledButton(
            onPressed: () => _addLog(context, ref),
            child: const Text('Add log'),
          ),
        ],
      ),
    );
  }

  Future<void> _addLog(BuildContext context, WidgetRef ref) async {
    final logType = TextEditingController(text: 'usage');
    final hoursUsed = TextEditingController();
    final description = TextEditingController();
    final cost = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add equipment log'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: 'usage',
              decoration: const InputDecoration(labelText: 'Log type'),
              items: const ['usage', 'maintenance', 'repair', 'fuel', 'inspection']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => logType.text = v ?? 'usage',
            ),
            TextField(
              controller: hoursUsed,
              decoration: const InputDecoration(labelText: 'Hours used'),
              keyboardType: TextInputType.number,
            ),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
            TextField(
              controller: cost,
              decoration: const InputDecoration(labelText: 'Cost'),
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
    if (ok != true || !context.mounted) return;
    await ref.read(appDatabaseProvider).equipmentDao.addLog(EquipmentLogsCompanion.insert(
          id: const Uuid().v4(),
          equipmentId: equipment.id,
          logDate: DateTime.now(),
          logType: logType.text,
          hoursUsed: Value(double.tryParse(hoursUsed.text)),
          description: Value(description.text.trim()),
          cost: Value(double.tryParse(cost.text)),
          createdBy: userId,
        ));
    ref.invalidate(equipmentLogsProvider(equipment.id));
    ref.invalidate(equipmentProvider(projectId));
  }
}