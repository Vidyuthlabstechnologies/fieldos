/// Staff salaries: a site engineer above the ESI limit, a supervisor
/// under it with an advance, and a driver without PF. Pay for the days
/// worked, PF on basic up to Rs 15,000, ESI only up to Rs 21,000,
/// Telangana professional tax, advance recovery that never takes more than
/// is owed or left; the month is made once, a joiner is paid from the day
/// they joined, a paid salary goes in the site's money book and is then
/// kept as it was.
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';
import 'package:fieldos_mobile/features/payroll/payslip_pdf.dart';
import 'package:fieldos_mobile/sync/sync_mappers.dart';

StaffMember _staff({double basic = 18000, double hra = 7000, double other = 3000, bool pf = true, bool esi = true,
        String pt = 'TS'}) =>
    StaffMember(
      id: 's',
      companyId: 'c',
      name: 'Anil',
      basic: basic,
      hra: hra,
      otherAllowance: other,
      pf: pf,
      esi: esi,
      ptState: pt,
      active: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('pay rules', () {
    test('above the ESI limit: PF on Rs 15,000 of basic, PT 200', () {
      final p = computePay(_staff(), days: 30, paidDays: 30);
      expect(p.gross, 28000);
      expect(p.pfEmployee, 1800);
      expect(p.pfEmployer, 1800);
      expect(p.esiEmployee, 0);
      expect(p.pt, 200);
      expect(p.net, 26000);
      expect(p.costToCompany, 29800);
    });

    test('days not worked come off every part of the pay', () {
      final p = computePay(_staff(), days: 30, paidDays: 27);
      expect(p.basic, 16200);
      expect(p.hra, 6300);
      expect(p.otherAllowance, 2700);
      expect(p.gross, 25200);
      expect(p.pfEmployee, 1800, reason: 'earned basic is still above the ceiling');
      expect(p.net, 23200);
    });

    test('at or under Rs 21,000: ESI 0.75% and 3.25% rounded up, PT 150', () {
      final s = _staff(basic: 12000, hra: 4000, other: 2000);
      final p = computePay(s, days: 30, paidDays: 30);
      expect(p.gross, 18000);
      expect(p.pfEmployee, 1440);
      expect(p.esiEmployee, 135);
      expect(p.esiEmployer, 585);
      expect(p.pt, 150);
      expect(p.net, 16275);
      final d = computePay(_staff(basic: 9000, hra: 0, other: 0, pf: false), days: 30, paidDays: 30);
      expect(d.pfEmployee, 0);
      expect(d.esiEmployee, 68);
      expect(d.esiEmployer, 293);
      expect(d.pt, 0);
      expect(d.net, 8932);
    });

    test('professional tax slabs, and none outside Telangana and Andhra Pradesh', () {
      expect(professionalTax('TS', 15000), 0);
      expect(professionalTax('TS', 15001), 150);
      expect(professionalTax('AP', 20000), 150);
      expect(professionalTax('AP', 20001), 200);
      expect(professionalTax('none', 90000), 0);
    });

    test('advance recovery is cut to what is owed and to what is left of the pay', () {
      final s = _staff(basic: 12000, hra: 4000, other: 2000);
      expect(computePay(s, days: 30, paidDays: 30, advanceWanted: 5000, advanceOwed: 3000).advanceRecovery, 3000);
      final all = computePay(s, days: 30, paidDays: 30, advanceWanted: 20000, advanceOwed: 20000);
      expect(all.advanceRecovery, 16275);
      expect(all.net, 0);
      expect(computePay(s, days: 30, paidDays: 0, advanceWanted: 500, advanceOwed: 500).advanceRecovery, 0);
    });

    test('months', () {
      expect(daysInMonth('2026-02'), 28);
      expect(daysInMonth('2028-02'), 29);
      expect(daysInMonth('2026-11'), 30);
      expect(shiftMonth('2026-01', -1), '2025-12');
      expect(shiftMonth('2026-12', 1), '2027-01');
      expect(monthKey(DateTime(2026, 3, 9)), '2026-03');
      expect(() => computePay(_staff(), days: 27, paidDays: 1), throwsArgumentError);
    });
  });

  group('a month of salaries', () {
    late AppDatabase db;
    late PayrollDao dao;
    late Company company;
    const owner = 'owner-1';

    setUp(() async {
      db = AppDatabase.memory();
      dao = db.payrollDao;
      company = await db.companyDao.create('Sai Constructions');
      await db.projectDao.create(ProjectsCompanion.insert(
          id: 'p-1', companyId: company.id, name: 'Narapally', status: const Value('active')));
    });
    tearDown(() => db.close());

    test('made once for the active staff, a joiner paid from the day they joined', () async {
      final eng = await dao.addStaff(
          companyId: company.id, name: 'Anil', basic: 18000, hra: 7000, otherAllowance: 3000, projectId: 'p-1',
          designation: 'Site engineer');
      final sup = await dao.addStaff(companyId: company.id, name: 'Bhaskar', basic: 12000, hra: 4000, otherAllowance: 2000);
      await dao.addStaff(
          companyId: company.id, name: 'Chandu', basic: 9000, pf: false, joinedOn: DateTime(2026, 11, 16));
      await dao.addStaff(companyId: company.id, name: 'Dinesh', basic: 9000, joinedOn: DateTime(2026, 12, 2));
      final gone = await dao.addStaff(companyId: company.id, name: 'Esha', basic: 9000);
      await dao.updateStaff(gone.id, name: 'Esha', basic: 9000, active: false);
      await dao.giveAdvance(staffId: sup.id, amount: 5000, by: owner, on: DateTime(2026, 11, 3));

      expect(await dao.makeMonth(company.id, '2026-11', by: owner), 3);
      expect(await dao.makeMonth(company.id, '2026-11', by: owner), 0);
      final lines = {for (final l in await dao.linesForMonth(company.id, '2026-11')) l.staffId: l};
      expect(lines[eng.id]!.net, 26000);
      expect(lines[eng.id]!.projectId, 'p-1');
      expect(lines[sup.id]!.advanceRecovery, 5000);
      expect(lines[sup.id]!.net, 11275);
      final joiner = lines.values.firstWhere((l) => l.staffId != eng.id && l.staffId != sup.id);
      expect(joiner.paidDays, 15);
      expect(joiner.gross, 4500);

      // Recover only 2,000 this month; the rest carries on.
      final changed = await dao.recalculate(lines[sup.id]!.id, paidDays: 30, advanceRecovery: 2000);
      expect(changed.net, 14275);
      expect(await dao.owedBy(sup.id), 3000);

      final t = payrollTotals(await dao.linesForMonth(company.id, '2026-11'));
      expect(t.people, 3);
      expect(t.paid, 0);
      expect(t.gross, 28000 + 18000 + 4500);
      expect(t.pf, 1800 * 2 + 1440 * 2);
    });

    test('paying puts the net pay in the site money book, then it is kept', () async {
      final eng = await dao.addStaff(companyId: company.id, name: 'Anil', basic: 18000, hra: 7000, otherAllowance: 3000,
          projectId: 'p-1');
      await dao.makeMonth(company.id, '2026-11', by: owner);
      final line = (await dao.linesForMonth(company.id, '2026-11')).single;
      final paid = await dao.markPaid(line.id, mode: 'bank', by: owner, on: DateTime(2026, 12, 1));
      expect(paid.status, 'paid');
      expect(paid.expenseId, isNotNull);
      final e = (await db.expenseDao.forProject('p-1')).single;
      expect(e.amount, 26000);
      expect(e.category, staffSalaryCategory);
      expect(e.paidTo, 'Anil');
      expect(e.mode, 'bank');
      expect(e.incurredOn, '2026-12-01');

      expect((await dao.markPaid(line.id, mode: 'cash', by: owner)).paidMode, 'bank', reason: 'paying twice does nothing');
      await expectLater(dao.recalculate(line.id, paidDays: 10, advanceRecovery: 0), throwsArgumentError);
      await expectLater(dao.deleteDraft(line.id), throwsArgumentError);
      expect((await db.expenseDao.forProject('p-1')), hasLength(1));

      final pdf = await buildPayslipPdf(line: paid, staff: eng, companyName: 'Sai Constructions', siteName: 'Narapally');
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
      expect(monthTitle('2026-11'), 'November 2026');

      final pending = [for (final o in await db.syncOutboxDao.pending()) '${o.targetTable}:${o.operation}'];
      expect(pending, containsAll(['staff_members:insert', 'payroll_lines:insert', 'payroll_lines:update', 'site_expenses:insert']));
    });

    test('a draft can be removed; office staff pay adds no site expense', () async {
      await dao.addStaff(companyId: company.id, name: 'Accounts', basic: 15000);
      await dao.makeMonth(company.id, '2026-10', by: owner);
      final l = (await dao.linesForMonth(company.id, '2026-10')).single;
      await dao.markPaid(l.id, mode: 'upi', by: owner);
      expect(await db.expenseDao.forProject('p-1'), isEmpty);
      await dao.makeMonth(company.id, '2026-11', by: owner);
      final nov = (await dao.linesForMonth(company.id, '2026-11')).single;
      await dao.deleteDraft(nov.id);
      expect(await dao.linesForMonth(company.id, '2026-11'), isEmpty);
    });

    test('staff, advances and payslips round-trip through the server format', () async {
      final s = await dao.addStaff(companyId: company.id, name: 'Anil', basic: 18000, uan: '100200300400');
      final a = await dao.giveAdvance(staffId: s.id, amount: 2500, by: owner);
      await dao.makeMonth(company.id, '2026-11', by: owner);
      final l = (await dao.linesForMonth(company.id, '2026-11')).single;
      Map<String, dynamic> j(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;
      expect(staffMemberFromSupabaseJson(j(staffMemberToSupabaseJson(s))).uan.value, '100200300400');
      expect(staffAdvanceFromSupabaseJson(j(staffAdvanceToSupabaseJson(a))).amount.value, 2500);
      final back = payrollLineFromSupabaseJson(j(payrollLineToSupabaseJson(l)));
      expect(back.net.value, l.net);
      expect(back.month.value, '2026-11');
      expect(back.advanceRecovery.value, 2500);
    });

    test('a salary needs a name and a basic pay', () async {
      await expectLater(dao.addStaff(companyId: company.id, name: ' ', basic: 9000), throwsArgumentError);
      await expectLater(dao.addStaff(companyId: company.id, name: 'X', basic: 0), throwsArgumentError);
      await expectLater(dao.addStaff(companyId: company.id, name: 'X', basic: 1, ptState: 'KA'), throwsArgumentError);
    });
  });
}
