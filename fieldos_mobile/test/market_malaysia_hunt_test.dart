/// Malaysia bug hunt: retention that must never pass the limit of
/// retention fund, rest-day pay past half the normal hours, permit
/// reminders that must be replaceable, and India's GSTIN and greeting
/// kept off Malaysian quotations and reports.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/crm/quote_pdf.dart';
import 'package:fieldos_mobile/features/export/data_export.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/money/bill_pdf.dart' show BillingProfile;
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/procurement/quote_compare.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/report_output.dart';

/// The text a PDF draws: every stream inflated, read as Latin-1.
String _pdfText(List<int> bytes) {
  final raw = latin1.decode(bytes);
  final out = StringBuffer(raw);
  final stream = RegExp(r'stream\r?\n');
  for (final m in stream.allMatches(raw)) {
    final end = raw.indexOf('endstream', m.end);
    if (end < 0) continue;
    try {
      out.write(latin1.decode(zlib.decode(bytes.sublist(m.end, end)), allowInvalid: true));
    } catch (_) {}
  }
  return out.toString();
}

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('retention cut to the limit stays within it once shown and read back', () {
    debugSetMarket(Market.malaysia);
    // Contract RM1,000,000: limit RM50,000; RM10,000 left. A claim of
    // RM299,970 at 10% wants RM29,997, so the % is cut to 3.3336...
    const gross = 299970.0, room = 10000.0;
    final pct = retentionPctWithinLimit(
        pct: 10, gross: gross, alreadyKept: 40000, contractSum: 1000000, limitPctOfContract: 5);
    // The bill screen writes the cut % into its field and saves what it
    // reads back from there.
    final saved = double.parse(fmtQty(pct));
    final kept = billTotals([const BillLine(description: 'Work', unit: 'LS', rate: gross, qty: 1)], retentionPct: saved)
        .retention;
    expect(kept, lessThanOrEqualTo(room));
  });

  test('a rest day worked past half the normal hours pays two days', () {
    debugSetMarket(Market.malaysia);
    final sun = DateTime(2026, 11, 22);
    final cal = PayCalendar(restDays: {DateTime.sunday});
    LabourAttendanceData punch(double hours) => LabourAttendanceData(
          id: 'p$hours',
          projectId: 'p',
          workerName: 'Agus',
          workerId: 'w1',
          recordedBy: 'u',
          punchIn: sun.add(const Duration(hours: 8)),
          punchOut: sun.add(Duration(minutes: 8 * 60 + (hours * 60).round())),
          createdAt: sun,
        );
    double days(double hours) => buildWageSheet(
          workers: [Worker(id: 'w1', projectId: 'p', name: 'Agus', dailyWage: 100, status: 'active', createdAt: DateTime(2026))],
          punches: [punch(hours)],
          expenses: const [],
          from: DateTime(2026, 11, 16),
          to: DateTime(2026, 11, 23),
          calendar: cal,
        ).lines.single.days;
    // Employment Act 1955 s60(3)(b): normal hours 8, so up to 4 hours is
    // one day's wages and more than 4 is two.
    expect(days(3.5), 1);
    expect(days(4), 1);
    expect(days(6), 2);
    expect(days(8), 2);
  });

  test('every permit reminder id is one the next plan cancels', () {
    debugSetMarket(Market.malaysia);
    final now = DateTime(2026, 11, 14, 6);
    final plan = planReminders(
      now: now,
      settings: const ReminderSettings(),
      runningSites: 1,
      reportedToday: false,
      openTasks: const [],
      isOwner: true,
      permits: [
        for (var i = 0; i < 7; i++)
          (worker: 'Agus', permit: 'PLKS work permit', expiresOn: DateTime(2026, 11, 14 + i).add(const Duration(days: 30))),
      ],
    );
    final permitIds = [for (final r in plan) if (r.payload == 'permits') r.id];
    expect(permitIds, hasLength(7));
    for (final id in [for (final r in plan) r.id]) {
      expect(id, inInclusiveRange(reminderIdBase, reminderIdBase + reminderIdCount - 1));
    }
  });

  test('report PDFs print the SST registration label, not GSTIN', () async {
    debugSetMarket(Market.malaysia);
    final pdf = _pdfText(await buildReportPdf(
      report: reportById('expenses')!,
      table: ReportTable(['Item'], [
        ['Cement'],
      ]),
      companyName: 'Bina Jaya Sdn Bhd',
      sitesText: 'All sites',
      profile: const BillingProfile(gstin: 'W10-1808-32000123'),
    ));
    expect(pdf, isNot(contains('GSTIN')));
    expect(pdf, contains('registration'));
  });

  test('the WhatsApp ask for supplier rates says SST, not GST, and no Namaste', () {
    final r = PurchaseRequest(
        id: 'r',
        projectId: 'p',
        raisedBy: 'u',
        materialName: 'Simen',
        quantity: 100,
        unit: 'bag',
        urgency: 'normal',
        status: 'approved',
        createdAt: DateTime(2026, 11, 14));
    String ask() => rfqMessage(request: r, siteName: 'Taman Bukit', companyName: 'Bina Jaya');
    expect(ask(), allOf(startsWith('Namaste'), contains(', GST,')));
    debugSetMarket(Market.malaysia);
    expect(ask(), isNot(contains('GST')));
    expect(ask(), isNot(contains('Namaste')));
    expect(ask(), contains(', SST,'));
  });

  group('Excel export', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.memory();
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u', username: 'lim', name: 'Lim', passwordHash: 'x'));
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p1', companyId: 'c', name: 'Taman Bukit'));
      await db.into(db.siteExpenses).insert(SiteExpensesCompanion.insert(
          id: 'e1',
          projectId: 'p1',
          category: 'Material',
          amount: 1060,
          incurredOn: '2026-11-07',
          recordedBy: 'u',
          gstPct: const Value(6)));
      await db.into(db.clientBills).insert(ClientBillsCompanion.insert(
          id: 'b1',
          projectId: 'p1',
          kind: 'ra',
          billNumber: 'RA-01',
          billDate: DateTime(2026, 11, 8),
          clientName: 'Pemaju Sdn Bhd',
          linesJson: '[]',
          gross: 10000,
          netPayable: 9600,
          recordedBy: 'u'));
    });
    tearDown(() => db.close());

    test('Malaysia: SST in its own column, no GSTIN, CGST, SGST, IGST or RA bill', () async {
      debugSetMarket(Market.malaysia);
      final sheets = await buildExportSheets(db, const ExportScope.project('p1'));
      final all = [
        for (final s in sheets) ...[...s.headers, for (final r in s.rows) ...r.map((c) => '$c')],
      ].join(' | ');
      for (final india in ['GSTIN', 'CGST', 'SGST', 'IGST', 'RA bill']) {
        expect(all, isNot(contains(india)), reason: india);
      }
      final spent = sheets.firstWhere((s) => s.name == 'Money spent');
      final col = spent.headers.indexOf('SST (RM)');
      expect(col, isNonNegative);
      expect(spent.rows.single[col], 60);
      expect(spent.rows.single.length, spent.headers.length);
      final bills = sheets.firstWhere((s) => s.name == 'Client bills');
      expect(bills.rows.single[bills.headers.indexOf('Type')], 'Progress claim');
    });

    test('India keeps CGST, SGST and IGST and the RA bill', () async {
      final sheets = await buildExportSheets(db, const ExportScope.project('p1'));
      final spent = sheets.firstWhere((s) => s.name == 'Money spent');
      expect(spent.headers, containsAll(['CGST (₹)', 'SGST (₹)', 'IGST (₹)']));
      expect(spent.rows.single.length, spent.headers.length);
      final bills = sheets.firstWhere((s) => s.name == 'Client bills');
      expect(bills.headers, contains('Client GSTIN'));
      expect(bills.rows.single[bills.headers.indexOf('Type')], 'RA bill');
    });
  });

  group('quotation', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.memory());
    tearDown(() => db.close());

    test('prints the SST registration label and no Indian greeting', () async {
      debugSetMarket(Market.malaysia);
      final company = await db.companyDao.create('Bina Jaya Sdn Bhd');
      final lead = await db.crmDao.addLead(companyId: company.id, name: 'Encik Ahmad', by: 'o', workType: 'Double storey');
      final q = await db.crmDao.saveQuote(
          leadId: lead.id,
          lines: const [BillLine(description: 'Brickwork', unit: 'm2', rate: 45, qty: 100)],
          by: 'o',
          gstRate: 6,
          interState: true);
      final pdf = _pdfText(await buildQuotePdf(
          quote: q, lead: lead, companyName: company.name, profile: const BillingProfile(gstin: 'W10-1808-32000123')));
      expect(pdf, isNot(contains('GSTIN')));
      expect(pdf, contains('registration')); // words are drawn one by one
      expect(quoteShareText(q, lead, company.name), isNot(contains('Namaste')));
    });

    test('India keeps GSTIN and Namaste', () async {
      final company = await db.companyDao.create('Sai Constructions');
      final lead = await db.crmDao.addLead(companyId: company.id, name: 'Ramesh', by: 'o');
      final q = await db.crmDao.saveQuote(
          leadId: lead.id, lines: const [BillLine(description: 'Brickwork', unit: 'cum', rate: 6500, qty: 10)], by: 'o');
      final pdf = _pdfText(await buildQuotePdf(
          quote: q, lead: lead, companyName: company.name, profile: const BillingProfile(gstin: '36ABCDE1234F1Z1')));
      expect(pdf, contains('GSTIN'));
      expect(quoteShareText(q, lead, company.name), startsWith('Namaste Ramesh'));
    });
  });
}
