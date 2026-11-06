/// Project documents with versioning and local file storage.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class DocumentsView extends ConsumerStatefulWidget {
  const DocumentsView({
    super.key,
    required this.projectId,
    required this.userId,
  });
  final String projectId;
  final String userId;

  @override
  ConsumerState<DocumentsView> createState() => _DocumentsViewState();
}

class _DocumentsViewState extends ConsumerState<DocumentsView> {
  @override
  Widget build(BuildContext context) {
    final documentsList = ref.watch(documentsProvider(widget.projectId));
    return Column(
      children: [
        _sectionHeader(context, 'Documents', () => _pickAndUpload(context, ref)),
        Expanded(
          child: documentsList.when(
            data: (rows) => rows.isEmpty
                ? Center(child: Text(tr('No documents yet.')))
                : ListView(
                    children: [
                      for (final d in rows)
                        _DocumentTile(document: d),
                    ],
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => ErrorState(error: e, stack: st),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndUpload(BuildContext context, WidgetRef ref) async {
    final file = await FilePicker.pickFile();
    if (file == null || !context.mounted) return;

    final originalName = file.name;
    final extension = p.extension(originalName).toLowerCase();
    final baseName = p.basenameWithoutExtension(originalName);

    // Copy file to app's documents directory with UUID prefix
    final docsDir = await localDocumentsDirectory();
    final uuid = const Uuid().v4();
    final newFilename = '$uuid$extension';
    final newPath = p.join(docsDir.path, newFilename);
    await File(file.path!).copy(newPath);

    final fileSize = file.size;
    final mimeType = _guessMimeType(extension);

    // Show dialog to confirm name and pick category
    final nameController = TextEditingController(text: baseName);
    final categoryController = TextEditingController(text: 'other');
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Save document')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: tr('Document name'))),
            DropdownButtonFormField<String>(
              initialValue: 'other',
              decoration: InputDecoration(labelText: tr('Category')),
              items: const [
                'drawing',
                'specification',
                'contract',
                'permit',
                'report',
                'photo',
                'correspondence',
                'safety',
                'other'
              ].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => categoryController.text = v ?? 'other',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || nameController.text.trim().isEmpty || !context.mounted) return;

    await ref.read(appDatabaseProvider).documentDao.create(DocumentsCompanion.insert(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          name: nameController.text.trim(),
          category: Value(categoryController.text),
          filePath: newPath,
          fileSize: Value(fileSize),
          mimeType: Value(mimeType),
          uploadedBy: widget.userId,
        ));
    ref.invalidate(documentsProvider(widget.projectId));
  }

  String _guessMimeType(String extension) {
    switch (extension) {
      case '.pdf':
        return 'application/pdf';
      case '.dwg':
        return 'application/acad';
      case '.dxf':
        return 'application/dxf';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

}

Widget _sectionHeader(BuildContext context, String title, VoidCallback onAdd) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          FloatingActionButton.small(onPressed: onAdd, child: const Icon(Icons.upload_file)),
        ],
      ),
    );

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.document});
  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: _categoryIcon(document.category),
        title: Text(document.name),
        subtitle: Text('${document.category} · v${document.version} · ${_formatFileSize(document.fileSize ?? 0)}'),
        trailing: _versionBadge(document.version),
        onTap: () => _showVersions(context, ref),
      ),
    );
  }

  Icon _categoryIcon(String category) {
    final icon = switch (category) {
      'drawing' => Icons.description,
      'specification' => Icons.article,
      'contract' => Icons.gavel,
      'permit' => Icons.verified,
      'report' => Icons.assessment,
      'photo' => Icons.photo,
      'correspondence' => Icons.email,
      'safety' => Icons.shield,
      _ => Icons.insert_drive_file,
    };
    return Icon(icon);
  }

  Widget _versionBadge(int version) => StatusPill('v$version');

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _showVersions(BuildContext context, WidgetRef ref) async {
    final versions = await ref.read(appDatabaseProvider).documentDao.versionsOf(document.projectId, document.name);
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Versions — ${document.name}'),
        content: SizedBox(
          width: 400,
          child: versions.isEmpty
              ? Text(tr('No versions.'))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final v in versions)
                      ListTile(
                        dense: true,
                        title: Text('v${v.version}'),
                        subtitle: Text(fmtDateTime(v.createdAt)),
                        trailing: Text(_formatFileSize(v.fileSize ?? 0)),
                      ),
                  ],
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(tr('Close')))],
      ),
    );
  }
}