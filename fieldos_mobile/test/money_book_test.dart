import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';
import 'package:fieldos_mobile/features/money/voucher_pdf.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

/// The money book, from Onsite's Play reviews: GST as CGST/SGST/IGST with
/// auto calculation, a voucher number on every entry, a filter that shows
/// its total, a breakdown by category, the company's own categories, and
/// a way to correct or cancel a wrong entry without losing the trail.
SiteExpense _e(
  String id, {
  String category = 'Material',
  double amount = 100,
  String day = '2026-11-08',
  String? workerId,
  String? paidTo,
  String? note,
  int? voucherNo,
  bool voided = false,
  DateTime? createdAt,
}) =>
    SiteExpense(
      id: id,
      projectId: 'p',
      category: category,
      amount: amount,
      incurredOn: day,
      recordedBy: 'u',
      note: note,
      workerId: workerId,
      paidTo: paidTo,
      gstInterState: false,
      voucherNo: voucherNo,
      voided: voided,
      createdAt: createdAt ?? DateTime(2026, 11, 8, 10),
    );

var _n = 0;

void main() {
  group('GST', () {
    test('a GST-inclusive total splits into CGST and SGST that add back exactly', () {
      final s = gstSplit(1180, 18);
      expect(s.taxable, 1000);
      expect(s.cgst, 90);
      expect(s.sgst, 90);
      expect(s.igst, 0);
      expect(s.tax, 180);
    });

    test('odd amounts round to paise and still add back to what was paid', () {
      for (final total in [999.0, 1234.57, 1.0, 87650.0]) {
        for (final rate in gstRates) {
          final s = gstSplit(total, rate);
          expect(((s.taxable + s.cgst + s.sgst) * 100).round(), (total * 100).round(), reason: '$total at $rate%');
          expect((s.cgst - s.sgst).abs(), lessThanOrEqualTo(0.011));
        }
      }
    });

    test('a supplier from another state is all IGST', () {
      final s = gstSplit(1120, 12, interState: true);
      expect(s.taxable, 1000);
      expect(s.igst, 120);
      expect(s.cgst + s.sgst, 0);
    });

    test('an amount typed before GST gets GST added', () {
      expect(withGst(1000, 18), 1180);
      expect(withGst(250.5, 5), 263.03);
      expect(gstSplit(500, 0).taxable, 500);
    });
  });

  group('filters and totals', () {
    final now = DateTime(2026, 11, 8, 12); // a Sunday
    final all = [
      _e('a', amount: 1000, day: '2026-11-08', voucherNo: 5, paidTo: 'Sri Balaji Hardware'),
      _e('b', category: 'Labour', amount: 800, day: '2026-11-03', workerId: 'w1', voucherNo: 4),
      _e('c', category: 'Fuel', amount: 300, day: '2026-10-28', voucherNo: 3, note: 'JCB diesel'),
      _e('d', category: 'Fuel', amount: 999, day: '2026-11-07', voucherNo: 6, voided: true),
      _e('e', category: 'Labour', amount: 650, day: '2026-09-30', voucherNo: 1),
    ];

    test('periods: this week starts Monday, months are calendar months', () {
      ids(MoneyFilter f) => f.expenses(all, now: now).map((e) => e.id).toList();
      expect(ids(const MoneyFilter()), ['a', 'd', 'b', 'c', 'e']); // newest first
      expect(ids(const MoneyFilter(period: MoneyPeriod.thisWeek)), ['a', 'd', 'b']);
      expect(ids(const MoneyFilter(period: MoneyPeriod.thisMonth)), ['a', 'd', 'b']);
      expect(ids(const MoneyFilter(period: MoneyPeriod.lastMonth)), ['c']);
      expect(
          ids(MoneyFilter(period: MoneyPeriod.custom, from: DateTime(2026, 9, 30), to: DateTime(2026, 10, 28))),
          ['c', 'e']); // both ends included
    });

    test('a January "last month" is December of the year before', () {
      final r = const MoneyFilter(period: MoneyPeriod.lastMonth).range(DateTime(2027, 1, 15))!;
      expect(r.$1, DateTime(2026, 12));
      expect(r.$2, DateTime(2027, 1));
    });

    test('category, worker and search narrow the list; the total leaves cancelled entries out', () {
      final fuel = const MoneyFilter(category: 'Fuel').expenses(all, now: now);
      expect(fuel.map((e) => e.id), ['d', 'c']);
      expect(totalOf(fuel), 300); // the cancelled 999 doesn't count
      expect(const MoneyFilter(workerId: 'w1').expenses(all, now: now).single.id, 'b');

      search(String q) => MoneyFilter(query: q).expenses(all, now: now, workerName: {'w1': 'Suresh'}).map((e) => e.id);
      expect(search('balaji'), ['a']);
      expect(search('v-3'), ['c']);
      expect(search('suresh'), ['b']);
      expect(search('diesel'), ['c']);
      expect(search('650'), ['e']);
      expect(search('nothing like this'), isEmpty);

      expect(const MoneyFilter(showCancelled: false).expenses(all, now: now).map((e) => e.id), isNot(contains('d')));
    });

    test('copyWith can clear a category or worker, and isEmpty knows a fresh filter', () {
      const f = MoneyFilter(category: 'Fuel', workerId: 'w1');
      expect(f.isEmpty, isFalse);
      final cleared = f.copyWith(category: null, workerId: null);
      expect(cleared.category, isNull);
      expect(cleared.workerId, isNull);
      expect(cleared.isEmpty, isTrue);
      expect(f.copyWith(query: 'x').category, 'Fuel'); // untouched fields stay
    });

    test('breakdown by category: biggest first, shares add to one, cancelled left out', () {
      final b = categoryBreakdown(all);
      expect(b.map((c) => c.category), ['Labour', 'Material', 'Fuel']);
      expect(b.first.amount, 1450);
      expect(b.first.count, 2);
      expect(b.last.amount, 300);
      expect(b.fold(0.0, (s, c) => s + c.share), closeTo(1, 1e-9));
      expect(categoryBreakdown(const []), isEmpty);
    });

    test('money received: period, search, and cancelled payments out of the total', () {
      PaymentsReceivedData p(String id, DateTime on, double amt, {bool voided = false}) => PaymentsReceivedData(
          id: id,
          projectId: 'p',
          amount: amt,
          receivedOn: on,
          fromParty: 'Mr Rao',
          mode: 'upi',
          recordedBy: 'u',
          voided: voided,
          createdAt: on);
      final rows = [
        p('r1', DateTime(2026, 11, 2), 50000),
        p('r2', DateTime(2026, 10, 2), 20000),
        p('r3', DateTime(2026, 11, 5), 9000, voided: true),
      ];
      final nov = const MoneyFilter(period: MoneyPeriod.thisMonth).payments(rows, now: now);
      expect(nov.map((x) => x.id), ['r3', 'r1']);
      expect(totalReceived(nov), 50000);
      expect(const MoneyFilter(query: 'rao').payments(rows, now: now), hasLength(3));
    });
  });

  group('categories', () {
    test('defaults, then the company\'s own, then any used on the site, with Other last', () {
      final c = categoriesToOffer(custom: ['Shuttering hire', 'material'], used: [_e('x', category: 'Electrician')]);
      expect(c.take(6), ['Material', 'Labour', 'Transport', 'Equipment hire', 'Food & tea', 'Fuel']);
      expect(c, containsAllInOrder(['Shuttering hire', 'Electrician', 'Other']));
      expect(c.last, 'Other');
      expect(c.where((x) => x.toLowerCase() == 'material'), hasLength(1));
    });

    test('a company adds and removes its own categories, kept on the phone', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      expect(await addCustomCategory(db, 'c', '  Plumber   work '), 'Plumber work');
      expect(await addCustomCategory(db, 'c', 'plumber WORK'), isNull); // already there
      expect(await addCustomCategory(db, 'c', 'fuel'), isNull); // a default
      expect(await addCustomCategory(db, 'c', '   '), isNull);
      expect((await addCustomCategory(db, 'c', 'x' * 80))!.length, 50);
      expect(await loadCustomCategories(db, 'c'), ['Plumber work', 'x' * 50]);
      expect(await loadCustomCategories(db, 'other company'), isEmpty);
      await removeCustomCategory(db, 'c', 'Plumber work');
      expect(await loadCustomCategories(db, 'c'), ['x' * 50]);
    });
  });

  group('the book on the phone', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    Future<SiteExpense> add(String project, {double amount = 100}) => db.expenseDao.create(SiteExpensesCompanion.insert(
        id: 'e${++_n}',
        projectId: project, category: 'Fuel', amount: amount, incurredOn: '2026-11-08', recordedBy: 'u'));

    test('every entry gets the next voucher number of its own site', () async {
      expect((await add('p1')).voucherNo, 1);
      expect((await add('p1')).voucherNo, 2);
      expect((await add('p2')).voucherNo, 1);
      // A teammate's entry synced in moves the count on.
      await db.expenseDao.upsertFromRemote(SiteExpensesCompanion.insert(
          id: 'remote', projectId: 'p1', category: 'Fuel', amount: 1, incurredOn: '2026-11-08', recordedBy: 'u2',
          voucherNo: const Value(7)));
      expect((await add('p1')).voucherNo, 8);
      expect(voucherLabel(8), 'V-8');
      expect(voucherLabel(null), '');
    });

    test('a correction keeps the voucher number, site and author, and goes to the cloud as an update', () async {
      final e = await add('p1', amount: 100);
      final fixed = await db.expenseDao.edit(
          e.id,
          const SiteExpensesCompanion(
            amount: Value(1180),
            paidTo: Value('Balaji'),
            gstPct: Value(18),
            projectId: Value('somewhere-else'),
            voucherNo: Value(99),
            recordedBy: Value('someone'),
          ),
          by: 'pm',
          now: DateTime(2026, 11, 9, 10));
      expect(fixed.amount, 1180);
      expect(fixed.paidTo, 'Balaji');
      expect(fixed.projectId, 'p1');
      expect(fixed.voucherNo, e.voucherNo);
      expect(fixed.recordedBy, 'u');
      expect(fixed.editedBy, 'pm');
      expect(fixed.editedAt, DateTime(2026, 11, 9, 10));

      final queued = await db.syncOutboxDao.pending();
      expect(queued.map((o) => o.operation), ['insert', 'update']);
      final payload = jsonDecode(queued.last.payload) as Map<String, dynamic>;
      expect(payload['amount'], 1180);
      expect(payload['gst_pct'], 18);
      expect(payload['edited_by'], 'pm');
    });

    test('a cancelled entry stays in the book, counts in no total, and can be restored', () async {
      final keep = await add('p1', amount: 500);
      final wrong = await add('p1', amount: 999);
      await db.expenseDao.setVoided(wrong.id, voided: true, reason: 'entered twice ${'!' * 300}', by: 'u');

      expect((await db.expenseDao.forProject('p1')).map((e) => e.id), [keep.id]);
      final book = await db.expenseDao.allForProject('p1');
      final cancelled = book.firstWhere((e) => e.id == wrong.id);
      expect(cancelled.voided, isTrue);
      expect(cancelled.voidReason!.length, 200);
      expect(cancelled.voidReason, startsWith('entered twice'));

      final back = await db.expenseDao.setVoided(wrong.id, voided: false, by: 'u');
      expect(back.voided, isFalse);
      expect(back.voidReason, isNull);
      expect(await db.expenseDao.forProject('p1'), hasLength(2));
      expect((await db.syncOutboxDao.pending()).where((o) => o.operation == 'update'), hasLength(2));
    });

    test('money received: corrected and cancelled the same way', () async {
      final p = await db.paymentDao.create(PaymentsReceivedCompanion.insert(
          id: 'r1',
          projectId: 'p1', amount: 50000, receivedOn: DateTime(2026, 11, 2), fromParty: 'Mr Rao', mode: 'upi',
          recordedBy: 'u'));
      final fixed = await db.paymentDao.edit(p.id, const PaymentsReceivedCompanion(amount: Value(45000)), by: 'owner');
      expect(fixed.amount, 45000);
      expect(fixed.recordedBy, 'u');
      await db.paymentDao.setVoided(p.id, voided: true, reason: 'cheque bounced', by: 'owner');
      expect(await db.paymentDao.forProject('p1'), isEmpty);
      expect((await db.paymentDao.allForProject('p1')).single.voidReason, 'cheque bounced');
    });
  });

  group('sync', () {
    test('a plain entry sends only the old columns, so it syncs to a cloud not yet upgraded', () {
      final json = siteExpenseToSupabaseJson(_e('a'));
      for (final k in ['paid_to', 'mode', 'gst_pct', 'voucher_no', 'voided', 'void_reason', 'edited_at', 'edited_by']) {
        expect(json.containsKey(k), isFalse, reason: k);
      }
    });

    test('an entry using the money book sends its new columns', () {
      final json = siteExpenseToSupabaseJson(_e('a', voucherNo: 3, paidTo: 'Balaji', voided: true));
      expect(json['voucher_no'], 3);
      expect(json['paid_to'], 'Balaji');
      expect(json['voided'], true);
      expect(json['gst_inter_state'], false);
    });

    test('pulling from a cloud without the new columns leaves the phone\'s values alone', () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final mine = await db.expenseDao.create(SiteExpensesCompanion.insert(
          id: 'mine', projectId: 'p', category: 'Fuel', amount: 300, incurredOn: '2026-11-08', recordedBy: 'u',
          paidTo: const Value('Balaji')));
      final old = siteExpenseToSupabaseJson(mine)
        ..removeWhere((k, _) => ['paid_to', 'mode', 'gst_pct', 'gst_inter_state', 'voucher_no', 'voided', 'void_reason', 'edited_at', 'edited_by'].contains(k))
        ..['created_at'] = mine.createdAt.toUtc().toIso8601String()
        ..['note'] = 'from the cloud';
      await db.expenseDao.upsertFromRemote(siteExpenseFromSupabaseJson(old));
      final row = (await db.expenseDao.byId(mine.id))!;
      expect(row.note, 'from the cloud');
      expect(row.paidTo, 'Balaji');
      expect(row.voucherNo, 1);

      // A cloud that has the columns but hasn't numbered the row yet
      // doesn't take the phone's voucher number away either.
      await db.expenseDao.upsertFromRemote(siteExpenseFromSupabaseJson({...old, 'voucher_no': null, 'voided': true}));
      final again = (await db.expenseDao.byId(mine.id))!;
      expect(again.voucherNo, 1);
      expect(again.voided, isTrue);
    });

    test('payments send their new columns only once cancelled or corrected', () {
      final p = PaymentsReceivedData(
          id: 'r', projectId: 'p', amount: 1, receivedOn: DateTime(2026, 11, 2), fromParty: 'Rao', mode: 'upi',
          recordedBy: 'u', voided: false, createdAt: DateTime(2026, 11, 2));
      expect(paymentReceivedToSupabaseJson(p).containsKey('voided'), isFalse);
      expect(paymentReceivedToSupabaseJson(p.copyWith(voided: true))['voided'], true);
    });
  });

  test('upgrading to v10 numbers the vouchers already on the phone, per site, in date order', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v10');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    Future<void> put(String id, String project, String day) => db.into(db.siteExpenses).insert(
        SiteExpensesCompanion.insert(id: id, projectId: project, category: 'Fuel', amount: 1, incurredOn: day, recordedBy: 'u'));
    await put('late', 'p1', '2026-11-05');
    await put('early', 'p1', '2026-11-01');
    await put('other', 'p2', '2026-11-03');
    await db.customStatement('PRAGMA user_version = 9');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    final p1 = {for (final e in await db.expenseDao.allForProject('p1')) e.id: e.voucherNo};
    expect(p1, {'early': 1, 'late': 2});
    expect((await db.expenseDao.allForProject('p2')).single.voucherNo, 1);
    expect((await db.expenseDao.create(SiteExpensesCompanion.insert(
            id: 'new', projectId: 'p1', category: 'Fuel', amount: 1, incurredOn: '2026-11-08', recordedBy: 'u')))
        .voucherNo, 3);
    await db.close();
  });

  group('voucher PDF', () {
    test('names who was paid: the worker first, else the typed name', () {
      expect(voucherPayee(_e('a', workerId: 'w1', paidTo: 'typed'), workerName: 'Suresh'), 'Suresh');
      expect(voucherPayee(_e('a', paidTo: '  Balaji  ')), 'Balaji');
      expect(voucherPayee(_e('a')), '');
    });

    test('builds a PDF for a GST bill and for a cancelled entry', () async {
      final gst = _e('a', amount: 1180, voucherNo: 12, paidTo: 'Balaji').copyWith(gstPct: const Value(18), mode: const Value('upi'));
      final bytes = await buildVoucherPdf(expense: gst, companyName: 'Sri Sai Constructions', siteName: 'Tower B', enteredBy: 'Ravi');
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final cancelled = _e('b', voucherNo: 13, voided: true).copyWith(voidReason: const Value('entered twice'));
      final igst = _e('c', amount: 1120, voucherNo: 14).copyWith(gstPct: const Value(12), gstInterState: true);
      for (final e in [cancelled, igst]) {
        expect((await buildVoucherPdf(expense: e, companyName: 'శ్రీ సాయి', siteName: 'Tower B')).length, greaterThan(500));
      }
    });
  });
}
