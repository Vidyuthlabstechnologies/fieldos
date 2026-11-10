/// The site cash book: cash given, spent (the holder's own cash expenses),
/// handed back and counted; shortfalls at counts, spending with no bill,
/// cancellations, what syncs, and the v36 upgrade.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/cash_book.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

late AppDatabase db;
late Project site;

Future<SiteExpense> _spend(String id, double amount, String day, {String by = 'ravi', String? mode = 'cash'}) =>
    db.expenseDao.create(SiteExpensesCompanion.insert(
      id: id,
      projectId: site.id,
      category: 'Petty cash',
      amount: amount,
      incurredOn: day,
      recordedBy: by,
      mode: Value(mode),
      createdAt: Value(DateTime.parse('${day}T12:00:00')),
    ));

Future<CashMove> _move(String kind, double amount, String day, {String holder = 'ravi', int hour = 9}) =>
    db.cashBookDao.record(
      projectId: site.id,
      holderId: holder,
      kind: kind,
      amount: amount,
      movedOn: day,
      by: 'owner',
      now: DateTime.parse('${day}T${hour.toString().padLeft(2, '0')}:00:00'),
    );

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas'));
  });
  tearDown(() => db.close());

  test('given, spent in cash, handed back: what is in hand', () async {
    await _move('given', 20000, '2026-11-02');
    await _spend('e1', 4500, '2026-11-03');
    await _spend('e2', 1200, '2026-11-04');
    await _spend('e3', 9000, '2026-11-04', mode: 'upi'); // not from the cash in hand
    await _spend('e4', 700, '2026-11-04', by: 'someone-else');
    await _move('returned', 5000, '2026-11-05');

    final book = (await loadCashBooks(db, site.id)).single;
    expect(book.holderId, 'ravi');
    expect(book.given, 20000);
    expect(book.spent, 5700);
    expect(book.returned, 5000);
    expect(book.inHand, 9300);
    expect(book.lines.map((l) => l.kind), ['given', 'spent', 'spent', 'returned']);
    expect(book.unexplained(), 0);
  });

  test('a count below the book is unexplained, and the book carries on from what was found', () async {
    await _move('given', 10000, '2026-11-02');
    await _spend('e1', 3000, '2026-11-03');
    await _move('counted', 6200, '2026-11-07', hour: 18); // book says 7000
    await _move('given', 5000, '2026-11-09');
    await _spend('e2', 1000, '2026-11-10');
    await _move('counted', 10200, '2026-11-14', hour: 18); // book says 10200: nothing new missing

    final book = (await loadCashBooks(db, site.id)).single;
    final counts = book.lines.where((l) => l.kind == 'counted').toList();
    expect(counts[0].bookBefore, 7000);
    expect(counts[0].countGap, -800);
    expect(counts[1].bookBefore, 10200);
    expect(counts[1].countGap, 0);
    expect(book.inHand, 10200);
    expect(book.unexplained(), 800);
    expect(book.unexplained(from: '2026-11-09', to: '2026-11-15'), 0);
    expect(book.unexplained(from: '2026-11-02', to: '2026-11-08'), 800);
    expect(book.lastCount!.day, '2026-11-14');
  });

  test('cash spent with no bill attached is flagged; spending before the book started is left out', () async {
    await _spend('early', 999, '2026-10-30');
    await _move('given', 5000, '2026-11-02');
    final billed = await _spend('e1', 1500, '2026-11-03');
    await _spend('e2', 800, '2026-11-03');
    final dir = await Directory.systemTemp.createTemp('fieldos_bill');
    addTearDown(() => dir.delete(recursive: true));
    final f = File('${dir.path}/bill.jpg')..writeAsBytesSync([1, 2, 3]);
    await db.expenseDao.attach(billed.id, f.path);

    final book = (await loadCashBooks(db, site.id)).single;
    expect(book.spent, 2300);
    expect(book.spentWithoutBill(), 800);
    expect(book.lines.where((l) => l.noBill).single.expense!.id, 'e2');
  });

  test('a cancelled entry stays in the book but counts in nothing, and syncs as an update', () async {
    final wrong = await _move('given', 50000, '2026-11-02');
    await _move('given', 5000, '2026-11-02', hour: 10);
    await db.cashBookDao.cancel(wrong.id, reason: 'Typed an extra zero');

    final moves = await db.cashBookDao.forProject(site.id);
    expect(moves.length, 2);
    expect(moves.firstWhere((m) => m.id == wrong.id).voided, isTrue);
    expect((await loadCashBooks(db, site.id)).single.inHand, 5000);

    final outbox = (await db.syncOutboxDao.pending()).where((e) => e.targetTable == 'site_cash_moves').toList();
    expect(outbox.map((e) => e.operation), ['insert', 'insert', 'update']);
    final last = jsonDecode(outbox.last.payload) as Map<String, dynamic>;
    expect(last['voided'], isTrue);
    expect(last['void_reason'], 'Typed an extra zero');
    expect(last['holder_id'], 'ravi');
  });

  test('two people on one site each get their own book', () async {
    await _move('given', 3000, '2026-11-02');
    await _move('given', 4000, '2026-11-02', holder: 'suresh');
    await _spend('e1', 500, '2026-11-03', by: 'suresh');
    final books = await loadCashBooks(db, site.id);
    expect({for (final b in books) b.holderId: b.inHand}, {'ravi': 3000, 'suresh': 3500});
  });

  test('amounts are checked: nothing given is zero, a count may find nothing', () async {
    expect(() => _move('given', 0, '2026-11-02'), throwsArgumentError);
    expect(() => _move('lent', 10, '2026-11-02'), throwsArgumentError);
    final c = await _move('counted', 0, '2026-11-02');
    expect(c.amount, 0);
  });

  test('a row from the server reads back the same', () async {
    final m = await _move('counted', 1234.5, '2026-11-02');
    final json = cashMoveToSupabaseJson(m);
    json['moved_on'] = '2026-11-02';
    await db.cashBookDao.upsertFromRemote(cashMoveFromSupabaseJson(json));
    final back = await db.cashBookDao.byId(m.id);
    expect(back!.amount, 1234.5);
    expect(back.kind, 'counted');
  });

  test('v35 -> v36 upgrade adds the cash book and keeps the site', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v36');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    var d = AppDatabase(NativeDatabase(file));
    final c = await d.companyDao.create('Sai Constructions');
    await d.projectDao.create(ProjectsCompanion.insert(id: 'p', companyId: c.id, name: 'Kompally Villas'));
    await d.customStatement('DROP TABLE cash_moves');
    await d.customStatement('PRAGMA user_version = 32');
    await d.close();

    d = AppDatabase(NativeDatabase(file));
    addTearDown(d.close);
    expect((await d.projectDao.byId('p'))!.name, 'Kompally Villas');
    await d.cashBookDao.record(projectId: 'p', holderId: 'u', kind: 'given', amount: 100, movedOn: '2026-11-10', by: 'o');
    expect((await d.cashBookDao.forProject('p')).single.amount, 100);
  });
}
