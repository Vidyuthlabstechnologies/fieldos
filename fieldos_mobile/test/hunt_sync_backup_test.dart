/// A backup made while the app keeps writing (a sync, or the person saving
/// an entry) is a backup that restores: the manifest counts what the zip's
/// database holds, not what the live one held a moment later.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/data/backup.dart';

const uuid = Uuid();

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fieldos-hunt-backup-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a site saved while the backup is being made does not make it unrestorable', () async {
    final dbPath = p.join(dir.path, 'phone1', 'fieldos.sqlite');
    Directory(p.dirname(dbPath)).createSync(recursive: true);
    final db = AppDatabase(NativeDatabase(File(dbPath)));
    final company = await db.companyDao.create('Sai Constructions');
    await db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));

    final zip = File(p.join(dir.path, 'out', 'fieldos-backup.zip'));
    // Both start together: the backup's copy is taken first, the site is
    // saved right after it.
    final (made, _) = await (
      writeBackup(db, zip, workDir: dir),
      db.projectDao.create(ProjectsCompanion.insert(
          id: uuid.v4(), companyId: company.id, name: 'Bachupally Towers', status: const Value('active'))),
    ).wait;
    await db.close();

    final livePath = p.join(dir.path, 'phone2', 'fieldos.sqlite');
    Directory(p.dirname(livePath)).createSync(recursive: true);
    final info = await stageRestore(zip,
        databasePath: livePath, filesDir: Directory(p.join(dir.path, 'phone2', 'files')), appSchemaVersion: db.schemaVersion);
    expect(info.counts['projects'], made.counts['projects']);
    expect(File(stagedRestorePath(livePath)).existsSync(), isTrue);
  });
}
