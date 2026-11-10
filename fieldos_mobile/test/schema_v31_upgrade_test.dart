/// Upgrading to schema v31 (daily site close, built as v19 and moved after
/// master's v30) adds the day events, close
/// setup and sync status tables, and keeps what the site already had.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v30 -> v31 upgrade adds the daily close tables', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v31');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    final c = await db.companyDao.create('Sai Constructions');
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p', companyId: c.id, name: 'Kompally Villas'));
    for (final t in ['site_day_events', 'site_close_settings', 'member_sync_status']) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement('PRAGMA user_version = 30');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.projectDao.byId('p'))!.name, 'Kompally Villas');
    expect(await db.dayCloseDao.eventsFor('p'), isEmpty);
    await db.dayCloseDao.record(projectId: 'p', workDate: '2026-11-10', kind: 'submitted', by: 'u', siteClosed: true);
    expect((await db.dayCloseDao.eventsFor('p')).single.siteClosed, isTrue);
    final s = await db.dayCloseDao.saveSettings(projectId: 'p', cutoffMinutes: 18 * 60, by: 'pm');
    expect(s.cutoffMinutes, 18 * 60);
  });

  test('a phone that already has the daily close tables is left as it is', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v31b');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    await db.dayCloseDao.record(projectId: 'p', workDate: '2026-11-10', kind: 'submitted', by: 'u');
    await db.customStatement('PRAGMA user_version = 30');
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.dayCloseDao.eventsFor('p')).length, 1);
  });
}
