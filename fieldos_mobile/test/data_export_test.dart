import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/data_export.dart';
import 'package:fieldos_mobile/features/export/xlsx_writer.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';

/// Onsite's most-liked Play review: "either pay 35k a year or we delete
/// your data". FieldOS gives every customer an Excel file of everything,
/// from Settings, each site and the paywall, so their records are theirs.
void main() {
  Map<String, String> unzip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return {for (final f in archive.files) f.name: utf8.decode(f.content as List<int>)};
  }

  group('xlsx writer', () {
    test('column letters and Excel dates', () {
      expect([0, 1, 25, 26, 27, 51, 52, 701, 702].map(columnLetter).toList(),
          ['A', 'B', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
      expect(excelSerial(DateTime(2024, 1, 1)), 45292);
      expect(excelSerial(DateTime(2024, 1, 1, 12)), 45292.5);
    });

    test('sheet names follow Excel rules and stay different', () {
      expect(safeSheetNames(['Money: in/out', 'money: in/out', 'A' * 40, '', 'Sheet']),
          ['Money  in out', 'money  in out (2)', 'A' * 31, 'Sheet', 'Sheet (2)']);
    });

    test('a workbook holds every part Excel needs, with typed cells', () {
      final bytes = buildXlsx([
        XlsxSheet('Money spent', ['Date', 'Category', 'Amount (₹)', 'Paid'], [
          [DateTime(2026, 11, 8), 'Food & tea <site>', 1250.5, true],
          [DateTime(2026, 11, 7, 9, 30), 'Cement "OPC"', 4200, null],
        ]),
        XlsxSheet('Empty', ['Name'], const []),
      ]);
      final files = unzip(bytes);
      expect(files.keys, containsAll([
        '[Content_Types].xml',
        '_rels/.rels',
        'xl/workbook.xml',
        'xl/_rels/workbook.xml.rels',
        'xl/styles.xml',
        'xl/worksheets/sheet1.xml',
        'xl/worksheets/sheet2.xml',
      ]));
      expect(files['xl/workbook.xml'], contains('<sheet name="Money spent" sheetId="1" r:id="rId1"/>'));
      final s1 = files['xl/worksheets/sheet1.xml']!;
      // Header is bold, and frozen so it stays on top while scrolling.
      expect(s1, contains('<c r="A1" t="inlineStr" s="1"><is><t xml:space="preserve">Date</t></is></c>'));
      expect(s1, contains('state="frozen"'));
      expect(s1, contains('<autoFilter ref="A1:D3"/>'));
      // Dates are real dates, numbers are numbers, text is escaped.
      expect(s1, contains('<c r="A2" s="2"><v>${excelSerial(DateTime(2026, 11, 8))}</v></c>'));
      expect(s1, contains('<c r="A3" s="3">'));
      expect(s1, contains('<c r="C2" s="4"><v>1250.5</v></c>'));
      expect(s1, contains('<c r="C3"><v>4200</v></c>'));
      expect(s1, contains('Food &amp; tea &lt;site&gt;'));
      expect(s1, contains('Cement &quot;OPC&quot;'));
      expect(s1, contains('<c r="D2" t="b"><v>1</v></c>'));
      expect(s1, isNot(contains('r="D3"'))); // empty cells are left out
    });

    test('no sheets still gives a file Excel opens', () {
      expect(unzip(buildXlsx(const [])).keys, contains('xl/worksheets/sheet1.xml'));
    });
  });

  group('export of a site and a company', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase.memory();
      await db.into(db.users).insert(UsersCompanion.insert(id: 'u', username: 'ravi', name: 'Ravi', passwordHash: 'x'));
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p1', companyId: 'c', name: 'Sunrise Villa'));
      await db.into(db.projects).insert(ProjectsCompanion.insert(id: 'p2', companyId: 'c', name: 'Apex Tower'));
      await db.into(db.workers).insert(WorkersCompanion.insert(id: 'w1', projectId: 'p1', name: 'Suresh'));
      await db.into(db.siteExpenses).insert(SiteExpensesCompanion.insert(
          id: 'e1',
          projectId: 'p1',
          category: 'Labour',
          amount: 800,
          incurredOn: '2026-11-07',
          recordedBy: 'u',
          workerId: const Value('w1')));
      await db.into(db.siteExpenses).insert(SiteExpensesCompanion.insert(
          id: 'e2', projectId: 'p2', category: 'Fuel', amount: 300, incurredOn: '2026-11-08', recordedBy: 'u'));
      await db.into(db.paymentsReceived).insert(PaymentsReceivedCompanion.insert(
          id: 'r1',
          projectId: 'p1',
          amount: 50000,
          receivedOn: DateTime(2026, 11, 1),
          fromParty: 'Mr Rao',
          mode: 'upi',
          recordedBy: 'u'));
      await db.into(db.labourAttendance).insert(LabourAttendanceCompanion.insert(
          id: 'a1',
          projectId: 'p1',
          workerName: 'Suresh',
          workerId: const Value('w1'),
          recordedBy: 'u',
          punchIn: DateTime(2026, 11, 7, 8),
          punchOut: Value(DateTime(2026, 11, 7, 17, 30))));
      await db.into(db.tasks).insert(TasksCompanion.insert(
          id: 't1', projectId: 'p1', title: 'Plinth beam', status: const Value('in_progress')));
    });
    tearDown(() => db.close());

    XlsxSheet sheet(List<XlsxSheet> sheets, String name) => sheets.firstWhere((s) => s.name == name);

    test('one site: its own records, names instead of ids, words instead of codes', () async {
      final sheets = await buildExportSheets(db, const ExportScope.project('p1'));
      expect(sheets.map((s) => s.name), containsAllInOrder(['Summary', 'Money spent', 'Money received', 'Attendance']));

      final spent = sheet(sheets, 'Money spent');
      expect(spent.headers.first, 'Date'); // no Site column for a single site
      expect(spent.rows, [
        [DateTime(2026, 11, 7), 'Labour', 'Suresh', 800.0, null, 'Ravi'],
      ]);
      expect(sheet(sheets, 'Money received').rows.single, contains('UPI'));
      expect(sheet(sheets, 'Attendance').rows.single[3], 9.5);
      expect(sheet(sheets, 'Tasks').rows.single[1], 'In progress');

      final summary = sheet(sheets, 'Summary');
      final row = summary.rows.single;
      expect(row[0], 'Sunrise Villa');
      expect(row[summary.headers.indexOf('Received (₹)')], 50000.0);
      expect(row[summary.headers.indexOf('Spent (₹)')], 800.0);
      expect(row[summary.headers.indexOf('Balance (₹)')], 49200.0);
    });

    test('whole company: every real site with a Site column, the demo site left out', () async {
      final sample = await createSampleProject(db, companyId: 'c', userId: 'u', now: DateTime(2026, 11, 8));
      final sheets = await buildExportSheets(db, const ExportScope.company('c'));
      expect(sheet(sheets, 'Summary').rows.map((r) => r.first), ['Apex Tower', 'Sunrise Villa']);
      final spent = sheet(sheets, 'Money spent');
      expect(spent.headers.first, 'Site');
      expect(spent.rows.map((r) => r.first), ['Apex Tower', 'Sunrise Villa']); // newest first
      expect(spent.rows.any((r) => r.first == sample.name), isFalse);
    });

    test('roles that may not see money in get a file without it', () async {
      final sheets = await buildExportSheets(db, const ExportScope.project('p1'), showMoneyIn: false);
      final names = sheets.map((s) => s.name).toList();
      expect(names, isNot(contains('Money received')));
      expect(names, isNot(contains('Client bills')));
      final summary = sheet(sheets, 'Summary');
      expect(summary.headers, isNot(contains('Received (₹)')));
      expect(summary.headers, isNot(contains('Balance (₹)')));
      expect(summary.rows.single.length, summary.headers.length);
    });

    test('the file name is safe on any phone or PC', () {
      expect(exportFileName('Sri Sai Constructions & Co.', DateTime(2026, 11, 8)),
          'FieldOS Sri Sai Constructions Co 08-11-2026.xlsx');
      expect(exportFileName('శ్రీ సాయి', DateTime(2026, 1, 2)), 'FieldOS export 02-01-2026.xlsx');
    });
  });
}
