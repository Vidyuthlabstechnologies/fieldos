/// US PDFs print on US Letter (612 x 792 pt); every other market on A4.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/core/page_format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/crm/quote_pdf.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/payroll/payslip_pdf.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/report_output.dart';

/// Every page's size in points, from its /MediaBox, as "w x h".
List<String> pageSizes(List<int> bytes) {
  final raw = latin1.decode(bytes);
  final box = RegExp(r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]');
  String pt(String v) => double.parse(v).round().toString();
  return [
    for (final m in box.allMatches(raw)) '${pt(m[3]!)} x ${pt(m[4]!)}',
  ];
}

const letter = '612 x 792';
const a4 = '595 x 842';

Future<List<int>> report({int columns = 1}) => buildReportPdf(
      report: reportById('expenses')!,
      table: ReportTable([for (var i = 0; i < columns; i++) 'Col $i'], [
        [for (var i = 0; i < columns; i++) 'Cement'],
      ]),
      companyName: 'Acme Builders',
      sitesText: 'All sites',
    );

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('Letter for the US, A4 for every other market', () {
    expect(marketPageFormat(Market.us), PdfPageFormat.letter);
    for (final m in Market.values.where((m) => m != Market.us)) {
      expect(marketPageFormat(m), PdfPageFormat.a4, reason: m.name);
    }
    debugSetMarket(Market.us);
    expect(marketPageFormat(), PdfPageFormat.letter, reason: 'follows the build\'s market');
    debugSetMarket(Market.india);
    expect(marketPageFormat(), PdfPageFormat.a4);
  });

  test('a US report PDF is 612 x 792 pt; an Indian one is A4', () async {
    debugSetMarket(Market.us);
    expect(pageSizes(await report()), everyElement(letter));
    expect(pageSizes(await report()), isNotEmpty);
    debugSetMarket(Market.india);
    expect(pageSizes(await report()), everyElement(a4));
    expect(pageSizes(await report()), isNotEmpty);
  });

  test('wide reports turn the market\'s paper sideways', () async {
    debugSetMarket(Market.us);
    expect(pageSizes(await report(columns: 8)), everyElement('792 x 612'));
    debugSetMarket(Market.uk);
    expect(pageSizes(await report(columns: 8)), everyElement('842 x 595'));
  });

  group('documents for clients and staff', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    test('quotation', () async {
      Future<List<String>> quote() async {
        final company = await db.companyDao.create('Acme Builders');
        final lead = await db.crmDao.addLead(companyId: company.id, name: 'Jordan', by: 'o');
        final q = await db.crmDao.saveQuote(
            leadId: lead.id, lines: const [BillLine(description: 'Framing', unit: 'sq ft', rate: 9, qty: 400)], by: 'o');
        return pageSizes(await buildQuotePdf(quote: q, lead: lead, companyName: company.name));
      }

      debugSetMarket(Market.us);
      expect(await quote(), allOf(isNotEmpty, everyElement(letter)));
      debugSetMarket(Market.india);
      expect(await quote(), allOf(isNotEmpty, everyElement(a4)));
    });

    test('payslip', () async {
      final company = await db.companyDao.create('Acme Builders');
      final staff = await db.payrollDao.addStaff(companyId: company.id, name: 'Sam', basic: 4000);
      await db.payrollDao.makeMonth(company.id, '2026-11', by: 'o');
      final line = (await db.payrollDao.linesForMonth(company.id, '2026-11')).single;
      Future<List<String>> slip() async =>
          pageSizes(await buildPayslipPdf(line: line, staff: staff, companyName: company.name));

      debugSetMarket(Market.us);
      expect(await slip(), allOf(isNotEmpty, everyElement(letter)));
      debugSetMarket(Market.india);
      expect(await slip(), allOf(isNotEmpty, everyElement(a4)));
    });
  });
}
