/// Upgrading to schema v30 adds the approval rules and their signatures.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approval_chain.dart';

void main() {
  test('v18 -> v30 upgrade creates the approval tables', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v30');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    for (final t in ['approval_rules', 'approval_steps']) {
      await db.customStatement('DROP TABLE $t');
    }
    await db.customStatement('PRAGMA user_version = 18');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    await db.approvalChainDao.setRule('c', kind: ApprovalKind.expense, role: ApprovalLevel.owner, above: 5000, by: 'o');
    expect((await db.approvalChainDao.rulesFor('c')).single.aboveAmount, 5000);
    await db.approvalChainDao
        .sign(projectId: 'p', kind: ApprovalKind.expense, itemId: 'e', level: ApprovalLevel.owner, approve: true, by: 'o');
    expect(await db.approvalChainDao.stepsFor('p'), hasLength(1));
    await db.close();
  });
}
