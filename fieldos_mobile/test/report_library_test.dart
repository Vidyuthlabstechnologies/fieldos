/// The report library: every report builds on real and on empty data, the
/// figures add up, periods and sites narrow what is counted, and money
/// received, salaries and sales stay with the people allowed to see them.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/reports/report_library.dart';
import 'package:fieldos_mobile/features/reports/report_output.dart';
import 'package:fieldos_mobile/features/reports/reports_library_screen.dart' show reportRange, ReportPeriodChoice;

const _uuid = Uuid();

void main() {
  late AppDatabase db;
  late String companyId;
  late Project a, b;
  final now = DateTime(2026, 11, 20, 10);

  setUp(() async {
    db = AppDatabase.memory();
    companyId = (await db.companyDao.create('Sai Constructions')).id;
    a = await db.projectDao.create(ProjectsCompanion.insert(id: 'a', companyId: companyId, name: 'Narapally', status: const Value('active')));
    b = await db.projectDao.create(ProjectsCompanion.insert(id: 'b', companyId: companyId, name: 'Kompally', status: const Value('active')));

    Future<void> spend(String site, String day, double amount, String head, {String? to, String mode = 'cash', double? gst}) =>
        db.expenseDao.create(SiteExpensesCompanion.insert(
            id: _uuid.v4(), projectId: site, category: head, amount: amount, incurredOn: day, recordedBy: 'u',
            paidTo: Value(to), mode: Value(mode), gstPct: Value(gst)));
    await spend('a', '2026-11-03', 12000, 'Material', to: 'Balaji Cements', mode: 'bank', gst: 18);
    await spend('a', '2026-11-05', 3000, 'Transport', to: 'Ravi Transport');
    await spend('b', '2026-11-06', 5000, 'Material', to: 'Balaji Cements', mode: 'upi');
    await spend('a', '2026-10-28', 9999, 'Material'); // last month

    await db.paymentDao.create(PaymentsReceivedCompanion.insert(
        id: _uuid.v4(), projectId: 'a', amount: 50000, receivedOn: DateTime(2026, 11, 10), fromParty: 'Mr Reddy', mode: 'bank', recordedBy: 'u'));

    final supplier = await db.supplierDao.create(SuppliersCompanion.insert(id: 's1', companyId: companyId, name: 'Balaji Cements'));
    for (final (site, qty, amount) in [('a', 100.0, 39000.0), ('a', 50.0, 20000.0), ('b', 20.0, 8000.0)]) {
      await db.materialDao.createReceipt(MaterialReceiptsCompanion.insert(
          id: _uuid.v4(), projectId: site, supplierId: Value(supplier.id), materialName: 'Cement', quantity: qty,
          unit: const Value('bags'), amount: amount, receivedBy: 'u', receivedOn: DateTime(2026, 11, 4)));
    }
    await db.materialDao.recordUsage(MaterialUsageCompanion.insert(
        id: _uuid.v4(), projectId: 'a', materialName: 'Cement', quantity: 30, unit: const Value('bags'), recordedBy: 'u', usedOn: DateTime(2026, 11, 8)));

    await db.taskDao.create(TasksCompanion.insert(
        id: 't1', projectId: 'a', title: 'Slab casting', dueDate: Value(DateTime(2026, 11, 15)), status: const Value('in_progress')));
    await db.taskDao.create(TasksCompanion.insert(id: 't2', projectId: 'b', title: 'Plastering', dueDate: Value(DateTime(2026, 12, 1))));

    final w = await db.workerDao.create(WorkersCompanion.insert(id: 'w1', projectId: 'a', name: 'Raju', dailyWage: const Value(800)));
    for (final day in ['2026-11-02', '2026-11-03', '2026-11-04']) {
      await db.attendanceDao.setMark(projectId: 'a', workerId: w.id, day: day, units: 1, by: 'u');
    }
    await db.attendanceDao.setMark(projectId: 'a', workerId: w.id, day: '2026-11-05', units: 0.5, by: 'u');

    final staff = await db.payrollDao.addStaff(companyId: companyId, name: 'Anil', basic: 18000, hra: 7000, otherAllowance: 3000, projectId: 'a');
    await db.payrollDao.giveAdvance(staffId: staff.id, amount: 5000, by: 'u');
    await db.payrollDao.makeMonth(companyId, '2026-11', by: 'u');

    final tool = await db.warehouseDao.addTool(companyId: companyId, name: 'Drill machine', value: 6500, by: 'u');
    await db.warehouseDao.issueTool(toolId: tool.id, issuedTo: 'Ravi', projectId: 'a', dueBack: DateTime(2026, 11, 12), by: 'u');

    await db.crmDao.addLead(companyId: companyId, name: 'Mr Rao', by: 'u', source: 'referral', estimatedValue: 4500000,
        nextFollowUp: DateTime(2026, 11, 19));
  });
  tearDown(() => db.close());

  Future<ReportInput> input({List<Project>? sites, ReportPeriodChoice period = ReportPeriodChoice.thisMonth, bool manager = true, bool moneyIn = true}) {
    final (from, to) = reportRange(period, now);
    return loadReportInput(db, companyId: companyId, sites: sites ?? [a, b], from: from, to: to, manager: manager, moneyIn: moneyIn, now: now);
  }

  ReportTable run(String id, ReportInput d) => reportById(id)!.build(d);

  test('there are fifty-plus reports, each with a unique id, and every one builds on full and empty data', () async {
    expect(reportLibrary.length, greaterThanOrEqualTo(50));
    expect(reportLibrary.map((r) => r.id).toSet(), hasLength(reportLibrary.length));
    final full = await input(period: ReportPeriodChoice.allTime);
    final empty = ReportInput(sites: const [], from: DateTime(2026), to: DateTime(2027), now: now);
    for (final r in reportLibrary) {
      final t = r.build(full);
      for (final row in t.rows) {
        expect(row, hasLength(t.headers.length), reason: r.id);
      }
      expect(r.build(empty).rows, isEmpty, reason: '${r.id} on no data');
    }
  });

  test('spending reports add up and leave out last month and cancelled vouchers', () async {
    final d = await input();
    expect(run('expenses', d).totals![6], 20000);
    final heads = run('expense-heads', d);
    expect(heads.rows.first, ['Material', 17000.0, 85.0]);
    expect(run('expense-sites', d).rows, [['Narapally', 15000.0], ['Kompally', 5000.0]]);
    expect(run('paid-to', d).rows.first, ['Balaji Cements', 17000.0]);
    final gst = run('gst-input', d);
    expect(gst.rows.single[5], closeTo(1830.51, 0.01), reason: 'GST inside 12,000 at 18%');
    expect(run('mode', d).rows.map((r) => r[0]), containsAll(['Bank', 'Cash', 'Upi']));
  });

  test('choosing one site narrows every figure to it', () async {
    final d = await input(sites: [b]);
    expect(run('expenses', d).totals![6], 5000);
    expect(run('grn', d).totals![6], 8000);
    expect(run('tasks', d).rows.single[1], 'Plastering');
  });

  test('material: received by material, average rate, and site stock after use', () async {
    final d = await input();
    final m = run('grn-by-material', d).rows.single;
    expect(m.sublist(0, 4), ['Cement', 'bags', 170.0, 67000.0]);
    expect(m[4], closeTo(394.12, 0.01));
    final stock = run('site-stock', d).rows.firstWhere((r) => r[0] == 'Narapally');
    expect(stock[7], 120.0, reason: '150 in, 30 used');
    expect(run('by-supplier', d).rows.single, ['Balaji Cements', 3, 67000.0, 0.0]);
  });

  test('labour: days worked and wages from the wage sheet, half days counted', () async {
    final d = await input();
    expect(run('worker-days', d).rows.single, ['Raju', 'Narapally', '', 3.5]);
    expect(run('wages-due', d).rows.single.last, 2800);
  });

  test('late tasks, overdue tools and follow-ups are as of today', () async {
    final d = await input();
    final late = run('late-tasks', d).rows.single;
    expect(late[1], 'Slab casting');
    expect(late[3], 5);
    expect(run('tools-overdue', d).rows.single.sublist(1, 3), ['Drill machine', 'Ravi']);
    expect(run('tools-overdue', d).rows.single.last, 8);
    expect(run('follow-ups', d).rows.single[1], 'Mr Rao');
    expect(run('pipeline', d).totals, ['Total', 1.0, 4500000.0]);
  });

  test('salaries: the register, PF and ESI to deposit, and advances owed', () async {
    final d = await input();
    final reg = run('salary-register', d).rows.single;
    expect(reg[1], 'Anil');
    expect(reg[3], 28000);
    final pf = run('pf-esi', d).rows.single;
    expect(pf[1], 1800);
    expect(pf[2], 1800);
    expect(run('advances', d).rows, isEmpty, reason: 'this month\'s payslip recovers the whole advance');
    expect(run('staff-cost-sites', d).rows.single[0], 'Narapally');
  });

  test('a site engineer gets no money received, salaries or sales, even if asked', () async {
    final d = await input(manager: false, moneyIn: false);
    expect(run('received', d).rows, isEmpty);
    expect(run('salary-register', d).rows, isEmpty);
    expect(run('pipeline', d).rows, isEmpty);
    final open = reportLibrary.where((r) => canOpenReport(r, moneyIn: false, manager: false)).map((r) => r.id);
    expect(open, isNot(contains('received')));
    expect(open, isNot(contains('salary-register')));
    expect(open, isNot(contains('pipeline')));
    expect(open, contains('expenses'));
  });

  test('periods: weeks start Monday, financial years on 1 April', () {
    expect(reportRange(ReportPeriodChoice.thisWeek, now), (DateTime(2026, 11, 16), DateTime(2026, 11, 21)));
    expect(reportRange(ReportPeriodChoice.lastMonth, now), (DateTime(2026, 10), DateTime(2026, 11)));
    expect(reportRange(ReportPeriodChoice.thisYear, now).$1, DateTime(2026, 4));
    expect(reportRange(ReportPeriodChoice.thisYear, DateTime(2027, 2, 1)).$1, DateTime(2026, 4));
    expect(reportRange(ReportPeriodChoice.lastYear, now), (DateTime(2025, 4), DateTime(2026, 4)));
  });

  test('PDF with the company\'s logo line, colour and footer, and Excel with a total row', () async {
    final d = await input();
    final r = reportById('expenses')!;
    final pdf = await buildReportPdf(
      report: r,
      table: r.build(d),
      companyName: 'Sai Constructions',
      sitesText: 'All sites',
      periodLine: periodText(d.from, d.to),
      branding: const PdfBranding(footerText: '98480 12345 | saibuilders.in', accent: 0xFF0E7C66, showFooter: false),
      now: now,
    );
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    final xlsx = buildReportXlsx(r, r.build(d));
    expect(xlsx.take(2), [0x50, 0x4B], reason: 'an .xlsx is a zip');
    expect(reportFileName(r, now, 'pdf'), 'FieldOS Expenses 20-11-2026.pdf');
    expect(cellText(12000.0, money: true), contains('12,000'));
    expect(cellText(DateTime(2026, 11, 3)), isNotEmpty);
  });

  test('branding: footer line joins the company\'s text and the FieldOS line', () async {
    expect(const PdfBranding().footerLine, 'Made with FieldOS');
    expect(const PdfBranding(showFooter: false).hasFooter, isFalse);
    expect(const PdfBranding(footerText: ' Call 98480 12345 ').footerLine, 'Call 98480 12345  |  Made with FieldOS');
    await setFooterText(db, companyId, 'x' * 300);
    await setAccent(db, companyId, 0xFF0E7C66);
    final b = await loadBranding(db, companyId);
    expect(b.footerText.length, footerTextMax);
    expect(b.accent, 0xFF0E7C66);
    await setAccent(db, companyId, null);
    expect((await loadBranding(db, companyId)).accent, isNull);
  });
}
