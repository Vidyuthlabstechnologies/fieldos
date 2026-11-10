/// Voucher numbers come from the server (audit P0, 2026-11-10), against the
/// local Supabase stack (skips itself if it is not running). Two phones
/// offline on one site both number their next expense the same; once both
/// have synced, in either order, every voucher on the site is unique and
/// both phones show the same numbers.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';

import 'support/cloud_phone.dart';

void main() {
  late bool stackUp;
  setUpAll(() async => stackUp = await localStackReachable());

  Future<SiteExpense> spend(CloudPhone phone, String projectId, double amount) =>
      phone.db.expenseDao.create(SiteExpensesCompanion.insert(
          id: uuid.v4(), projectId: projectId, category: 'Material', amount: amount, incurredOn: '2026-11-10',
          recordedBy: phone.localUserId));

  test('two offline phones, same site, synced in both orders: no duplicate voucher numbers', () async {
    if (!stackUp) return markTestSkipped('local Supabase stack not running');
    final owner = await CloudPhone.signUp('owner');
    final engineer = await CloudPhone.signUp('engineer');
    final company = await owner.db.companyDao.create('Voucher Co');
    final cloud = await owner.service.registerCompany(companyId: company.id, name: company.name);
    final project = await owner.db.projectDao.create(ProjectsCompanion.insert(
        id: uuid.v4(), companyId: company.id, name: 'Villa 4', status: const Value('active')));
    expect((await owner.engine.pushPending()).failed, 0);
    await engineer.service.joinCompany(cloud.joinCode!);
    await engineer.engine.pullAll();

    // Round 1: both offline, both write V-1. Owner syncs first.
    final a1 = await spend(owner, project.id, 100);
    final b1 = await spend(engineer, project.id, 200);
    expect(a1.voucherNo, 1);
    expect(b1.voucherNo, 1, reason: 'each phone only knows its own numbers while offline');
    expect(await owner.db.expenseDao.provisionalVoucherIds(project.id), {a1.id});

    expect((await owner.engine.pushPending()).failed, 0);
    expect((await engineer.engine.pushPending()).failed, 0);
    expect(await owner.db.expenseDao.provisionalVoucherIds(project.id), isEmpty);
    expect((await owner.db.expenseDao.byId(a1.id))!.voucherNo, 1);
    expect((await engineer.db.expenseDao.byId(b1.id))!.voucherNo, 2,
        reason: 'the server renumbered the second V-1 and the phone took the final number at once');

    // Round 2: both offline again, both write V-3. This time the engineer
    // reaches the server first.
    final a2 = await spend(owner, project.id, 300);
    await owner.engine.pullAll(); // nothing new for the owner yet
    final b2 = await spend(engineer, project.id, 400);
    expect(a2.voucherNo, 2, reason: "the owner's phone hasn't seen the engineer's V-2 yet");
    expect(b2.voucherNo, 3);
    expect((await engineer.engine.pushPending()).failed, 0);
    expect((await owner.engine.pushPending()).failed, 0);

    await owner.engine.pullAll();
    await engineer.engine.pullAll();
    Map<String, int?> numbers(List<SiteExpense> rows) => {for (final e in rows) e.id: e.voucherNo};
    final onOwner = numbers(await owner.db.expenseDao.allForProject(project.id));
    final onEngineer = numbers(await engineer.db.expenseDao.allForProject(project.id));
    expect(onOwner, onEngineer, reason: 'both phones show the same number for every expense');
    expect(onOwner.values.toSet(), {1, 2, 3, 4}, reason: 'unique, no gaps');
    expect(onOwner[b2.id], 3);
    expect(onOwner[a2.id], 4);

    // The server's number holds even if a phone later sends another one.
    await engineer.db.expenseDao.edit(b2.id, const SiteExpensesCompanion(note: Value('corrected')), by: engineer.localUserId);
    await engineer.db.customStatement('UPDATE site_expenses SET voucher_no = 99 WHERE id = ?', [b2.id]);
    expect((await engineer.db.syncOutboxDao.pending()), isNotEmpty);
    expect((await engineer.engine.pushPending()).failed, 0);
    final server = await owner.client.from('site_expenses').select('voucher_no').eq('id', b2.id).single();
    expect(server['voucher_no'], 3);

    await owner.close();
    await engineer.close();
  });

  test('provisional label', () {
    expect(voucherLabel(12), 'V-12');
    expect(voucherLabel(12, provisional: true), 'V-12 (provisional)');
    expect(voucherLabel(null, provisional: true), '');
  });
}
