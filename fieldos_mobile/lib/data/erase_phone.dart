/// Erasing everything FieldOS keeps on this phone, for Forgot PIN on a
/// phone that cannot sign in to its cloud account
/// (lib/features/security/pin_reset.dart). After it the app is as on first
/// launch: language, then log in or create an account.
///
/// Everything is in two places: the database (every record, the settings
/// with the PIN and the cloud session) and the app's own folders (photos,
/// bills, documents, PDFs and backups made for sharing). There is no
/// keychain or secure storage to clear.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fieldos_mobile/data/app_database.dart';

class PhoneEraser {
  PhoneEraser(
    this._db, {
    Future<String> Function()? databasePath,
    Future<List<Directory>> Function()? folders,
  })  : _databasePath = databasePath ?? appDatabasePath,
        _folders = folders ?? _appFolders;

  final AppDatabase _db;
  final Future<String> Function() _databasePath;
  final Future<List<Directory>> Function() _folders;

  static Future<List<Directory>> _appFolders() async => [
        await getApplicationDocumentsDirectory(),
        await getTemporaryDirectory(),
      ];

  /// Files first, then the database in one go. Killed half-way, the phone
  /// still has its PIN (it is in the database) and no photos left behind
  /// for anyone: erasing again finishes the job.
  Future<void> erase() async {
    await _deleteFiles();
    await _wipeDatabase();
  }

  Future<void> _deleteFiles() async {
    final db = await _databasePath();
    // The open database stays (its rows are wiped next); a kept-aside copy
    // from a restore, or a restore waiting to go in, are old data.
    final live = {db, '$db-wal', '$db-shm', '$db-journal'};
    for (final dir in await _folders()) {
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(followLinks: false)) {
        if (live.contains(e.path) || live.contains(p.normalize(e.path))) continue;
        try {
          e.deleteSync(recursive: true);
        } on FileSystemException {
          // A file the system holds open (rare in temp); the rest still go.
        }
      }
    }
  }

  Future<void> _wipeDatabase() async {
    // Read-only mode refuses the person's own changes; erasing is not one.
    await WriteGuard.serverSync(() async {
      // Deleted rows are overwritten, not left readable in free pages.
      await _db.customStatement('PRAGMA secure_delete = ON');
      await _db.transaction(() async {
        for (final t in _db.allTables) {
          await _db.delete(t).go();
        }
      });
      await _db.customStatement('VACUUM');
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    });
  }
}
