/// A whole-phone backup of the FieldOS database, and restoring it.
///
/// A backup is one zip:
/// - `fieldos.sqlite`, a consistent copy made with VACUUM INTO while the
///   app runs;
/// - `manifest.json`: schema version, when it was made, and row counts
///   that are checked on restore;
/// - the photos, bills and slips the records point to, under `files/`.
///
/// Restoring checks the zip before touching anything:
/// - its integrity, and that its schema is not newer than the app;
/// - its row counts against the manifest.
/// The checked database is then staged next to the live one and swapped
/// in the next time the app opens its database (see [applyStagedRestore]),
/// so the live file is never replaced while it is open. File paths inside
/// the restored database are pointed at the restored files.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:fieldos_mobile/data/app_database.dart';

const backupFormat = 1;

/// Tables whose rows are counted in the manifest and checked on restore.
const _countedTables = [
  'companies', 'projects', 'tasks', 'dpr_entries', 'workers', 'labour_attendance', 'site_expenses',
  'material_receipts', 'payments_received', 'client_bills', 'suppliers', 'purchase_orders', 'close_reviews',
  'work_measurements', 'supplier_invoices', 'cost_codes', 'work_claims', 'work_certifications', 'variations',
  'variation_decisions', 'task_constraints', 'drawings', 'drawing_revisions', 'rfis', 'hold_points', 'defects',
  'handover_units', 'sync_outbox',
];

/// (table, column) pairs that hold a path to a file on the phone.
const _fileColumns = [
  ('dpr_photos', 'photo_path'),
  ('expense_attachments', 'file_path'),
  ('receipt_attachments', 'file_path'),
  ('documents', 'file_path'),
  ('commercial_attachments', 'file_path'),
  ('drawing_revisions', 'file_path'),
  ('execution_photos', 'file_path'),
];

class BackupProblem implements Exception {
  const BackupProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

class BackupInfo {
  const BackupInfo({required this.schemaVersion, required this.madeAt, required this.counts, required this.files});
  final int schemaVersion;
  final DateTime madeAt;
  final Map<String, int> counts;
  final int files;
}

Future<Map<String, int>> _countRows(AppDatabase db) async {
  final have = {
    for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()) r.read<String>('name'),
  };
  return {
    for (final t in _countedTables)
      if (have.contains(t)) t: (await db.customSelect('SELECT COUNT(*) AS n FROM "$t"').getSingle()).read<int>('n'),
  };
}

Future<List<String>> _filePaths(AppDatabase db) async {
  final have = {
    for (final r in await db.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get()) r.read<String>('name'),
  };
  final out = <String>{};
  for (final (table, column) in _fileColumns) {
    if (!have.contains(table)) continue;
    final cols = await db.customSelect('PRAGMA table_info("$table")').get();
    if (!cols.any((c) => c.read<String>('name') == column)) continue;
    for (final r in await db.customSelect('SELECT "$column" AS f FROM "$table" WHERE "$column" IS NOT NULL').get()) {
      final f = r.read<String>('f');
      if (f.isNotEmpty && File(f).existsSync()) out.add(f);
    }
  }
  return out.toList()..sort();
}

/// Writes a backup of [db] to [outFile] (a .zip) and returns what is in it.
/// [workDir]: somewhere to put the temporary database copy.
Future<BackupInfo> writeBackup(AppDatabase db, File outFile, {required Directory workDir, DateTime? now}) async {
  final copy = File(p.join(workDir.path, 'fieldos-backup-${DateTime.now().microsecondsSinceEpoch}.sqlite'));
  if (copy.existsSync()) copy.deleteSync();
  await db.customStatement('VACUUM INTO ?', [copy.path]);
  try {
    _stripCredentials(copy);
    final counts = await _countRows(db);
    final files = await _filePaths(db);
    final info = BackupInfo(schemaVersion: db.schemaVersion, madeAt: now ?? DateTime.now(), counts: counts, files: files.length);
    final archive = Archive()
      ..addFile(ArchiveFile.bytes('fieldos.sqlite', copy.readAsBytesSync()))
      ..addFile(ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': backupFormat,
            'schema_version': info.schemaVersion,
            'made_at': info.madeAt.toUtc().toIso8601String(),
            'counts': counts,
            'files': {for (var i = 0; i < files.length; i++) 'files/$i${p.extension(files[i])}': files[i]},
          })));
    for (var i = 0; i < files.length; i++) {
      archive.addFile(ArchiveFile.bytes('files/$i${p.extension(files[i])}', File(files[i]).readAsBytesSync()));
    }
    final bytes = ZipEncoder().encode(archive);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsBytesSync(bytes, flush: true);
    return info;
  } finally {
    if (copy.existsSync()) copy.deleteSync();
  }
}

/// Settings rows that are sign-ins, never data: the cloud session holds a
/// live refresh token, so whoever got a forwarded backup zip would be
/// signed in to the company's cloud without a password. Left out of every
/// backup and dropped from every restore; after a restore the person signs
/// in again.
const backupCredentialSettings = {'cloud_session'};

void _stripCredentials(File databaseFile) {
  final raw = sqlite3.open(databaseFile.path);
  try {
    final hasSettings = raw.select("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'app_settings'").isNotEmpty;
    if (!hasSettings) return;
    final marks = List.filled(backupCredentialSettings.length, '?').join(',');
    raw.execute('DELETE FROM app_settings WHERE key IN ($marks)', backupCredentialSettings.toList());
    // Rewrite the file so the deleted value is not left in a free page.
    raw.execute('VACUUM');
  } finally {
    raw.close();
  }
}

/// Where a checked restore waits until the database is next opened.
String stagedRestorePath(String databasePath) => '$databasePath.restore';

/// Checks [backup] and stages it to replace the database at
/// [databasePath] on next open. Files go under [filesDir], and the
/// restored records point at them. Nothing live changes here.
Future<BackupInfo> stageRestore(File backup, {required String databasePath, required Directory filesDir, required int appSchemaVersion}) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(backup.readAsBytesSync());
  } catch (_) {
    throw const BackupProblem('This is not a FieldOS backup file.');
  }
  final manifestFile = archive.findFile('manifest.json');
  final dbFile = archive.findFile('fieldos.sqlite');
  if (manifestFile == null || dbFile == null) throw const BackupProblem('This is not a FieldOS backup file.');
  final Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
  } catch (_) {
    throw const BackupProblem('This is not a FieldOS backup file.');
  }
  if ((manifest['format'] as int? ?? 0) > backupFormat) {
    throw const BackupProblem('This backup was made by a newer FieldOS. Update the app first.');
  }
  final version = manifest['schema_version'] as int? ?? 0;
  if (version > appSchemaVersion) throw const BackupProblem('This backup was made by a newer FieldOS. Update the app first.');

  final staged = File(stagedRestorePath(databasePath));
  if (staged.existsSync()) staged.deleteSync();
  staged.writeAsBytesSync(dbFile.content as List<int>, flush: true);

  // Check the copy: integrity, and the rows the manifest promises.
  AppDatabaseCheck? check;
  Directory? written;
  try {
    try {
      check = AppDatabaseCheck(staged);
    } catch (_) {
      throw const BackupProblem('The backup is damaged and was not restored.');
    }
    final ok = await check.integrity();
    if (!ok) throw const BackupProblem('The backup is damaged and was not restored.');
    if (check.userVersion != version) throw const BackupProblem('The backup is damaged and was not restored.');
    final counts = Map<String, int>.from(manifest['counts'] as Map);
    final found = await check.counts(counts.keys);
    for (final e in counts.entries) {
      if (found[e.key] != e.value) throw const BackupProblem('The backup is incomplete and was not restored.');
    }

    // Bring the files back and point the records at them.
    // A folder of its own per restore, so files an earlier restore
    // brought back are never overwritten.
    final into = Directory(p.join(filesDir.path, 'restored-${DateTime.now().millisecondsSinceEpoch}'))
      ..createSync(recursive: true);
    written = into;
    final paths = Map<String, String>.from(manifest['files'] as Map? ?? const {});
    var restored = 0;
    final moves = <String, String>{};
    for (final e in paths.entries) {
      final f = archive.findFile(e.key);
      if (f == null) continue;
      final dest = File(p.join(into.path, p.basename(e.key)));
      dest.writeAsBytesSync(f.content as List<int>, flush: true);
      moves[e.value] = dest.path;
      restored++;
    }
    await check.repoint(moves);
    // Backups made before 1.7.4 still carry the sign-in.
    await check.close();
    _stripCredentials(staged);
    return BackupInfo(
      schemaVersion: version,
      madeAt: DateTime.parse(manifest['made_at'] as String).toLocal(),
      counts: counts,
      files: restored,
    );
  } catch (e) {
    await check?.close();
    if (staged.existsSync()) staged.deleteSync();
    if (written != null && written.existsSync()) written.deleteSync(recursive: true);
    rethrow;
  } finally {
    await check?.close();
  }
}

/// Swaps a staged restore in before the database opens. Returns true when
/// it did. The replaced database is kept beside it as `.before-restore`.
bool applyStagedRestore(String databasePath) {
  final staged = File(stagedRestorePath(databasePath));
  if (!staged.existsSync()) return false;
  final live = File(databasePath);
  if (live.existsSync()) {
    final keep = File('$databasePath.before-restore');
    if (keep.existsSync()) keep.deleteSync();
    live.renameSync(keep.path);
  }
  for (final suffix in ['-wal', '-shm', '-journal']) {
    final f = File('$databasePath$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  staged.renameSync(databasePath);
  return true;
}

/// Raw access to a staged database file, for checking it. Plain sqlite3,
/// not drift, so opening it can't touch its schema version.
class AppDatabaseCheck {
  AppDatabaseCheck(File file) : _db = sqlite3.open(file.path);
  final Database _db;
  bool _closed = false;

  Set<String> _tables() => {for (final r in _db.select("SELECT name FROM sqlite_master WHERE type = 'table'")) r['name'] as String};

  Future<bool> integrity() async {
    try {
      return _db.select('PRAGMA integrity_check').first.values.first == 'ok';
    } on SqliteException {
      return false;
    }
  }

  int get userVersion => _db.userVersion;

  Future<Map<String, int>> counts(Iterable<String> tables) async {
    final have = _tables();
    return {
      for (final t in tables)
        if (have.contains(t)) t: _db.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int,
    };
  }

  Future<void> repoint(Map<String, String> moves) async {
    if (moves.isEmpty) return;
    final have = _tables();
    for (final (table, column) in _fileColumns) {
      if (!have.contains(table)) continue;
      final stmt = _db.prepare('UPDATE "$table" SET "$column" = ? WHERE "$column" = ?');
      for (final e in moves.entries) {
        stmt.execute([e.value, e.key]);
      }
      stmt.close();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _db.close();
  }
}
