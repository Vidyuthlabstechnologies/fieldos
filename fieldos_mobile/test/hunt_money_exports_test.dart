import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/accounts_check.dart';
import 'package:fieldos_mobile/features/export/accounts_export.dart';
import 'package:fieldos_mobile/features/export/xlsx_writer.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/money_book.dart' show gstSplit;

/// Bug hunt on the accountant exports and money words: CSV cells that a
/// spreadsheet would run as formulas, characters Tally's XML cannot hold,
/// Excel dates in the US order, and amounts in words for one unit and
/// below zero.
void main() {
  tearDown(() => debugSetMarket(Market.india));

  SiteExpense e(String id, double amount, String day,
          {String category = 'Transport', String? mode, double? gst, int? no, String? paidTo, String? note}) =>
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
        gstInterState: false,
        voided: false,
        voucherNo: no,
        paidTo: paidTo,
        note: note,
      );
  PaymentsReceivedData pay(String id, double amount, DateTime on, {String from = 'Client', String? note}) =>
      PaymentsReceivedData(
        id: '$id-0000-0000',
        projectId: 'p',
        amount: amount,
        receivedOn: on,
        fromParty: from,
        mode: 'bank',
        recordedBy: 'u',
        createdAt: on,
        voided: false,
        note: note,
      );

  /// The fields of a CSV line, quotes undone (no newlines inside).
  List<String> fields(String line) {
    final out = <String>[];
    final cur = StringBuffer();
    var q = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (q) {
        if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else if (c == '"') {
          q = false;
        } else {
          cur.write(c);
        }
      } else if (c == '"') {
        q = true;
      } else if (c == ',') {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    return out..add(cur.toString());
  }

  group('formula injection in accountant CSVs', () {
    test('Zoho: payee, note and category that start a formula stay text', () {
      final out = zohoExpensesCsv(expenses: [
        e('a', 500, '2026-11-03', category: '@SUM(A1)', paidTo: '=HYPERLINK("http://x.example","Pay")', note: '-2+3', no: 4),
        e('b', 200, '2026-11-04', paidTo: '+91 98480 12345', note: ' @note', no: 5),
      ], siteName: {
        'p': '=cmd|calc'
      });
      final lines = out.text.trim().split('\n');
      final a = fields(lines[1]), b = fields(lines[2]);
      expect(a[1], "'@SUM(A1)");
      expect(a[3], "'=HYPERLINK(\"http://x.example\",\"Pay\")");
      expect(a[4], '500.00', reason: 'amounts stay numbers');
      expect(a[7], "'-2+3");
      expect(a[8], "'=cmd|calc");
      expect(b[3], "'+91 98480 12345");
      expect(b[7], "'@note", reason: 'trimmed, then neutralised');
      expect(checkZohoCsv(out.text).problems, isEmpty);
    });

    test('QuickBooks and Xero: description, payee and reference stay text, amounts stay signed numbers', () {
      debugSetMarket(Market.us);
      final ex = [e('a', 150, '2026-11-02', category: '=1+1', mode: 'cash', no: 4)];
      final pays = [pay('m', 300, DateTime(2026, 11, 1), from: '@evil', note: 'x')];
      final qb = bankStatementCsvs(
          format: AccountsFormat.quickbooks, expenses: ex, payments: pays, siteName: {'p': 'Site'});
      final rows = qb['Cash']!.text.trim().split('\n');
      final spent = rows.firstWhere((r) => r.endsWith('-150.00'));
      expect(fields(spent)[1], startsWith("'=1+1"));
      expect(fields(spent)[2], '-150.00');
      expect(checkBankStatementCsv(qb['Cash']!.text, xero: false).problems, isEmpty);

      debugSetMarket(Market.uk);
      final xe = bankStatementCsvs(format: AccountsFormat.xero, expenses: ex, payments: pays, siteName: {'p': 'Site'});
      final paid = fields(xe['Bank Account']!.text.trim().split('\n')[1]);
      expect(paid[1], '300.00');
      expect(paid[2], "'@evil");
      final cash = fields(xe['Cash']!.text.trim().split('\n')[1]);
      expect(cash[1], '-150.00');
      expect(cash[3], startsWith("'=1+1"));
      for (final x in xe.values) {
        expect(checkBankStatementCsv(x.text, xero: true).problems, isEmpty);
      }
    });

    test('a lone carriage return in a note is quoted, so the row is not split', () {
      final out = zohoExpensesCsv(expenses: [e('a', 500, '2026-11-03', note: 'line one\rline two', no: 4)], siteName: {});
      expect(out.text, contains('"line one\rline two"'));
    });

    test('commas, quotes and newlines are quoted (no bug, coverage)', () {
      final out = zohoExpensesCsv(
          expenses: [e('a', 500, '2026-11-03', paidTo: 'Rao, "Big" Traders', note: 'a\nb', no: 4)], siteName: {});
      expect(out.text, contains('"Rao, ""Big"" Traders"'));
      expect(out.text, contains('"a\nb"'));
      expect(checkZohoCsv(out.text).problems, isEmpty);
    });
  });

  group('Tally XML', () {
    test('& < > and quotes in company, site, payee and note are escaped and the XML still checks', () {
      final t = tallyXml(
        companyName: 'R & S <Builders>',
        expenses: [e('a', 1180, '2026-11-03', gst: 18, paidTo: 'A&B "Steel" <Pvt>', note: "Ravi's 5 > 3", no: 2)],
        payments: [pay('m', 2000, DateTime(2026, 11, 4), from: 'Tom & Co <UK>')],
        siteName: {'p': 'Plot <7> & Annex'},
      );
      final check = checkTallyXml(t.text, ledgers: t.ledgers);
      expect(check.problems, isEmpty);
      final doc = XmlDocument.parse(t.text);
      expect(doc.findAllElements('SVCURRENTCOMPANY').single.innerText, 'R & S <Builders>');
      expect(doc.findAllElements('NARRATION').first.innerText, contains('A&B "Steel" <Pvt>'));
      expect(t.ledgers, contains('Tom & Co <UK>'));
      final masters = XmlDocument.parse(tallyLedgerMastersXml('R & S', t));
      expect(masters.findAllElements('LEDGER').map((l) => l.getAttribute('NAME')), contains('Tom & Co <UK>'));
    });

    test('a control character pasted into a note does not make the whole export unreadable', () {
      final t = tallyXml(
        companyName: 'Sri Sai',
        expenses: [e('a', 500, '2026-11-03', note: 'Rebar\u000bfirst floor\u0001', paidTo: 'Ram\u001fu', no: 2)],
        payments: const [],
        siteName: {'p': 'Site'},
      );
      final check = checkTallyXml(t.text, ledgers: t.ledgers);
      expect(check.problems, isEmpty);
      // XML 1.0 (and Tally) allow no control character but tab, newline, return.
      expect(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(t.text), isFalse);
      final narration = XmlDocument.parse(t.text).findAllElements('NARRATION').single.innerText;
      expect(narration, contains('Rebar'));
      expect(narration, contains('first floor'));
    });

    test('an empty period gives a valid file with no vouchers (no bug, coverage)', () {
      final t = tallyXml(companyName: 'Sri Sai', expenses: const [], payments: const [], siteName: const {});
      expect(t.vouchers, 0);
      expect(checkTallyXml(t.text, ledgers: t.ledgers).problems, isEmpty);
      final z = zohoExpensesCsv(expenses: const [], siteName: const {});
      expect(z.vouchers, 0);
      expect(z.text.trim().split('\n'), hasLength(1));
      expect(bankStatementCsvs(format: AccountsFormat.xero, expenses: const [], payments: const [], siteName: const {}),
          isEmpty);
    });

    test('GST parts add back to the bill in paise for awkward totals (no bug, coverage)', () {
      for (final total in [0.01, 0.05, 1.0, 99.99, 1049.99, 263.03, 123456.78]) {
        for (final rate in [5.0, 12.0, 18.0, 28.0]) {
          for (final inter in [false, true]) {
            final g = gstSplit(total, rate, interState: inter);
            expect(((g.taxable + g.tax) * 100).round(), (total * 100).round(), reason: '$total @ $rate');
          }
        }
      }
    });
  });

  group('Excel dates', () {
    Map<String, String> unzip(List<int> bytes) {
      final archive = ZipDecoder().decodeBytes(bytes);
      return {for (final f in archive.files) f.name: utf8.decode(f.content as List<int>)};
    }

    test('the US workbook shows dates month first, everywhere else day first', () {
      debugSetMarket(Market.us);
      var styles = unzip(buildXlsx([XlsxSheet('S', ['Date'], [[DateTime(2026, 11, 8)]])]))['xl/styles.xml']!;
      expect(styles, contains('formatCode="mm/dd/yyyy"'));
      expect(styles, isNot(contains('dd/mm/yyyy')));
      debugSetMarket(Market.uk);
      styles = unzip(buildXlsx([XlsxSheet('S', ['Date'], [[DateTime(2026, 11, 8)]])]))['xl/styles.xml']!;
      expect(styles, contains('formatCode="dd/mm/yyyy"'));
      expect(styles, contains('formatCode="dd/mm/yyyy hh:mm"'));
    });

    test('special characters in strings and sheet names stay well-formed XML (no bug, coverage)', () {
      final files = unzip(buildXlsx([
        XlsxSheet('R&D <1>', ['A & B'], [
          ['=SUM(A1) <b> & "q" \u0001'],
          [-1250.5],
        ]),
      ]));
      XmlDocument.parse(files['xl/workbook.xml']!);
      final sheet = XmlDocument.parse(files['xl/worksheets/sheet1.xml']!);
      final texts = sheet.findAllElements('t').map((t) => t.innerText).toList();
      expect(texts, ['A & B', '=SUM(A1) <b> & "q" ']);
      expect(sheet.findAllElements('f'), isEmpty, reason: 'an inline string is never a formula');
      expect(files['xl/worksheets/sheet1.xml'], contains('<v>-1250.5</v>'));
    });
  });

  group('amounts in words', () {
    test('one dollar, one cent, one pound and one penny are singular', () {
      debugSetMarket(Market.us);
      expect(amountInWords(1), 'One Dollar Only');
      expect(amountInWords(1.01), 'One Dollar and One Cent Only');
      expect(amountInWords(21.01), 'Twenty One Dollars and One Cent Only');
      expect(amountInWords(12500.5), 'Twelve Thousand Five Hundred Dollars and Fifty Cents Only');
      debugSetMarket(Market.uk);
      expect(amountInWords(1.01), 'One Pound and One Penny Only');
      expect(amountInWords(2.02), 'Two Pounds and Two Pence Only');
    });

    test('a negative amount keeps its sign in words', () {
      expect(amountInWords(-500), 'Minus Rupees Five Hundred Only');
      debugSetMarket(Market.us);
      expect(amountInWords(-12.5), 'Minus Twelve Dollars and Fifty Cents Only');
      expect(amountInWords(-0.001), 'Zero Dollars Only', reason: 'float dust below zero is zero');
    });

    test('zero, paise only and large values in each market (no bug, coverage)', () {
      expect(amountInWords(0), 'Rupees Zero Only');
      expect(amountInWords(0.5), 'Rupees Zero and Fifty Paise Only');
      expect(amountInWords(12345678901), 'Rupees One Thousand Two Hundred Thirty Four Crore Fifty Six Lakh Seventy Eight Thousand Nine Hundred One Only');
      expect(amountInWords(10000000), 'Rupees One Crore Only');
      expect(amountInWords(0.29), 'Rupees Zero and Twenty Nine Paise Only', reason: '0.29 * 100 is 28.999...');
      debugSetMarket(Market.uae);
      expect(amountInWords(1234567.25), 'UAE Dirhams One Million Two Hundred Thirty Four Thousand Five Hundred Sixty Seven and Twenty Five Fils Only');
      debugSetMarket(Market.malaysia);
      expect(amountInWords(0.05), 'Ringgit Malaysia Zero and Cents Five Only');
      debugSetMarket(Market.uk);
      expect(amountInWords(1000005), 'One Million and Five Pounds Only');
    });

    test('money() groups and signs per market (no bug, coverage)', () {
      expect(money(1234567), '₹12,34,567');
      expect(money(-1234.5, cents: true), '-₹1,234.50');
      expect(money(-0.001), '₹0');
      debugSetMarket(Market.uae);
      expect(money(1234567), 'AED 1,234,567');
      debugSetMarket(Market.us);
      expect(money(0.29, cents: true), r'$0.29');
      expect(fmtDateNumeric(DateTime(2026, 11, 6)), '11/06/2026');
    });
  });
}
