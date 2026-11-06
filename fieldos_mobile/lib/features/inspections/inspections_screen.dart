/// Inspections with checklist items (safety, quality, structural, MEP, etc.).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class InspectionsView extends ConsumerStatefulWidget {
  const InspectionsView({super.key, required this.projectId, required this.userId});
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
                ? Center(child: Text(tr('No inspections yet.')))
                : ListView(
                    children: [
                      for (final i in rows)
                        _InspectionTile(inspection: i, projectId: widget.projectId, userId: widget.userId),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _addInspection(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final inspectionType = TextEditingController(text: 'safety');
    final scheduledDate = TextEditingController();
    DateTime? scheduledOn;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Add inspection')),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: InputDecoration(labelText: tr('Title')),
            ),
            DropdownButtonFormField<String>(
              initialValue: 'safety',
              decoration: InputDecoration(labelText: tr('Type')),
              items: [for (final t in _inspectionTypes) DropdownMenuItem(value: t, child: Text(_typeLabel(t)))],
              onChanged: (v) => inspectionType.text = v ?? 'safety',
            ),
            TextField(
              controller: scheduledDate,
              decoration: InputDecoration(labelText: tr('Scheduled date (optional)')),
              readOnly: true,
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  scheduledOn = picked;
                  scheduledDate.text = fmtDate(picked);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
    await ref
        .read(appDatabaseProvider)
        .inspectionDao
        .create(
          InspectionsCompanion.insert(
            id: const Uuid().v4(),
            projectId: widget.projectId,
            title: title.text.trim(),
            inspectionType: inspectionType.text,
            scheduledDate: scheduledOn == null ? const Value.absent() : Value(scheduledOn!),
            status: const Value('open'),
          ),
        );
    ref.invalidate(inspectionsProvider(widget.projectId));
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

class _InspectionTile extends ConsumerWidget {
  const _InspectionTile({required this.inspection, required this.projectId, required this.userId});
  final Inspection inspection;
  final String projectId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        title: Text(inspection.title),
        subtitle: Text(
          [
            _typeLabel(inspection.inspectionType),
            if (inspection.completedDate != null)
              'done ${fmtDate(inspection.completedDate!, short: true)}'
            else if (inspection.scheduledDate != null)
              'due ${fmtDate(inspection.scheduledDate!, short: true)}',
          ].join(' · '),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _statusBadge(inspection),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: tr('Checklist'),
              onPressed: () => _showChecklist(context),
            ),
          ],
        ),
        onTap: () => _showChecklist(context),
      ),
    );
  }

  Future<void> _showChecklist(BuildContext context) => showDialog<void>(
    context: context,
    // Watches the items, so a status picked here or an item just added
    // shows at once. The list used to be read once when the dialog
    // opened, so a changed status snapped back to the old one.
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final items = ref.watch(inspectionItemsProvider(inspection.id));
        return AlertDialog(
          title: Text(inspection.title),
          scrollable: true,
          content: SizedBox(
            width: 400,
            child: items.when(
              data: (rows) => rows.isEmpty
                  ? Text(tr('Nothing on the checklist yet. Add each thing to check, with a photo if it helps.'))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in rows)
                          _ChecklistItemTile(
                            item: item,
                            onChanged: (status) async {
                              await ref.read(appDatabaseProvider).inspectionDao.updateItemStatus(item.id, status);
                              ref.invalidate(inspectionItemsProvider(inspection.id));
                            },
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
            OutlinedButton(onPressed: () => _addItem(ctx, ref), child: Text(tr('Add item'))),
            if (inspection.status != 'completed')
              FilledButton(onPressed: () => _completeInspection(ctx, ref), child: Text(tr('Complete'))),
          ],
        );
      },
    ),
  );

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final description = TextEditingController();
    String? photoPath;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setItemState) => AlertDialog(
          title: Text(tr('Add checklist item')),
          scrollable: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 300,
                decoration: InputDecoration(labelText: tr('What to check'), counterText: ''),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: Icon(photoPath == null ? Icons.photo_camera_outlined : Icons.check_circle_outline),
                label: Text(photoPath == null ? tr('Add a photo') : tr('Photo added')),
                onPressed: () async {
                  final path = await captureCameraFirst(ctx, prefix: 'inspection');
                  if (path != null) setItemState(() => photoPath = path);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    final text = description.text.trim();
    description.dispose();
    if (ok != true || text.isEmpty || !context.mounted) return;

    // The item has no photo column, so the photo's path goes in its notes
    // (see splitInspectionNotes).
    await ref
        .read(appDatabaseProvider)
        .inspectionDao
        .addItem(
          InspectionItemsCompanion.insert(
            id: const Uuid().v4(),
            inspectionId: inspection.id,
            itemDescription: text,
            status: const Value('pending'),
            notes: Value(photoPath == null ? null : '$_photoPrefix$photoPath'),
          ),
        );
    ref.invalidate(inspectionItemsProvider(inspection.id));
  }

  Future<void> _completeInspection(BuildContext context, WidgetRef ref) async {
    var result = 'pass';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Complete inspection')),
        content: DropdownButtonFormField<String>(
          initialValue: result,
          decoration: InputDecoration(labelText: tr('Overall result')),
          items: [for (final e in _results.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => result = v ?? 'pass',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Complete'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(appDatabaseProvider).inspectionDao.complete(inspection.id, result);
    ref.invalidate(inspectionsProvider(projectId));
    if (context.mounted) Navigator.of(context).pop();
  }
}

const _inspectionTypes = ['safety', 'quality', 'structural', 'mep', 'environmental', 'final', 'other'];

String _typeLabel(String type) => switch (type) {
  'mep' => tr('MEP'),
  '' => tr('Inspection'),
  _ => '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}',
};

/// An inspection's overall result, in words.
const _results = {'pass': 'Passed', 'fail': 'Failed', 'partial': 'Partly passed'};

Widget _statusBadge(Inspection i) => switch (i.status) {
  'completed' => switch (i.overallResult) {
    'pass' => const StatusPill('Passed', tone: PillTone.ok),
    'fail' => const StatusPill('Failed', tone: PillTone.danger),
    'partial' => const StatusPill('Partly passed', tone: PillTone.warn),
    _ => const StatusPill('Done', tone: PillTone.ok),
  },
  'open' => const StatusPill('Open'),
  'in_progress' => const StatusPill('In progress', tone: PillTone.warn),
  final other => StatusPill(other.replaceAll('_', ' ')),
};

/// A checklist item's status, in words.
const _itemStatuses = {'pending': 'Not checked', 'pass': 'Pass', 'fail': 'Fail', 'na': 'Not needed'};

const _photoPrefix = 'Photo: ';

/// A checklist item's notes hold its photo's path on the phone that took it
/// as `Photo: /the/path`. Splits that from any other note, so the path
/// itself is never shown as text.
({String? photoPath, String? text}) splitInspectionNotes(String? notes) {
  final lines = (notes ?? '').split('\n');
  String? photoPath;
  final rest = <String>[];
  for (final line in lines) {
    if (photoPath == null && line.startsWith(_photoPrefix) && line.length > _photoPrefix.length) {
      photoPath = line.substring(_photoPrefix.length).trim();
    } else if (line.trim().isNotEmpty) {
      rest.add(line.trim());
    }
  }
  return (photoPath: photoPath, text: rest.isEmpty ? null : rest.join('\n'));
}

class _ChecklistItemTile extends StatelessWidget {
  const _ChecklistItemTile({required this.item, required this.onChanged});
  final InspectionItem item;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final (:photoPath, :text) = splitInspectionNotes(item.notes);
    final photo = photoPath == null ? null : File(photoPath);
    final onThisPhone = photo != null && photo.existsSync();
    final details = [if (photoPath != null && !onThisPhone) 'Photo is on the phone that took it', ?text];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: onThisPhone ? _PhotoThumb(photo) : null,
      title: Text(item.itemDescription),
      subtitle: details.isEmpty ? null : Text(details.join('\n')),
      trailing: DropdownButton<String>(
        value: _itemStatuses.containsKey(item.status) ? item.status : null,
        hint: Text(item.status),
        items: [for (final e in _itemStatuses.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (s) {
          if (s != null && s != item.status) onChanged(s);
        },
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb(this.file);
  final File file;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tr('Open photo'),
    child: InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => showPhotoViewer(context, [file.path]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          file,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          cacheWidth: 132,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        ),
      ),
    ),
  );
}
