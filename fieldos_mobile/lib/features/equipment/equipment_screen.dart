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
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';

class EquipmentView extends ConsumerStatefulWidget {
  const EquipmentView({super.key, required this.projectId, required this.userId});
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
                ? MitraEmpty(tr('No equipment yet.'), mood: MitraMood.hammer)
                : ListView(
                    children: [
                      for (final e in rows)
                        _EquipmentTile(equipment: e, projectId: widget.projectId, userId: widget.userId),
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
        title: Text(tr('Add equipment')),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Name'), hintText: tr('e.g. JCB 3DX')),
            ),
            TextField(
              controller: equipmentType,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('Type (optional)'), hintText: tr('e.g. Excavator')),
            ),
            TextField(
              controller: model,
              decoration: InputDecoration(labelText: tr('Model (optional)')),
            ),
            TextField(
              controller: registrationNumber,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: tr('Registration number (optional)')),
            ),
            TextField(
              controller: dailyRate,
              decoration: InputDecoration(labelText: tr('Daily rate (optional)'), prefixText: '₹ '),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    await ref
        .read(appDatabaseProvider)
        .equipmentDao
        .create(
          EquipmentCompanion.insert(
            id: const Uuid().v4(),
            projectId: widget.projectId,
            name: name.text.trim(),
            equipmentType: Value(_orNull(equipmentType.text)),
            model: Value(_orNull(model.text)),
            registrationNumber: Value(_orNull(registrationNumber.text)),
            dailyRate: Value(_amount(dailyRate.text)),
            status: const Value('available'),
          ),
        );
    ref.invalidate(equipmentProvider(widget.projectId));
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

class _EquipmentTile extends ConsumerWidget {
  const _EquipmentTile({required this.equipment, required this.projectId, required this.userId});
  final EquipmentData equipment;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(equipment.name),
        subtitle: Text(
          [
            equipment.equipmentType ?? '',
            equipment.model ?? '',
            equipment.registrationNumber ?? '',
          ].where((e) => e.isNotEmpty).join(' · '),
        ),
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
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'available', child: Text(tr('Available'))),
                PopupMenuItem(value: 'in_use', child: Text(tr('In use'))),
                PopupMenuItem(value: 'maintenance', child: Text(tr('Maintenance'))),
                PopupMenuItem(value: 'breakdown', child: Text(tr('Breakdown'))),
              ],
            ),
            IconButton(icon: const Icon(Icons.list_alt), tooltip: tr('View logs'), onPressed: () => _showLogs(context)),
          ],
        ),
        onTap: () => _showLogs(context),
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

  Future<void> _showLogs(BuildContext context) => showDialog<void>(
    context: context,
    // Watches the logs, so one just added shows at once (the list used
    // to be read once, when the dialog opened).
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final logs = ref.watch(equipmentLogsProvider(equipment.id));
        return AlertDialog(
          title: Text(equipment.name),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: logs.when(
              data: (rows) => rows.isEmpty
                  ? Text(tr('No logs yet. Add hours worked, fuel, repairs or servicing.'))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final l in rows)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text('${fmtDate(l.logDate, short: true)} · ${_logTypeLabel(l.logType)}'),
                            subtitle: Text(
                              [
                                if (l.hoursUsed != null) '${fmtQty(l.hoursUsed!)} h',
                                if (l.cost != null) rupees(l.cost!, paise: true),
                                if ((l.description ?? '').isNotEmpty) l.description!,
                              ].join(' · '),
                            ),
                          ),
                      ],
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, st) => Text(friendlyError(e, st)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Close'))),
            FilledButton(onPressed: () => _addLog(ctx, ref), child: Text(tr('Add log'))),
          ],
        );
      },
    ),
  );

  Future<void> _addLog(BuildContext context, WidgetRef ref) async {
    final logType = TextEditingController(text: 'usage');
    final hoursUsed = TextEditingController();
    final description = TextEditingController();
    final cost = TextEditingController();
    String? hoursError;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr('Add equipment log')),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: 'usage',
                decoration: InputDecoration(labelText: tr('What happened')),
                items: [for (final t in _logTypes) DropdownMenuItem(value: t, child: Text(_logTypeLabel(t)))],
                onChanged: (v) => logType.text = v ?? 'usage',
              ),
              TextField(
                controller: hoursUsed,
                decoration: InputDecoration(labelText: tr('Hours (optional)'), errorText: hoursError),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: description,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Note (optional)')),
              ),
              TextField(
                controller: cost,
                decoration: InputDecoration(labelText: tr('Cost (optional)'), prefixText: '₹ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () {
                // The cloud keeps hours below 10,000 (a meter reading, at most).
                final h = _amount(hoursUsed.text);
                final bad = hoursUsed.text.trim().isNotEmpty && (h == null || h >= 10000);
                if (bad) {
                  setDialogState(() => hoursError = 'Enter hours as a number below 10,000');
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: Text(tr('Save')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref
        .read(appDatabaseProvider)
        .equipmentDao
        .addLog(
          EquipmentLogsCompanion.insert(
            id: const Uuid().v4(),
            equipmentId: equipment.id,
            logDate: DateTime.now(),
            logType: logType.text,
            hoursUsed: Value(_amount(hoursUsed.text)),
            description: Value(_orNull(description.text)),
            cost: Value(_amount(cost.text)),
            createdBy: userId,
          ),
        );
    ref.invalidate(equipmentLogsProvider(equipment.id));
    ref.invalidate(equipmentProvider(projectId));
  }
}

const _logTypes = ['usage', 'fuel', 'maintenance', 'repair', 'inspection'];

String _logTypeLabel(String t) => switch (t) {
  'usage' => tr('Worked'),
  'fuel' => tr('Fuel'),
  'maintenance' => tr('Servicing'),
  'repair' => tr('Repair'),
  'inspection' => tr('Inspection'),
  _ => t.replaceAll('_', ' '),
};

String? _orNull(String text) => text.trim().isEmpty ? null : text.trim();

/// A typed amount, tolerating "1,500" and a stray "₹"; null when blank,
/// unreadable or negative.
double? _amount(String text) {
  final v = double.tryParse(text.replaceAll(RegExp(r'[₹,\s]'), ''));
  return v == null || v < 0 || v.isNaN || v.isInfinite ? null : v;
}
