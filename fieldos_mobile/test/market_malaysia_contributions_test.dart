/// Malaysia's EPF, SOCSO and EIS on staff salaries, payslips and the wage
/// sheet, with worked examples from the official tables; India's PF and
/// ESI stay as they were and other markets show nothing.
///
/// RM1,700: EPF band 1,680.01-1,700 (11% and 13% of 1,700: 187 and 221);
/// SOCSO band 1,600.01-1,700 (employer 28.85, employee 8.25); EIS 3.30
/// each. RM5,000: EPF 550 / 650, SOCSO 86.65 / 24.75, EIS 9.90. RM5,500:
/// EPF 605 / 660 (12% above RM5,000), SOCSO 95.35 / 27.25, EIS 10.90.
/// RM7,000: EPF 770 / 840, SOCSO and EIS at the RM6,000 ceiling (104.15
/// / 29.75, 11.90). A foreign worker on RM1,700: EPF 34 each, SOCSO as a
/// Malaysian's (28.85 / 8.25), no EIS. Sources are in the library note of
/// lib/features/payroll/malaysia_contributions.dart.
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

/// PERKESO's contribution tables as printed, one row per wage band: (top of
/// band in RM, First Category employer, First Category employee, Second
/// Category (Employment Injury only) employer, EIS each). Act 4: booklet
/// pp. 35-38; Act 800: pp. 51-54, at
/// https://perkeso.gov.my/images/dokumen/risalah/2025-BOOKLET_PERKESO_BI.pdf
/// (and _BM.pdf), the RM6,000 ceiling being in force from October 2024.
const _perkesoTable = [
  (30.0, 0.40, 0.10, 0.30, 0.05),
  (50.0, 0.70, 0.20, 0.50, 0.10),
  (70.0, 1.10, 0.30, 0.80, 0.15),
  (100.0, 1.50, 0.40, 1.10, 0.20),
  (140.0, 2.10, 0.60, 1.50, 0.25),
  (200.0, 2.95, 0.85, 2.10, 0.35),
  (300.0, 4.35, 1.25, 3.10, 0.50),
  (400.0, 6.15, 1.75, 4.40, 0.70),
  (500.0, 7.85, 2.25, 5.60, 0.90),
  (600.0, 9.65, 2.75, 6.90, 1.10),
  (700.0, 11.35, 3.25, 8.10, 1.30),
  (800.0, 13.15, 3.75, 9.40, 1.50),
  (900.0, 14.85, 4.25, 10.60, 1.70),
  (1000.0, 16.65, 4.75, 11.90, 1.90),
  (1100.0, 18.35, 5.25, 13.10, 2.10),
  (1200.0, 20.15, 5.75, 14.40, 2.30),
  (1300.0, 21.85, 6.25, 15.60, 2.50),
  (1400.0, 23.65, 6.75, 16.90, 2.70),
  (1500.0, 25.35, 7.25, 18.10, 2.90),
  (1600.0, 27.15, 7.75, 19.40, 3.10),
  (1700.0, 28.85, 8.25, 20.60, 3.30),
  (1800.0, 30.65, 8.75, 21.90, 3.50),
  (1900.0, 32.35, 9.25, 23.10, 3.70),
  (2000.0, 34.15, 9.75, 24.40, 3.90),
  (2100.0, 35.85, 10.25, 25.60, 4.10),
  (2200.0, 37.65, 10.75, 26.90, 4.30),
  (2300.0, 39.35, 11.25, 28.10, 4.50),
  (2400.0, 41.15, 11.75, 29.40, 4.70),
  (2500.0, 42.85, 12.25, 30.60, 4.90),
  (2600.0, 44.65, 12.75, 31.90, 5.10),
  (2700.0, 46.35, 13.25, 33.10, 5.30),
  (2800.0, 48.15, 13.75, 34.40, 5.50),
  (2900.0, 49.85, 14.25, 35.60, 5.70),
  (3000.0, 51.65, 14.75, 36.90, 5.90),
  (3100.0, 53.35, 15.25, 38.10, 6.10),
  (3200.0, 55.15, 15.75, 39.40, 6.30),
  (3300.0, 56.85, 16.25, 40.60, 6.50),
  (3400.0, 58.65, 16.75, 41.90, 6.70),
  (3500.0, 60.35, 17.25, 43.10, 6.90),
  (3600.0, 62.15, 17.75, 44.40, 7.10),
  (3700.0, 63.85, 18.25, 45.60, 7.30),
  (3800.0, 65.65, 18.75, 46.90, 7.50),
  (3900.0, 67.35, 19.25, 48.10, 7.70),
  (4000.0, 69.15, 19.75, 49.40, 7.90),
  (4100.0, 70.85, 20.25, 50.60, 8.10),
  (4200.0, 72.65, 20.75, 51.90, 8.30),
  (4300.0, 74.35, 21.25, 53.10, 8.50),
  (4400.0, 76.15, 21.75, 54.40, 8.70),
  (4500.0, 77.85, 22.25, 55.60, 8.90),
  (4600.0, 79.65, 22.75, 56.90, 9.10),
  (4700.0, 81.35, 23.25, 58.10, 9.30),
  (4800.0, 83.15, 23.75, 59.40, 9.50),
  (4900.0, 84.85, 24.25, 60.60, 9.70),
  (5000.0, 86.65, 24.75, 61.90, 9.90),
  (5100.0, 88.35, 25.25, 63.10, 10.10),
  (5200.0, 90.15, 25.75, 64.40, 10.30),
  (5300.0, 91.85, 26.25, 65.60, 10.50),
  (5400.0, 93.65, 26.75, 66.90, 10.70),
  (5500.0, 95.35, 27.25, 68.10, 10.90),
  (5600.0, 97.15, 27.75, 69.40, 11.10),
  (5700.0, 98.85, 28.25, 70.60, 11.30),
  (5800.0, 100.65, 28.75, 71.90, 11.50),
  (5900.0, 102.35, 29.25, 73.10, 11.70),
  (6000.0, 104.15, 29.75, 74.40, 11.90),
];

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

    test('a foreign worker: EPF 2% each, SOCSO First Category like a Malaysian, no EIS', () {
      // PERKESO booklet pp. 19-20: foreign workers are in the Invalidity
      // Scheme from 1 July 2024, so the First Category table, employee share
      // included; only those first covered at 55+ are Employment Injury only.
      final c = malaysiaContributions(1700, foreign: true);
      _expect(c, epfEe: 34, epfEr: 34, socsoEe: 8.25, socsoEr: 28.85, eis: 0);
      expect(c.employeeTotal, 42.25);
      expect(c.employerTotal, 62.85);
      _expect(malaysiaContributions(7000, foreign: true), epfEe: 140, epfEr: 140, socsoEe: 29.75, socsoEr: 104.15, eis: 0);
      _expect(malaysiaContributions(30, foreign: true), epfEe: 1, epfEr: 1, socsoEe: 0.10, socsoEr: 0.40, eis: 0);
    });

    test('non-citizen EPF: 2% of the wage itself, rounded up to the ringgit (secondary sources)', () {
      // UNVERIFIED against KWSP's Part F (unreachable); see the library note.
      for (final (wage, share) in [
        (10.0, 0.0),
        (10.01, 1.0), // 0.20 -> 1
        (1700.0, 34.0),
        (1750.0, 35.0), // no RM20 band: 35.00 exactly, not 2% of 1,760
        (1750.01, 36.0),
        (3000.0, 60.0),
        (5000.01, 101.0),
        (25000.01, 501.0),
      ]) {
        final c = malaysiaContributions(wage, foreign: true);
        expect((c.epfEmployee, c.epfEmployer), (share, share), reason: 'RM$wage');
      }
    });

    test("EPF Part A rows (a third party's copy of Jadual Ketiga Bahagian A)", () {
      // (wage, employer, employee); kwsp.gov.my itself could not be read.
      for (final (wage, er, ee) in [
        (10.0, 0.0, 0.0),
        (10.01, 3.0, 3.0),
        (20.0, 3.0, 3.0),
        (20.01, 6.0, 5.0),
        (40.0, 6.0, 5.0),
        (40.01, 8.0, 7.0),
        (60.0, 8.0, 7.0),
        (4960.01, 648.0, 548.0),
        (4980.0, 648.0, 548.0),
        (4980.01, 650.0, 550.0),
        (5000.0, 650.0, 550.0),
        (5000.01, 612.0, 561.0),
        (5100.0, 612.0, 561.0),
        (5100.01, 624.0, 572.0),
        (5200.0, 624.0, 572.0),
        (19700.01, 2376.0, 2178.0),
        (19800.0, 2376.0, 2178.0),
        (19800.01, 2388.0, 2189.0),
        (19900.01, 2400.0, 2200.0),
        (20000.0, 2400.0, 2200.0),
      ]) {
        final c = malaysiaContributions(wage);
        expect((c.epfEmployer, c.epfEmployee), (er, ee), reason: 'RM$wage');
      }
    });

    test("every row of PERKESO's Act 4 and Act 800 tables, at both ends of each band", () {
      var bottom = 0.0;
      for (final (top, er, ee, injuryOnly, eis) in _perkesoTable) {
        for (final wage in [bottom + 0.01, top]) {
          final c = malaysiaContributions(wage);
          expect((c.socsoEmployer, c.socsoEmployee, c.eisEmployee, c.eisEmployer), (er, ee, eis, eis),
              reason: 'RM$wage');
          expect(socsoEmploymentInjuryOnly(wage), injuryOnly, reason: 'RM$wage, Employment Injury only');
          final f = malaysiaContributions(wage, foreign: true);
          expect((f.socsoEmployer, f.socsoEmployee, f.eisEmployee), (er, ee, 0.0), reason: 'RM$wage, foreign');
        }
        bottom = top;
      }
      expect(bottom, socsoWageCeiling);
      // "When wages exceed RM6,000": the RM6,000 row again.
      for (final wage in [6000.01, 6050.0, 10000.0, 25000.0]) {
        final c = malaysiaContributions(wage);
        expect((c.socsoEmployer, c.socsoEmployee, c.eisEmployee), (104.15, 29.75, 11.90), reason: 'RM$wage');
        expect(socsoEmploymentInjuryOnly(wage), 74.40, reason: 'RM$wage');
      }
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
      _expect(agus.contributions, epfEe: 34, epfEr: 34, socsoEe: 8.25, socsoEr: 28.85, eis: 0);
      expect(agus.netPay, 1657.75);
      final t = contributionTotals(c);
      expect(t.employee, 240.80);
      expect(t.employer, 316.00);
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
