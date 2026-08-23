/// Inspections with checklist items (safety, quality, structural, MEP, etc.).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';

class InspectionsView extends ConsumerStatefulWidget {
  const InspectionsView({
    super.key,
    required this.projectId,
    required this.userId,
  });
  final String projectId;
  final String userId;

  @override
  ConsumerState<InspectionsView> createState() => _InspectionsViewState();
}

class _InspectionsViewState extends ConsumerState<InspectionsView> {
  @override
  Widget build(BuildContext context) {
    final inspectionsList = ref.watch(inspectionsProvider(widget.projectId));
    return Column(
      children: [
        _sectionHeader(context, 'Inspections', () => _addInspection(context, ref)),
        Expanded(
          child: inspectionsList.when(
            data: (rows) => rows.isEmpty
                ? const Center(child: Text('No inspections yet.'))
                : ListView(
                    children: [
                      for (final i in rows)
                        _InspectionTile(
                          inspection: i,
                          projectId: widget.projectId,
                          userId: widget.userId,
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

  Future<void> _addInspection(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final inspectionType = TextEditingController(text: 'safety');
    final scheduledDate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add inspection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            DropdownButtonFormField<String>(
              initialValue: 'safety',
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                'safety',
                'quality',
                'structural',
                'mep',
                'environmental',
                'final',
                'other'
              ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => inspectionType.text = v ?? 'safety',
            ),
            TextField(
              controller: scheduledDate,
              decoration: const InputDecoration(labelText: 'Scheduled date (optional)'),
              readOnly: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  scheduledDate.text = picked.toIso8601String().split('T').first;
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).inspectionDao.create(InspectionsCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          title: title.text.trim(),
          inspectionType: inspectionType.text,
          scheduledDate: scheduledDate.text.isEmpty
              ? const Value.absent()
              : Value(DateTime.parse(scheduledDate.text)),
          status: const Value('open'),
        ));
    ref.invalidate(inspectionsProvider(widget.projectId));
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

class _InspectionTile extends ConsumerWidget {
  const _InspectionTile({
    required this.inspection,
    required this.projectId,
    required this.userId,
  });
  final Inspection inspection;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(inspection.title),
        subtitle: Text('${inspection.inspectionType} · ${inspection.status}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(inspection.status),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Checklist',
              onPressed: () => _showChecklist(context, ref),
            ),
          ],
        ),
        onTap: () => _showChecklist(context, ref),
      ),
    );
  }

Widget _statusBadge(String status) {
    Color color;
    switch (status) {
      case 'open':
        color = Colors.blue;
      case 'in_progress':
        color = Colors.orange;
      case 'completed':
        color = Colors.green;
      default:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _showChecklist(BuildContext context, WidgetRef ref) async {
    final items = await ref.read(inspectionItemsProvider(inspection.id).future);
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Checklist — ${inspection.title}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (items.isEmpty)
                  const Text('No checklist items yet.')
                else
                  ...items.map((item) => _ChecklistItemTile(
                        item: item,
                        onChanged: (newStatus) async {
                          await ref.read(appDatabaseProvider).inspectionDao.updateItemStatus(item.id, newStatus);
                          ref.invalidate(inspectionItemsProvider(inspection.id));
                          ref.invalidate(inspectionsProvider(projectId));
                          setDialogState(() {});
                        },
                      )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            FilledButton(
              onPressed: () => _addItem(context, ref, setDialogState),
              child: const Text('Add item'),
            ),
            if (inspection.status != 'completed')
              FilledButton.tonal(
                onPressed: () => _completeInspection(context, ref),
                child: const Text('Complete inspection'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref, Function(void Function()) setDialogState) async {
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add checklist item'),
        content: TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || description.text.trim().isEmpty || !context.mounted) return;
    await ref.read(appDatabaseProvider).inspectionDao.addItem(InspectionItemsCompanion.insert(
          id: const Uuid().v4(),
          inspectionId: inspection.id,
          itemDescription: description.text.trim(),
          status: const Value('pending'),
        ));
    ref.invalidate(inspectionItemsProvider(inspection.id));
    ref.invalidate(inspectionsProvider(projectId));
    setDialogState(() {});
  }

  Future<void> _completeInspection(BuildContext context, WidgetRef ref) async {
    final overallResult = TextEditingController(text: 'pass');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Complete inspection'),
        content: DropdownButtonFormField<String>(
          initialValue: 'pass',
          decoration: const InputDecoration(labelText: 'Overall result'),
          items: const ['pass', 'fail', 'partial']
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (v) => overallResult.text = v ?? 'pass',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Complete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(appDatabaseProvider).inspectionDao.complete(inspection.id, overallResult.text);
    ref.invalidate(inspectionsProvider(projectId));
    ref.invalidate(inspectionItemsProvider(inspection.id));
    if (context.mounted) Navigator.of(context).pop();
  }
}

class _ChecklistItemTile extends ConsumerWidget {
  const _ChecklistItemTile({
    required this.item,
    required this.onChanged,
  });
  final InspectionItem item;
  final Function(String) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      title: Text(item.itemDescription),
      subtitle: item.notes != null && item.notes!.isNotEmpty ? Text(item.notes!) : null,
      trailing: DropdownButton<String>(
        value: item.status,
        items: const ['pending', 'pass', 'fail', 'na']
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (s) {
          if (s != null) onChanged(s);
        },
      ),
    );
  }
}