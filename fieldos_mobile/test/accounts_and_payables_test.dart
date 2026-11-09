import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/accounts_export.dart';
import 'package:fieldos_mobile/features/procurement/supplier_statement.dart';

/// Accountants work in Tally or Zoho Books, not in FieldOS; and suppliers
/// stop giving credit when bills go unpaid for months.
void main() {
  SiteExpense e(String id, double amount, String day,
          {String category = 'Transport', String? mode, double? gst, bool igst = false, bool voided = false, int? no, String? paidTo}) =>
      SiteExpense(
        id: '$id-0000-0000',
        projectId: 'p',
        category: category,
        amount: amount,
        incurredOn: day,
        recordedBy: 'u',
        createdAt: DateTime(2026, 1, 1),
        mode: mode,
        gstPct: gst,
        gstInterState: igst,
        voided: voided,
        voucherNo: no,
        paidTo: paidTo,
      );
  PaymentsReceivedData pay(String id, double amount, DateTime on) => PaymentsReceivedData(
        id: '$id-0000-0000',
        projectId: 'p',
        amount: amount,
        receivedOn: on,
        fromParty: 'Mr. Reddy',
        mode: 'upi',
        recordedBy: 'u',
        createdAt: on,
        voided: false,
      );

  group('Tally', () {
    final out = tallyXml(
      companyName: 'Sri Sai & Sons',
      expenses: [
        e('a', 1500, '2026-11-02', mode: 'cash', no: 4, paidTo: 'Tractor <Ravi>'),
        e('b', 11800, '2026-11-03', category: 'Material', mode: 'upi', gst: 18, no: 5),
        e('c', 1050, '2026-11-04', category: 'Material', mode: 'bank', gst: 5, igst: true, no: 6),
        e('d', 900, '2026-11-05', voided: true, no: 7),
        e('f', 700, '2026-10-30', no: 3),
      ],
      payments: [pay('m', 50000, DateTime(2026, 11, 6))],
      siteName: {'p': 'Green Valley Villa'},
      from: DateTime(2026, 11),
      to: DateTime(2026, 12),
    );

    test('one voucher per live entry in the period, cancelled ones left out', () {
      expect(out.vouchers, 4);
      expect(RegExp('<VOUCHER ').allMatches(out.text).length, 4);
      expect(out.text, contains('<SVCURRENTCOMPANY>Sri Sai &amp; Sons</SVCURRENTCOMPANY>'));
      expect(out.text, isNot(contains('V-7')));
      expect(out.text, isNot(contains('V-3')));
    });

    test('a cash expense debits the category and credits cash, escaped and dated', () {
      expect(out.text, contains('<VOUCHER VCHTYPE="Payment" ACTION="Create"><DATE>20261102</DATE>'));
      expect(out.text, contains('<VOUCHERNUMBER>GVV/V-4</VOUCHERNUMBER>'));
      expect(out.text, contains('Paid to Tractor &lt;Ravi&gt;'));
      expect(out.text,
          contains('<LEDGERNAME>Transport</LEDGERNAME><ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE><AMOUNT>-1500.00</AMOUNT>'));
      expect(out.text, contains('<LEDGERNAME>Cash</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>1500.00</AMOUNT>'));
    });

    test('GST is split into input tax ledgers and every voucher balances', () {
      expect(out.text, contains('<LEDGERNAME>Material</LEDGERNAME><ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE><AMOUNT>-10000.00</AMOUNT>'));
      expect(out.text, contains('<LEDGERNAME>Input CGST</LEDGERNAME><ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE><AMOUNT>-900.00</AMOUNT>'));
      expect(out.text, contains('<LEDGERNAME>Input IGST</LEDGERNAME><ISDEEMEDPOSITIVE>Yes</ISDEEMEDPOSITIVE><AMOUNT>-50.00</AMOUNT>'));
      for (final v in RegExp(r'<VOUCHER .*?</VOUCHER>').allMatches(out.text)) {
        final sum = RegExp(r'<AMOUNT>(-?[\d.]+)</AMOUNT>')
            .allMatches(v[0]!)
            .fold<double>(0, (s, m) => s + double.parse(m[1]!));
        expect(sum.abs(), lessThan(0.005), reason: v[0]);
      }
    });

    test('a client payment is a receipt into the bank, and the ledgers are listed', () {
      expect(out.text, contains('<VOUCHER VCHTYPE="Receipt" ACTION="Create"><DATE>20261106</DATE>'));
      expect(out.text, contains('<LEDGERNAME>Mr. Reddy</LEDGERNAME><ISDEEMEDPOSITIVE>No</ISDEEMEDPOSITIVE><AMOUNT>50000.00</AMOUNT>'));
      expect(out.ledgers,
          ['Bank Account', 'Cash', 'Input CGST', 'Input IGST', 'Input SGST', 'Material', 'Mr. Reddy', 'Transport']);
    });
  });

  test('Zoho CSV has one row per expense with the tax rate', () {
    final z = zohoExpensesCsv(
      expenses: [e('b', 11800, '2026-11-03', category: 'Material', mode: 'upi', gst: 18, no: 5, paidTo: 'Balaji, Hardware')],
      siteName: {'p': 'Green Valley'},
    );
    expect(z.text.split('\n')[1], '2026-11-03,Material,Bank Account,"Balaji, Hardware",11800.00,18,V-5,,Green Valley');
  });

  test('the financial year runs April to March', () {
    expect(financialYear(DateTime(2026, 11, 9)), (DateTime(2026, 4), DateTime(2027, 4)));
    expect(financialYear(DateTime(2027, 2, 1)), (DateTime(2026, 4), DateTime(2027, 4)));
  });

  test('ageing pays off the oldest bills first', () {
    StatementLine l(DateTime? on, double amt) =>
        StatementLine(on: on, kind: amt < 0 ? StatementKind.payment : StatementKind.delivery, label: '', amount: amt);
    final now = DateTime(2026, 11, 9);
    final a = ageStatement([
      l(null, 5000), // opening
      l(DateTime(2026, 7, 1), 20000), // 131 days
      l(DateTime(2026, 9, 25), 10000), // 45 days
      l(DateTime(2026, 11, 1), 8000), // 8 days
      l(DateTime(2026, 10, 1), -15000),
    ], now);
    expect(a.over90, 10000); // 5000 opening + 20000 paid down by 15000 → 0 opening, 10000 left
    expect(a.upTo60, 10000);
    expect(a.upTo30, 8000);
    expect(a.total, 28000);
    expect(a.oldestDays, 131);
    expect(a.openingUnpaid, isFalse);
  });
}
