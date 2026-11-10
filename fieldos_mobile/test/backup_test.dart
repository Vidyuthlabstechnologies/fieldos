/// Backup and restore: a backup made while the app runs restores to the
/// same records and files on a fresh phone, and a damaged, incomplete or
/// newer backup is refused without touching the live database.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  setUp(() => dir = Directory.systemTemp.createTempSync('fieldos-backup-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(AppDatabase, String)> seeded() async {
    final dbPath = p.join(dir.path, 'phone1', 'fieldos.sqlite');
    Directory(p.dirname(dbPath)).createSync(recursive: true);
    final db = AppDatabase(NativeDatabase(File(dbPath)));
    final company = await db.companyDao.create('Sai Constructions');
    final site = await db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Kompally Villas', status: const Value('active')));
    final expense = await db.expenseDao.create(SiteExpensesCompanion.insert(
        id: uuid.v4(), projectId: site.id, category: 'Material', amount: 6400, incurredOn: '2026-11-10', recordedBy: 'me'));
    final bill = File(p.join(dir.path, 'phone1', 'sand-bill.pdf'))..writeAsStringSync('%PDF-1.4 sand bill');
    await db.expenseDao.attach(expense.id, bill.path, mimeType: 'application/pdf');
    return (db, bill.path);
  }

  test('a backup restores the same records and files on another phone', () async {
    final (db, billPath) = await seeded();
    final zip = File(p.join(dir.path, 'out', 'fieldos-backup.zip'));
    final made = await writeBackup(db, zip, workDir: dir);
    expect(made.counts['projects'], 1);
    expect(made.counts['site_expenses'], 1);
    expect(made.files, 1);
    await db.close();

    // Another phone, with a different database already on it.
    final livePath = p.join(dir.path, 'phone2', 'fieldos.sqlite');
    Directory(p.dirname(livePath)).createSync(recursive: true);
    var live = AppDatabase(NativeDatabase(File(livePath)));
    await live.companyDao.create('Old company');
    await live.close();

    final info = await stageRestore(zip,
        databasePath: livePath, filesDir: Directory(p.join(dir.path, 'phone2', 'files')), appSchemaVersion: db.schemaVersion);
    expect(info.files, 1);
    // Nothing live changed yet.
    live = AppDatabase(NativeDatabase(File(livePath)));
    expect((await live.select(live.companies).get()).single.name, 'Old company');
    await live.close();

    expect(applyStagedRestore(livePath), isTrue);
    expect(File('$livePath.before-restore').existsSync(), isTrue);
    expect(applyStagedRestore(livePath), isFalse, reason: 'only once');
    live = AppDatabase(NativeDatabase(File(livePath)));
    expect((await live.select(live.companies).get()).single.name, 'Sai Constructions');
    final expense = (await live.select(live.siteExpenses).get()).single;
    final att = (await live.expenseDao.attachmentsFor(expense.id)).single;
    expect(att.filePath, isNot(billPath));
    expect(att.filePath, startsWith(p.join(dir.path, 'phone2', 'files')));
    expect(File(att.filePath).readAsStringSync(), '%PDF-1.4 sand bill');
    await live.close();
  });

  Future<File> rewrite(File zip, void Function(Archive a, Map<String, dynamic> manifest) change) async {
    final a = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    final manifest = jsonDecode(utf8.decode(a.findFile('manifest.json')!.content as List<int>)) as Map<String, dynamic>;
    final out = Archive();
    change(out, manifest);
    for (final f in a.files) {
      if (f.name == 'manifest.json' || out.findFile(f.name) != null) continue;
      out.addFile(ArchiveFile.bytes(f.name, f.content as List<int>));
    }
    out.addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)));
    final file = File(p.join(dir.path, 'changed-${DateTime.now().microsecondsSinceEpoch}.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(out));
    return file;
  }

  test('a damaged, incomplete or newer backup is refused and nothing is staged', () async {
    final (db, _) = await seeded();
    final zip = File(p.join(dir.path, 'fieldos-backup.zip'));
    await writeBackup(db, zip, workDir: dir);
    final version = db.schemaVersion;
    await db.close();
    final livePath = p.join(dir.path, 'phone2', 'fieldos.sqlite');
    Directory(p.dirname(livePath)).createSync(recursive: true);
    final filesDir = Directory(p.join(dir.path, 'phone2', 'files'));

    Future<void> refused(File f, String message) async {
      await expectLater(stageRestore(f, databasePath: livePath, filesDir: filesDir, appSchemaVersion: version),
          throwsA(isA<BackupProblem>().having((e) => e.message, 'message', contains(message))));
      expect(File(stagedRestorePath(livePath)).existsSync(), isFalse);
      expect(applyStagedRestore(livePath), isFalse);
    }

    await refused(File(p.join(dir.path, 'x.zip'))..writeAsStringSync('not a zip'), 'not a FieldOS backup');
    await refused(await rewrite(zip, (_, m) => m['schema_version'] = version + 1), 'newer FieldOS');
    await refused(await rewrite(zip, (_, m) => (m['counts'] as Map)['site_expenses'] = 2), 'incomplete');
    await refused(
        await rewrite(zip, (a, _) => a.addFile(ArchiveFile.bytes('fieldos.sqlite', utf8.encode('garbage' * 200)))), 'damaged');
    expect(filesDir.existsSync() ? filesDir.listSync() : const [], isEmpty, reason: 'no files left behind');
  });
}
