/// Settings > Your data: back up this phone to one file, and restore one.
/// The file is shared wherever the person keeps things (Drive, WhatsApp to
/// themselves, a computer); restoring checks it first and takes effect the
/// next time FieldOS opens. See docs/BACKUP_RESTORE.md.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/data/backup.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

Future<void> backUpPhone(BuildContext context, WidgetRef ref) async {
  final db = ref.read(appDatabaseProvider);
  try {
    final tmp = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'FieldOS-backup-${now.year}-${two(now.month)}-${two(now.day)}-${two(now.hour)}${two(now.minute)}.zip';
    final out = File(p.join(tmp.path, name));
    final info = await writeBackup(db, out, workDir: tmp);
    if (!context.mounted) return;
    await SharePlus.instance.share(ShareParams(
      files: [XFile(out.path, mimeType: 'application/zip')],
      text: trf('FieldOS backup: {sites} sites, {files} photos and bills', {
        'sites': '${info.counts['projects'] ?? 0}',
        'files': '${info.files}',
      }),
    ));
  } catch (e) {
    if (context.mounted) showSnack(context, trf('Backup failed: {error}', {'error': '$e'}), error: true);
  }
}

Future<void> restoreBackup(BuildContext context, WidgetRef ref) async {
  final sure = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Restore a backup?')),
      content: Text(tr(
          'Everything on this phone is replaced by the backup the next time FieldOS opens. The current data is kept aside on the phone in case you need it back.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Choose backup file'))),
      ],
    ),
  );
  if (sure != true || !context.mounted) return;
  final picked = await FilePicker.pickFile();
  final path = picked?.path;
  if (path == null || !context.mounted) return;
  final db = ref.read(appDatabaseProvider);
  try {
    final info = await stageRestore(File(path),
        databasePath: await appDatabasePath(),
        filesDir: await localMediaDirectory(),
        appSchemaVersion: db.schemaVersion);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Backup checked')),
        content: Text(trf(
            'Made {date}: {sites} sites, {files} photos and bills. Close FieldOS fully and open it again to finish the restore.', {
          'date': fmtDateTime(info.madeAt),
          'sites': '${info.counts['projects'] ?? 0}',
          'files': '${info.files}',
        })),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tr('OK')))],
      ),
    );
  } on BackupProblem catch (e) {
    if (context.mounted) showSnack(context, _problem(e), error: true);
  } catch (e) {
    if (context.mounted) showSnack(context, trf('Restore failed: {error}', {'error': '$e'}), error: true);
  }
}

String _problem(BackupProblem e) => switch (e.message) {
      'This is not a FieldOS backup file.' => tr('This is not a FieldOS backup file.'),
      'This backup was made by a newer FieldOS. Update the app first.' =>
        tr('This backup was made by a newer FieldOS. Update the app first.'),
      'The backup is damaged and was not restored.' => tr('The backup is damaged and was not restored.'),
      'The backup is incomplete and was not restored.' => tr('The backup is incomplete and was not restored.'),
      _ => e.message,
    };
