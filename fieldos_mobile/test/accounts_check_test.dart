/// The Tally and Zoho exports pass the checks the importers make, for many
/// amounts and GST rates; and the checks catch each way a file can break.
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/accounts_check.dart';
import 'package:fieldos_mobile/features/export/accounts_export.dart';

void main() {
  var seq = 0;
  SiteExpense e(double amount, String day,
          {String project = 'p', String category = 'Material', String? mode, double? gst, bool igst = false, int? no, String? paidTo, String? note}) =>
      SiteExpense(
        id: '${(seq++).toString().padLeft(8, '0')}-0000-0000',
        projectId: project,
        category: category,
        amount: amount,
        incurredOn: day,
        recordedBy: 'u',
        createdAt: DateTime(2026, 1, 1),
        mode: mode,
        gstPct: gst,
        gstInterState: igst,
        voided: false,
        voucherNo: no,
        paidTo: paidTo,
        note: note,
      );
  PaymentsReceivedData pay(double amount, DateTime on, {String project = 'p', String party = 'Mr. Reddy'}) => PaymentsReceivedData(
        id: '${(seq++).toString().padLeft(8, '0')}-0000-0000',
        projectId: project,
        amount: amount,
        receivedOn: on,
        fromParty: party,
        mode: 'bank',
        recordedBy: 'u',
        createdAt: on,
        voided: false,
      );

  test('a year of random expenses and receipts passes every Tally and Zoho check', () {
    final rnd = Random(7);
    const rates = [null, 0.0, 5.0, 12.0, 18.0, 28.0];
    final expenses = [
      for (var i = 0; i < 400; i++)
        e((rnd.nextInt(5000000) + 1) / 100, '2026-${(rnd.nextInt(12) + 1).toString().padLeft(2, '0')}-${(rnd.nextInt(28) + 1).toString().padLeft(2, '0')}',
            project: rnd.nextBool() ? 'p' : 'q',
            category: ['Material', 'Transport', 'Labour & Wages', 'Food "site"'][rnd.nextInt(4)],
            mode: ['cash', 'upi', 'bank'][rnd.nextInt(3)],
            gst: rates[rnd.nextInt(rates.length)],
            igst: rnd.nextBool(),
            no: i + 1,
            paidTo: rnd.nextBool() ? 'Balaji, <Hardware> & Sons' : null,
            note: rnd.nextBool() ? 'line one\nline two, "quoted"' : null),
    ];
    final payments = [for (var i = 0; i < 40; i++) pay((rnd.nextInt(90000000) + 100) / 100, DateTime(2026, rnd.nextInt(12) + 1, 3))];
    // Two sites with the same initials: their voucher numbers must not clash.
    final names = {'p': 'Kompally Villas', 'q': 'Kukatpally Villas'};
    final t = tallyXml(companyName: 'Sri Sai & Sons', expenses: expenses, payments: payments, siteName: names);
    final check = checkTallyXml(t.text, ledgers: t.ledgers);
    expect(check.problems, isEmpty);
    expect(check.entries, 440);

    final z = zohoExpensesCsv(expenses: expenses, siteName: names);
    final zc = checkZohoCsv(z.text);
    expect(zc.problems, isEmpty);
    expect(zc.entries, 400);
  });

  test('the Tally ledgers file creates each ledger once, under the right group', () {
    final t = tallyXml(
        companyName: 'Sri Sai',
        expenses: [e(11800, '2026-11-03', mode: 'upi', gst: 18), e(500, '2026-11-04', category: 'Transport', mode: 'cash')],
        payments: [pay(50000, DateTime(2026, 11, 6))],
        siteName: {'p': 'Green Valley'});
    final doc = XmlDocument.parse(tallyLedgerMastersXml('Sri Sai', t));
    expect(doc.findAllElements('REPORTNAME').single.innerText, 'All Masters');
    final groups = {
      for (final l in doc.findAllElements('LEDGER')) l.getAttribute('NAME'): l.getElement('PARENT')!.innerText,
    };
    expect(groups, {
      'Bank Account': 'Bank Accounts',
      'Input CGST': 'Duties & Taxes',
      'Input SGST': 'Duties & Taxes',
      'Material': 'Direct Expenses',
      'Mr. Reddy': 'Sundry Debtors',
      'Transport': 'Direct Expenses',
    }, reason: 'Cash already exists in every Tally company');
  });

  group('the Tally check catches', () {
    late String good;
    late List<String> ledgers;
    setUp(() {
      final t = tallyXml(
          companyName: 'Sri Sai',
          expenses: [e(11800, '2026-11-03', mode: 'upi', gst: 18, no: 5)],
          payments: [pay(50000, DateTime(2026, 11, 6))],
          siteName: {'p': 'Green Valley'});
      good = t.text;
      ledgers = t.ledgers;
      expect(checkTallyXml(good, ledgers: ledgers).ok, isTrue);
    });
    void catches(String bad, String problem, {List<String>? with_}) =>
        expect(checkTallyXml(bad, ledgers: with_ ?? ledgers).problems, contains(contains(problem)));

    test('broken XML', () => catches(good.replaceFirst('</ENVELOPE>', ''), 'not valid XML'));
    test('an unbalanced voucher', () => catches(good.replaceFirst('<AMOUNT>-10000.00</AMOUNT>', '<AMOUNT>-10000.50</AMOUNT>'), 'differ by 0.50'));
    test('a sign Tally reads the other way',
        () => catches(good.replaceFirst('<ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE>', '<ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE>'), 'ISDEEMEDPOSITIVE'));
    test('a date that does not exist', () => catches(good.replaceFirst('<DATE>20261103</DATE>', '<DATE>20261131</DATE>'), 'not a real date'));
    test('a ledger not on the list', () => catches(good, 'not on the list', with_: ledgers.where((l) => l != 'Material').toList()));
    test('a number used twice', () => catches(good.replaceFirst(RegExp(r'GV/R-\w+'), 'GV/V-5').replaceAll('VCHTYPE="Receipt"', 'VCHTYPE="Payment"').replaceAll('>Receipt<', '>Payment<'), 'used twice'));
    test('a receipt that is not money in', () => catches(good.replaceFirst('<LEDGERNAME>Bank Account</LEDGERNAME><ISDEEMEDPOSITIVE>Yes', '<LEDGERNAME>Material</LEDGERNAME><ISDEEMEDPOSITIVE>Yes'), 'does not come into'));
    test('no company', () => catches(good.replaceFirst('<SVCURRENTCOMPANY>Sri Sai</SVCURRENTCOMPANY>', '<SVCURRENTCOMPANY></SVCURRENTCOMPANY>'), 'No company'));
  });

  group('the Zoho check catches', () {
    const header = 'Expense Date,Expense Account,Paid Through,Vendor,Amount,Tax Percentage,Reference#,Description,Project';
    void catches(String row, String problem) => expect(checkZohoCsv('$header\n$row\n').problems, contains(contains(problem)));

    test('a row is fine', () => expect(checkZohoCsv('$header\n2026-11-03,Material,Cash,"Balaji, ""Hardware""",100.00,18,V-1,"two\nlines",Site\n').problems, isEmpty));
    test('a missing column', () => expect(checkZohoCsv('Expense Date,Amount\n2026-11-03,100\n').problems, contains(contains('Paid Through'))));
    test('a shifted row', () => catches('2026-11-03,Material,Cash,Balaji, Hardware,100.00,18,V-1,,Site', '10 fields'));
    test('a bad date', () => catches('03/11/2026,Material,Cash,,100.00,18,V-1,,Site', 'not a real date'));
    test('a zero amount', () => catches('2026-11-03,Material,Cash,,0,18,V-1,,Site', 'not above zero'));
    test('a bad tax rate', () => catches('2026-11-03,Material,Cash,,100,eighteen,V-1,,Site', 'not a percentage'));
    test('an open quote', () => catches('2026-11-03,Material,Cash,"Balaji,100,18,V-1,,Site', 'not closed'));
  });
}
