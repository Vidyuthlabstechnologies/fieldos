/// Client bills: the GST and deduction maths, amounts in words, bill
/// numbering, GSTIN checks, the bill PDF, the DAO with its sync outbox,
/// the mapper round trip and the v8 -> v9 upgrade.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

const _lines = [
  BillLine(description: 'Brick work 230mm', unit: 'cum', rate: 5200, qty: 12.5),
  BillLine(description: 'Plastering 12mm', unit: 'sqm', rate: 310, qty: 100),
];

ClientBillsCompanion _bill({String id = 'b1', String number = 'RA-01', String kind = 'ra', List<BillLine> lines = _lines}) {
  final t = billTotals(lines, retentionPct: 5, tdsPct: 1);
  return ClientBillsCompanion.insert(
    id: id,
    projectId: 'p',
    kind: kind,
    billNumber: number,
    billDate: DateTime(2026, 11, 6),
    clientName: 'Sai Builders',
    clientGstin: const Value('36ABCDE1234F1Z5'),
    linesJson: encodeLines(lines),
    retentionPct: const Value(5),
    tdsPct: const Value(1),
    gross: t.gross,
    netPayable: t.netPayable,
    recordedBy: 'u',
  );
}

void main() {
  group('billTotals', () {
    test('splits GST into CGST and SGST inside the state, and takes retention and TDS on the value before GST', () {
      final t = billTotals(_lines, gstRate: 18, retentionPct: 5, tdsPct: 1);
      expect(t.gross, 96000);
      expect((t.cgst, t.sgst, t.igst), (8640, 8640, 0));
      expect(t.invoiceTotal, 113280);
      expect(t.retention, 4800);
      expect(t.tds, 960);
      expect(t.netPayable, 107520);
    });

    test('is all IGST across states', () {
      final t = billTotals(_lines, gstRate: 18, interState: true);
      expect((t.cgst, t.sgst, t.igst), (0, 0, 17280));
      expect(t.netPayable, 113280);
    });

    test('keeps the halves adding up to the tax when it has odd paise', () {
      final t = billTotals(const [BillLine(description: 'x', unit: 'no', rate: 0.05, qty: 1)], gstRate: 18);
      expect(t.cgst + t.sgst, closeTo(0.01, 1e-9));
    });

    test('an empty bill is all zero', () {
      expect(billTotals(const []).netPayable, 0);
    });
  });

  test('lines round trip through JSON and bad JSON gives no lines', () {
    final back = decodeLines(encodeLines(_lines));
    expect(back.map((l) => (l.description, l.unit, l.rate, l.qty)),
        _lines.map((l) => (l.description, l.unit, l.rate, l.qty)));
    expect(decodeLines(''), isEmpty);
    expect(decodeLines('{"a":1}'), isEmpty);
  });

  test('previous quantities add up the same item across earlier bills, ignoring case', () {
    final prev = previousQuantities([
      _lines,
      const [BillLine(description: 'BRICK WORK 230MM', unit: 'CUM', rate: 5200, qty: 2.5)],
    ]);
    expect(prev[_lines.first.itemKey], 15);
    expect(prev[_lines.last.itemKey], 100);
  });

  test('next bill number continues each series', () {
    expect(nextBillNumber(const [], 'ra'), 'RA-01');
    expect(nextBillNumber(const ['RA-01', 'RA-09', 'INV-0003'], 'ra'), 'RA-10');
    expect(nextBillNumber(const ['RA-01', 'INV-0003', 'inv-0007'], 'tax_invoice'), 'INV-0008');
    expect(nextBillNumber(const ['RA-x'], 'ra'), 'RA-01');
  });

  group('amount in words', () {
    test('uses lakh and crore', () {
      expect(indianNumberWords(1234567), 'Twelve Lakh Thirty Four Thousand Five Hundred Sixty Seven');
      expect(indianNumberWords(250000000), 'Twenty Five Crore');
      expect(indianNumberWords(0), 'Zero');
    });

    test('adds paise', () {
      expect(rupeesInWords(107520), 'Rupees One Lakh Seven Thousand Five Hundred Twenty Only');
      expect(rupeesInWords(12500.5), 'Rupees Twelve Thousand Five Hundred and Fifty Paise Only');
    });
  });

  test('GSTIN shape and inter-state check', () {
    expect(isValidGstin('36ABCDE1234F1Z5'), isTrue);
    expect(isValidGstin(' 36abcde1234f1z5 '), isTrue);
    expect(isValidGstin('99ABCDE1234F1Z5'), isFalse);
    expect(isValidGstin('36ABCDE1234F1X5'), isFalse);
    expect(isInterState('36ABCDE1234F1Z5', '37ABCDE1234F1Z5'), isTrue);
    expect(isInterState('36ABCDE1234F1Z5', '36ZZZZZ1234F1Z5'), isFalse);
    expect(isInterState('36ABCDE1234F1Z5', null), isFalse);
  });

  test('project margin', () {
    const p = ProjectPnl(billed: 200000, received: 150000, spent: 170000, owed: 50000);
    expect(p.margin, 30000);
    expect(p.marginPct, 15);
    expect(const ProjectPnl(billed: 0, received: 0, spent: 10, owed: 0).marginPct, isNull);
  });

  test('pdfSafe swaps the rupee sign and replaces characters the PDF font lacks', () {
    expect(pdfSafe('₹ 1,000 – done'), 'Rs.  1,000 - done');
    expect(pdfSafe('రామ'), '???');
  });

  test('UPI link carries payee, amount and the bill number', () {
    final u = Uri.parse(upiPayLink('sai@okhdfc', 'Sai Builders', 107520, 'RA-01'));
    expect(u.scheme, 'upi');
    expect(u.queryParameters['pa'], 'sai@okhdfc');
    expect(u.queryParameters['am'], '107520.00');
    expect(u.queryParameters['tn'], 'Bill RA-01');
  });

  group('with a database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('creating a bill and marking it paid both go to the sync outbox', () async {
      final b = await db.billDao.create(_bill());
      await db.billDao.setStatus(b.id, 'paid');
      final out = await db.select(db.syncOutbox).get();
      expect(out.map((o) => (o.targetTable, o.operation)),
          [('site_client_bills', 'insert'), ('site_client_bills', 'update')]);
      expect(jsonDecode(out.last.payload)['status'], 'paid');
    });

    test('lists a project newest first', () async {
      await db.billDao.create(_bill());
      await db.billDao.create(_bill(id: 'b2', number: 'RA-02').copyWith(billDate: Value(DateTime(2026, 12, 1))));
      expect((await db.billDao.forProject('p')).map((b) => b.billNumber), ['RA-02', 'RA-01']);
      expect(await db.billDao.forProject('other'), isEmpty);
    });

    test('a bill round trips through the Supabase JSON', () async {
      final b = await db.billDao.create(_bill());
      final json = clientBillToSupabaseJson(b);
      expect(json['bill_date'], '2026-11-06');
      await db.delete(db.clientBills).go();
      await db.billDao.upsertFromRemote(clientBillFromSupabaseJson(json));
      final back = (await db.billDao.forProject('p')).single;
      expect((back.billNumber, back.gross, back.netPayable, back.retentionPct, back.linesJson),
          (b.billNumber, b.gross, b.netPayable, b.retentionPct, b.linesJson));
    });

    test('the PDF builds for an RA bill and a tax invoice', () async {
      final ra = await db.billDao.create(_bill());
      final inv = await db.billDao.create(_bill(id: 'b2', number: 'INV-0001', kind: 'tax_invoice'));
      final project = Project(
        id: 'p',
        companyId: 'c',
        name: 'Kondapur villa',
        status: 'active',
        createdAt: DateTime(2026, 11, 1),
      );
      for (final bill in [ra, inv]) {
        final bytes = await buildBillPdf(
          bill: bill,
          companyName: 'Sai Builders',
          project: project,
          profile: const BillingProfile(gstin: '36ABCDE1234F1Z5', upiId: 'sai@okhdfc'),
          previousQty: {_lines.first.itemKey: 10},
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    });
  });

  test('v8 -> v9 upgrade adds the bills table', () async {
    final dir = await Directory.systemTemp.createTemp('fieldos_v9');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');

    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.tasks).insert(TasksCompanion.insert(id: 't', projectId: 'p', title: 'Footing'));
    await db.customStatement('DROP TABLE client_bills');
    await db.customStatement('PRAGMA user_version = 8');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    expect((await db.taskDao.forProject('p')).single.title, 'Footing');
    await db.billDao.create(_bill());
    expect(await db.billDao.forProject('p'), hasLength(1));
    await db.close();
  });
}
