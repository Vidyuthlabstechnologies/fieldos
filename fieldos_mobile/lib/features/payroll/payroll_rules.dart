/// Monthly salaries for staff: pay for the days worked, then PF, ESI,
/// professional tax and advance recovery, to the amount paid.
///
/// The usual private-sector rules, kept to what a small builder runs:
/// - Pay is the monthly salary for the days paid: each part (basic, HRA,
///   other) times paid days over the days in the month, to the rupee.
/// - PF: 12% from the employee and 12% from the company, on the basic
///   earned up to Rs 15,000 (the statutory wage ceiling).
/// - ESI: when the full monthly salary is Rs 21,000 or less, 0.75% from
///   the employee and 3.25% from the company on what was earned, each
///   rounded up to the rupee.
/// - Professional tax, Telangana and Andhra Pradesh slabs on what was
///   earned: nil up to Rs 15,000, Rs 150 up to Rs 20,000, Rs 200 above.
/// - An advance is recovered from the pay, never more than is left of it
///   or more than is still owed.
library;

import 'dart:math' as math;

import 'package:fieldos_mobile/data/app_database.dart';

const pfWageCeiling = 15000.0;
const pfRate = 0.12;
const esiWageLimit = 21000.0;
const esiEmployeeRate = 0.0075;
const esiEmployerRate = 0.0325;

const ptStates = ['TS', 'AP', 'none'];
const ptStateLabels = {'TS': 'Telangana', 'AP': 'Andhra Pradesh', 'none': 'No professional tax'};

const payModes = {'bank': 'Bank transfer', 'upi': 'UPI', 'cash': 'Cash', 'cheque': 'Cheque'};

String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

DateTime monthStart(String key) => DateTime(int.parse(key.substring(0, 4)), int.parse(key.substring(5, 7)));

int daysInMonth(String key) {
  final s = monthStart(key);
  return DateTime(s.year, s.month + 1, 0).day;
}

String shiftMonth(String key, int by) {
  final s = monthStart(key);
  return monthKey(DateTime(s.year, s.month + by));
}

double professionalTax(String state, double grossEarned) {
  if (state != 'TS' && state != 'AP') return 0;
  if (grossEarned <= 15000) return 0;
  if (grossEarned <= 20000) return 150;
  return 200;
}

double fullMonthGross(StaffMember s) => s.basic + s.hra + s.otherAllowance;

class PayCalc {
  const PayCalc({
    required this.daysInMonth,
    required this.paidDays,
    required this.basic,
    required this.hra,
    required this.otherAllowance,
    required this.pfEmployee,
    required this.esiEmployee,
    required this.pt,
    required this.advanceRecovery,
    required this.otherDeduction,
    required this.pfEmployer,
    required this.esiEmployer,
  });
  final int daysInMonth;
  final double paidDays;
  final double basic;
  final double hra;
  final double otherAllowance;
  final double pfEmployee;
  final double esiEmployee;
  final double pt;
  final double advanceRecovery;
  final double otherDeduction;
  final double pfEmployer;
  final double esiEmployer;

  double get gross => basic + hra + otherAllowance;
  double get deductions => pfEmployee + esiEmployee + pt + advanceRecovery + otherDeduction;
  double get net => math.max(0, gross - deductions);

  /// What the month costs the company: pay plus its PF and ESI share.
  double get costToCompany => gross + pfEmployer + esiEmployer;
}

/// The month's pay for [s] with [paidDays] of [days]. [advanceWanted] is
/// what to recover this month, cut to [advanceOwed] and to what is left
/// after the other deductions.
PayCalc computePay(
  StaffMember s, {
  required int days,
  required double paidDays,
  double advanceWanted = 0,
  double advanceOwed = 0,
  double otherDeduction = 0,
}) {
  if (days < 28 || days > 31) throw ArgumentError('A month has 28 to 31 days.');
  final pd = paidDays.clamp(0, days).toDouble();
  final ratio = pd / days;
  final basic = (s.basic * ratio).roundToDouble();
  final hra = (s.hra * ratio).roundToDouble();
  final other = (s.otherAllowance * ratio).roundToDouble();
  final gross = basic + hra + other;

  final pfWage = math.min(basic, pfWageCeiling);
  final pfEmp = s.pf ? (pfWage * pfRate).roundToDouble() : 0.0;
  final pfEr = s.pf ? (pfWage * pfRate).roundToDouble() : 0.0;
  final esiOn = s.esi && fullMonthGross(s) <= esiWageLimit && gross > 0;
  final esiEmp = esiOn ? (gross * esiEmployeeRate).ceilToDouble() : 0.0;
  final esiEr = esiOn ? (gross * esiEmployerRate).ceilToDouble() : 0.0;
  final pt = professionalTax(s.ptState, gross);
  final otherDed = math.max(0.0, otherDeduction).roundToDouble();

  final room = math.max(0.0, gross - pfEmp - esiEmp - pt - otherDed);
  final adv = math.min(math.max(0.0, advanceWanted), math.min(math.max(0.0, advanceOwed), room)).roundToDouble();

  return PayCalc(
    daysInMonth: days,
    paidDays: pd,
    basic: basic,
    hra: hra,
    otherAllowance: other,
    pfEmployee: pfEmp,
    esiEmployee: esiEmp,
    pt: pt,
    advanceRecovery: adv,
    otherDeduction: otherDed,
    pfEmployer: pfEr,
    esiEmployer: esiEr,
  );
}

/// Advances given less what payslips have recovered. [exceptLineId] leaves
/// out the payslip being worked on, so editing it does not count its own
/// recovery twice.
double advanceOwed(String staffId, Iterable<StaffAdvance> advances, Iterable<PayrollLine> lines,
    {String? exceptLineId}) {
  var owed = 0.0;
  for (final a in advances) {
    if (a.staffId == staffId) owed += a.amount;
  }
  for (final l in lines) {
    if (l.staffId == staffId && l.id != exceptLineId) owed -= l.advanceRecovery;
  }
  return math.max(0, owed);
}

typedef PayrollTotals = ({
  int people,
  int paid,
  double gross,
  double net,
  double pf,
  double esi,
  double pt,
  double cost,
});

/// The month's totals. PF and ESI are both shares, what goes to the
/// government; PT is what was cut from pay.
PayrollTotals payrollTotals(Iterable<PayrollLine> lines) {
  var people = 0, paid = 0;
  var gross = 0.0, net = 0.0, pf = 0.0, esi = 0.0, pt = 0.0, cost = 0.0;
  for (final l in lines) {
    people++;
    if (l.status == 'paid') paid++;
    gross += l.gross;
    net += l.net;
    pf += l.pfEmployee + l.pfEmployer;
    esi += l.esiEmployee + l.esiEmployer;
    pt += l.pt;
    cost += l.gross + l.pfEmployer + l.esiEmployer;
  }
  return (people: people, paid: paid, gross: gross, net: net, pf: pf, esi: esi, pt: pt, cost: cost);
}
