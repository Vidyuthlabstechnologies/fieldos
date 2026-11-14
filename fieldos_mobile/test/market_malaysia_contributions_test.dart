/// Malaysia's EPF, SOCSO and EIS on staff salaries, payslips and the wage
/// sheet, with worked examples from the official tables; India's PF and
/// ESI stay as they were and other markets show nothing.
///
/// RM1,700: EPF band 1,680.01-1,700 (11% and 13% of 1,700: 187 and 221);
/// SOCSO band 1,600.01-1,700 (employer 28.85, employee 8.25); EIS 3.30
/// each. RM5,000: EPF 550 / 650, SOCSO 86.65 / 24.75, EIS 9.90. RM5,500:
/// EPF 605 / 660 (12% above RM5,000), SOCSO 95.35 / 27.25, EIS 10.90.
/// RM7,000: EPF 770 / 840, SOCSO and EIS at the RM6,000 ceiling (104.15
/// / 29.75, 11.90).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_contributions.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/payroll/malaysia_contributions.dart';
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';
import 'package:fieldos_mobile/features/payroll/payslip_pdf.dart';

StaffMember _staff(double basic, {double hra = 0, bool pf = true, bool esi = true}) => StaffMember(
      id: 's',
      companyId: 'c',
      name: 'Aminah',
      basic: basic,
      hra: hra,
      otherAllowance: 0,
      pf: pf,
      esi: esi,
      ptState: 'TS', // the default the form leaves; Malaysia has no PT
      active: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

PayrollLine _line(PayCalc c) => PayrollLine(
      id: 'l',
      companyId: 'c',
      staffId: 's',
      month: '2026-11',
      daysInMonth: c.daysInMonth,
      paidDays: c.paidDays,
      basic: c.basic,
      hra: c.hra,
      otherAllowance: c.otherAllowance,
      gross: c.gross,
      pfEmployee: c.pfEmployee,
      esiEmployee: c.esiEmployee,
      pt: c.pt,
      advanceRecovery: c.advanceRecovery,
      otherDeduction: c.otherDeduction,
      net: c.net,
      pfEmployer: c.pfEmployer,
      esiEmployer: c.esiEmployer,
      status: 'draft',
      createdBy: 'u',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void _expect(MalaysiaContributions c,
    {required double epfEe, required double epfEr, required double socsoEe, required double socsoEr,
    required double eis}) {
  expect(c.epfEmployee, epfEe, reason: 'EPF employee');
  expect(c.epfEmployer, epfEr, reason: 'EPF employer');
  expect(c.socsoEmployee, socsoEe, reason: 'SOCSO employee');
  expect(c.socsoEmployer, socsoEr, reason: 'SOCSO employer');
  expect(c.eisEmployee, eis, reason: 'EIS employee');
  expect(c.eisEmployer, eis, reason: 'EIS employer');
}

void main() {
  tearDown(() => debugSetMarket(Market.india));

  group('the official tables', () {
    test('RM1,700', () {
      final c = malaysiaContributions(1700);
      _expect(c, epfEe: 187, epfEr: 221, socsoEe: 8.25, socsoEr: 28.85, eis: 3.30);
      expect(c.employeeTotal, 198.55);
      expect(c.employerTotal, 253.15);
    });

    test('RM5,000: the last wage at the 13% employer rate', () {
      _expect(malaysiaContributions(5000), epfEe: 550, epfEr: 650, socsoEe: 24.75, socsoEr: 86.65, eis: 9.90);
    });

    test('RM5,500: 12% employer EPF, RM100 EPF bands', () {
      _expect(malaysiaContributions(5500), epfEe: 605, epfEr: 660, socsoEe: 27.25, socsoEr: 95.35, eis: 10.90);
      // RM5,000.01 is already in the 5,000.01-5,100 band at 12%.
      expect(malaysiaContributions(5000.01).epfEmployer, 612);
      expect(malaysiaContributions(5000.01).epfEmployee, 561);
    });

    test('RM7,000: SOCSO and EIS stop at the RM6,000 ceiling, EPF does not', () {
      _expect(malaysiaContributions(7000), epfEe: 770, epfEr: 840, socsoEe: 29.75, socsoEr: 104.15, eis: 11.90);
      _expect(malaysiaContributions(6000), epfEe: 660, epfEr: 720, socsoEe: 29.75, socsoEr: 104.15, eis: 11.90);
    });

    test('EPF bands: the top of the RM20 band, rounded up to the ringgit', () {
      // 1,700.01 is in 1,700.01-1,720: 11% of 1,720 = 189.20 -> 190, 13% = 223.60 -> 224.
      expect(malaysiaContributions(1700.01).epfEmployee, 190);
      expect(malaysiaContributions(1700.01).epfEmployer, 224);
      expect(malaysiaContributions(10).epfEmployee, 0);
      expect(malaysiaContributions(15).epfEmployee, 3);
      // Above RM20,000 the rate is on the wage itself: 11% of 20,050 = 2,205.50 -> 2,206.
      expect(malaysiaContributions(20050).epfEmployee, 2206);
      expect(malaysiaContributions(20050).epfEmployer, 2406);
    });

    test('SOCSO and EIS low bands, as published', () {
      // RM30 is in the RM20.01-40 EPF band: 11% and 13% of 40, rounded up.
      _expect(malaysiaContributions(30), epfEe: 5, epfEr: 6, socsoEe: 0.10, socsoEr: 0.40, eis: 0.05);
      final c = malaysiaContributions(200);
      expect((c.socsoEmployer, c.socsoEmployee, c.eisEmployee), (2.95, 0.85, 0.35));
      final d = malaysiaContributions(200.01);
      expect((d.socsoEmployer, d.socsoEmployee, d.eisEmployee), (4.35, 1.25, 0.50));
      expect(malaysiaContributions(3000).socsoEmployer, 51.65);
      expect(malaysiaContributions(3000).socsoEmployee, 14.75);
    });

    test('a foreign worker: EPF 2% each, SOCSO employment injury only, no EIS', () {
      final c = malaysiaContributions(1700, foreign: true);
      _expect(c, epfEe: 34, epfEr: 34, socsoEe: 0, socsoEr: 20.60, eis: 0);
      expect(c.employeeTotal, 34);
      expect(c.employerTotal, 54.60);
      expect(malaysiaContributions(7000, foreign: true).socsoEmployer, 74.40);
      expect(malaysiaContributions(5000, foreign: true).socsoEmployer, 61.90);
    });

    test('no wage, nothing due', () {
      expect(malaysiaContributions(0).isEmpty, isTrue);
    });
  });

  group('staff salaries', () {
    test('Malaysia: EPF in the PF columns, SOCSO + EIS in the ESI ones, no professional tax', () {
      debugSetMarket(Market.malaysia);
      final p = computePay(_staff(1700), days: 30, paidDays: 30);
      expect(p.gross, 1700);
      expect(p.pfEmployee, 187);
      expect(p.pfEmployer, 221);
      expect(p.esiEmployee, 11.55); // 8.25 + 3.30
      expect(p.esiEmployer, 32.15); // 28.85 + 3.30
      expect(p.pt, 0);
      expect(p.net, 1501.45);
      expect(p.costToCompany, 1953.15);

      final split = malaysiaLineContributions(_line(p));
      _expect(split, epfEe: 187, epfEr: 221, socsoEe: 8.25, socsoEr: 28.85, eis: 3.30);
    });

    test('Malaysia: RM5,000 basic + RM500 housing is EPF on RM5,500 at 12%', () {
      debugSetMarket(Market.malaysia);
      final p = computePay(_staff(5000, hra: 500), days: 30, paidDays: 30);
      expect(p.pfEmployee, 605);
      expect(p.pfEmployer, 660);
      expect(p.esiEmployee, 38.15); // 27.25 + 10.90
      expect(p.esiEmployer, 106.25); // 95.35 + 10.90
      expect(p.net, 4856.85);
    });

    test('Malaysia: switched off, nothing is cut; an advance never takes the sen that are not there', () {
      debugSetMarket(Market.malaysia);
      final off = computePay(_staff(7000, pf: false, esi: false), days: 30, paidDays: 30);
      expect(off.pfEmployee + off.esiEmployee + off.pfEmployer + off.esiEmployer, 0);
      expect(off.net, 7000);
      final all = computePay(_staff(1700), days: 30, paidDays: 30, advanceWanted: 5000, advanceOwed: 5000);
      expect(all.advanceRecovery, 1501.45);
      expect(all.net, 0);
    });

    test('Malaysia: the month deposits split EPF, SOCSO and EIS', () {
      debugSetMarket(Market.malaysia);
      final lines = [
        _line(computePay(_staff(1700), days: 30, paidDays: 30)),
        _line(computePay(_staff(7000), days: 30, paidDays: 30)),
      ];
      final d = malaysiaDeposits(lines);
      expect(d.epf, 187 + 221 + 770 + 840);
      expect(d.socso, closeTo(171.00, 1e-9));
      expect(d.eis, closeTo(30.40, 1e-9));
    });

    test('India is unchanged: PF on Rs 15,000, ESI above the limit nil, Telangana PT', () {
      debugSetMarket(Market.india);
      final p = computePay(_staff(18000, hra: 10000), days: 30, paidDays: 30);
      expect(p.pfEmployee, 1800);
      expect(p.pfEmployer, 1800);
      expect(p.esiEmployee, 0);
      expect(p.pt, 200);
      expect(p.net, 26000);
      final small = computePay(_staff(12000, hra: 3000), days: 30, paidDays: 30);
      expect(small.esiEmployee, 113); // 0.75% of 15,000 = 112.5, up
      expect(small.esiEmployer, 488); // 3.25% = 487.5, up
      expect(small.pt, 0);
    });

    test('the salaries screen is in the India and Malaysia apps only', () {
      for (final (m, shown) in [
        (Market.india, true),
        (Market.malaysia, true),
        (Market.us, false),
        (Market.uae, false),
        (Market.uk, false),
      ]) {
        debugSetMarket(m);
        expect(payrollShown, shown, reason: m.name);
      }
    });

    test('a Malaysian payslip PDF builds', () async {
      debugSetMarket(Market.malaysia);
      final p = computePay(_staff(1700), days: 30, paidDays: 30);
      final pdf = await buildPayslipPdf(line: _line(p), staff: _staff(1700), companyName: 'Binaan Maju');
      expect(String.fromCharCodes(pdf.take(4)), '%PDF');
    });
  });

  group('wage sheet', () {
    WageSheet sheet() {
      WageLine line(String id, double wage, double days) =>
          WageLine(key: id, name: id, workerId: id, dailyWage: wage)..days = days;
      return WageSheet(DateTime(2026, 11, 1), DateTime(2026, 12, 1), [
        line('local', 85, 20), // RM1,700
        line('agus', 85, 20), // RM1,700, PLKS on file
        line('idle', 85, 0),
      ]);
    }

    WorkerPermit permit(String workerId, String kind) => WorkerPermit(
          id: '$workerId-$kind',
          projectId: 'p',
          workerId: workerId,
          kind: kind,
          expiresOn: DateTime(2027),
          createdBy: 'u',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

    test('a PLKS permit marks a worker foreign; a passport alone does not', () {
      expect(foreignWorkerIds([permit('agus', 'plks'), permit('local', 'passport'), permit('x', 'green_card')]), {'agus'});
    });

    test('Malaysia: deductions, employer share and net pay on the period wages', () {
      debugSetMarket(Market.malaysia);
      final c = wageContributions(sheet(), foreign: {'agus'});
      expect(c.keys, unorderedEquals(['local', 'agus']));
      final local = c['local']!;
      _expect(local.contributions, epfEe: 187, epfEr: 221, socsoEe: 8.25, socsoEr: 28.85, eis: 3.30);
      expect(local.netPay, 1501.45);
      expect(local.foreign, isFalse);
      final agus = c['agus']!;
      expect(agus.foreign, isTrue);
      _expect(agus.contributions, epfEe: 34, epfEr: 34, socsoEe: 0, socsoEr: 20.60, eis: 0);
      expect(agus.netPay, 1666);
      final t = contributionTotals(c);
      expect(t.employee, 232.55);
      expect(t.employer, 307.75);
    });

    test('India and the other markets show nothing on the wage sheet', () {
      for (final m in [Market.india, Market.us, Market.uae, Market.uk]) {
        debugSetMarket(m);
        expect(wageSheetContributionsShown, isFalse, reason: m.name);
        expect(wageContributions(sheet(), foreign: {'agus'}), isEmpty, reason: m.name);
      }
    });
  });

  test('EPF leaves overtime pay out; SOCSO and EIS charge it', () {
    debugSetMarket(Market.malaysia);
    // RM1,700 of wages plus RM300 overtime pay.
    final c = malaysiaContributions(2000, epfWages: 1700);
    final plain = malaysiaContributions(1700);
    final all = malaysiaContributions(2000);
    expect(c.epfEmployee, plain.epfEmployee);
    expect(c.epfEmployer, plain.epfEmployer);
    expect(c.socsoEmployee, all.socsoEmployee);
    expect(c.socsoEmployer, all.socsoEmployer);
    expect(c.eisEmployee, all.eisEmployee);
    expect(c.epfEmployee, lessThan(all.epfEmployee));
  });
}
