/// Upgrading to schema v17 (site teams) adds the approval limit to the site
/// roster and the members-only table, keeping roster rows already there.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  test('v16 -> v17 upgrade keeps the roster and adds limits and members-only sites', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v17');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await db.customStatement('DROP TABLE site_access');
    await db.customStatement('DROP TABLE project_members');
    // The roster as it was before v17.
    await db.customStatement('CREATE TABLE project_members (id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL, '
        'user_id TEXT NOT NULL, role TEXT NOT NULL, created_at INTEGER NOT NULL DEFAULT (CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER)))');
    await db.customStatement("INSERT INTO project_members (id, project_id, user_id, role) VALUES ('m1', 'p', 'u', 'site_engineer')");
    await db.customStatement('PRAGMA user_version = 16');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final row = (await db.siteTeamDao.membersFor('p')).single;
    expect(row.role, 'site_engineer');
    expect(row.approvalLimit, isNull);
    await db.siteTeamDao.setMember(projectId: 'p', userId: 'u', role: 'project_manager', approvalLimit: 20000);
    expect((await db.siteTeamDao.memberOf('p', 'u'))!.approvalLimit, 20000);
    await db.siteTeamDao.setMembersOnly('p', true);
    expect(await db.siteTeamDao.isMembersOnly('p'), isTrue);
    await db.close();
  });
}
