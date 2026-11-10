/// The databases phones already have, upgraded to today's schema in one go
/// (issue #145). Each fixture was created by the shipped build's own code
/// and then given one row in every table (tool/upgrade_fixtures/):
///   v9  = 1.6.3 (build 11), still on closed testing
///   v14 = 1.6.6 and 1.7.0 (builds 14, 15)
///   v32 = 1.7.1 and 1.7.2 (builds 16, 17)
/// A failed upgrade locks a person out of every record on their phone, and
/// no later update can reach them, so this checks the whole walk: it opens,
/// no row is lost, and the result matches a fresh install's schema exactly.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:fieldos_mobile/data/app_database.dart';

Future<Map<String, int>> _counts(AppDatabase db) async => {
      for (final r in await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
          .get())
        r.read<String>('name'): (await db.customSelect('SELECT COUNT(*) AS n FROM "${r.read<String>('name')}"').getSingle())
            .read<int>('n'),
    };

/// Table -> its columns (name, type, not null, default, primary key) and
/// the names of its indexes and triggers.
Future<Map<String, String>> _schema(AppDatabase db) async {
  final out = <String, String>{};
  final objects = await db
      .customSelect("SELECT type, name, tbl_name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name")
      .get();
  for (final o in objects) {
    final type = o.read<String>('type');
    final name = o.read<String>('name');
    if (type == 'table') {
      final cols = await db.customSelect('PRAGMA table_info("$name")').get();
      final fks = await db.customSelect('PRAGMA foreign_key_list("$name")').get();
      final lines = <String>[
        for (final c in cols)
          '${c.read<String>('name')} ${c.read<String>('type')} nn=${c.read<int>('notnull')} '
              'd=${c.readNullable<String>('dflt_value')} pk=${c.read<int>('pk')}',
        for (final f in fks) 'fk ${f.read<String>('from')}->${f.read<String>('table')}.${f.readNullable<String>('to')}',
      ]..sort(); // an added column sits at the end of an upgraded table
      out['table $name'] = lines.join('\n');
    } else {
      out['$type $name'] = o.read<String>('tbl_name');
    }
  }
  return out;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('fieldos-upgrade-'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Map<String, String>> freshSchema() async {
    final fresh = AppDatabase(NativeDatabase(File(p.join(dir.path, 'fresh.sqlite'))));
    final s = await _schema(fresh);
    await fresh.close();
    return s;
  }

  for (final version in [9, 14, 32]) {
    test('a phone on schema v$version upgrades with every row kept and a fresh install\'s schema', () async {
      final file = File(p.join(dir.path, 'v$version.sqlite'))
        ..writeAsBytesSync(gzip.decode(File('test/fixtures/upgrade/fieldos_v$version.sqlite.gz').readAsBytesSync()));

      // What the old build left, read before the app touches it.
      final old = sqlite3.open(file.path);
      final oldCounts = {
        for (final r in old.select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"))
          r['name'] as String: old.select('SELECT COUNT(*) AS n FROM "${r['name']}"').first['n'] as int,
      };
      final oldVersion = old.userVersion;
      old.close();
      expect(oldVersion, version);
      expect(oldCounts.values.every((n) => n == 1), isTrue, reason: 'fixture has one row per table');

      final db = AppDatabase(NativeDatabase(file));
      final newCounts = await _counts(db);
      expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), db.schemaVersion);

      for (final e in oldCounts.entries) {
        if (!newCounts.containsKey(e.key)) continue; // a table a later version dropped on purpose
        expect(newCounts[e.key], greaterThanOrEqualTo(e.value), reason: '${e.key} lost rows in the upgrade from v$version');
      }
      final project = (await db.select(db.projects).get()).single;
      expect(project.name, 'projects.name');
      expect((await db.customSelect('PRAGMA foreign_key_check').get()), isEmpty);
      expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');

      final upgraded = await _schema(db);
      await db.close();
      final fresh = await freshSchema();
      expect(upgraded.keys.toSet().difference(fresh.keys.toSet()), isEmpty, reason: 'left over after upgrade from v$version');
      expect(fresh.keys.toSet().difference(upgraded.keys.toSet()), isEmpty, reason: 'missing after upgrade from v$version');
      for (final k in fresh.keys) {
        expect(upgraded[k], fresh[k], reason: '$k differs after upgrade from v$version');
      }
    });
  }
}
