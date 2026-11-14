/// Malaysia's statutory contributions on a month's wages: EPF (KWSP),
/// SOCSO (PERKESO) and EIS (SIP), the employee's share cut from pay and
/// the employer's share paid on top.
///
/// Worked in sen (whole numbers) so a band edge never lands a cent off.
///
/// - EPF, Third Schedule of the EPF Act 1991, Malaysians under 60: the
///   employee pays 11%; the employer 13% on wages up to RM5,000 and 12%
///   above. The schedule charges each rate on the top of the wage's band
///   (RM20 bands up to RM5,000, RM100 bands up to RM20,000) and rounds up
///   to the next ringgit; above RM20,000 the rate is on the wage itself,
///   again rounded up. Nothing is due on RM10 or less.
/// - EPF for foreign workers (mandatory from October 2025 wages): 2% from
///   the employee and 2% from the employer. UNCERTAIN: this uses the same
///   bands and rounding as Malaysians' schedule; check against the KWSP
///   table for non-citizens before relying on it to the ringgit.
/// - SOCSO, First Category (Employment Injury and Invalidity, under 60):
///   on wages up to RM6,000 a month (the ceiling from October 2024). From
///   RM200 up the official table is in RM100 bands, charged on the band's
///   middle: the employee pays 0.5% of it and the two shares together are
///   2.25% rounded to the nearest 10 sen (the employer's ~1.75% is the
///   rest), which reproduces the published table (RM5,000: 86.65 and
///   24.75; RM6,000 and above: 104.15 and 29.75). The six bands up to
///   RM200 are copied from the table, as they do not follow one formula.
/// - Foreign workers: SOCSO Employment Injury only, employer 1.25% on the
///   same bands (nearest 10 sen; RM6,000 and above: 74.40), no employee
///   share, no EIS.
/// - EIS, Employment Insurance System Act 2017: 0.2% each on the same
///   bands and RM6,000 ceiling.
///
/// Not handled, because the app does not record them: workers aged 60 and
/// over (EPF and SOCSO change, EIS stops), EIS's exemption for those who
/// start work after 57, the employee's choice to pay EPF above 11%, and
/// MTD/PCB income tax.
library;

class MalaysiaContributions {
  const MalaysiaContributions({
    this.epfEmployee = 0,
    this.epfEmployer = 0,
    this.socsoEmployee = 0,
    this.socsoEmployer = 0,
    this.eisEmployee = 0,
    this.eisEmployer = 0,
  });

  static const none = MalaysiaContributions();

  final double epfEmployee;
  final double epfEmployer;
  final double socsoEmployee;
  final double socsoEmployer;
  final double eisEmployee;
  final double eisEmployer;

  /// Cut from the worker's pay.
  double get employeeTotal => _sum([epfEmployee, socsoEmployee, eisEmployee]);

  /// Paid by the employer on top of the pay.
  double get employerTotal => _sum([epfEmployer, socsoEmployer, eisEmployer]);

  bool get isEmpty => employeeTotal == 0 && employerTotal == 0;
}

double _sum(List<double> xs) => _rm(xs.fold<int>(0, (s, x) => s + (x * 100).round()));
double _rm(int sen) => sen / 100;
int _sen(double rm) => (rm * 100).round();

/// The wage SOCSO and EIS stop at: RM6,000 a month from October 2024.
const socsoWageCeiling = 6000.0;

/// EPF's employer rate drops from 13% to 12% above this monthly wage.
const epfHigherEmployerRateUpTo = 5000.0;

/// The contributions on [monthlyWage] (for daily-rated workers, the sum of
/// the period's wages). [foreign] is a worker on a foreign worker's permit.
///
/// [epfWages] is the part of the wage EPF is charged on, when it differs:
/// overtime pay is not "wages" for EPF (EPF Act 1991, s2), but SOCSO and
/// EIS are charged on it. Left out, EPF uses the whole wage.
MalaysiaContributions malaysiaContributions(double monthlyWage, {bool foreign = false, double? epfWages}) {
  final w = _sen(monthlyWage);
  if (w <= 0) return MalaysiaContributions.none;
  final e = epfWages == null ? w : _sen(epfWages.clamp(0, monthlyWage).toDouble());
  if (foreign) {
    return MalaysiaContributions(
      epfEmployee: _rm(epfShare(e, 2)),
      epfEmployer: _rm(epfShare(e, 2)),
      socsoEmployer: _rm(_employmentInjuryOnly(w)),
    );
  }
  final (socsoEr, socsoEe) = _socsoFirstCategory(w);
  final eis = _eis(w);
  return MalaysiaContributions(
    epfEmployee: _rm(epfShare(e, 11)),
    epfEmployer: _rm(epfShare(e, e <= _sen(epfHigherEmployerRateUpTo) ? 13 : 12)),
    socsoEmployee: _rm(socsoEe),
    socsoEmployer: _rm(socsoEr),
    eisEmployee: _rm(eis),
    eisEmployer: _rm(eis),
  );
}

/// One EPF share in sen: [percent] of the top of [wageSen]'s band, rounded
/// up to the next ringgit.
int epfShare(int wageSen, int percent) {
  if (wageSen <= 1000) return 0;
  final int base;
  if (wageSen <= 500000) {
    base = _bandTop(wageSen, 2000);
  } else if (wageSen <= 2000000) {
    base = _bandTop(wageSen, 10000);
  } else {
    base = wageSen;
  }
  // base sen x percent / 100 = sen; up to the ringgit = / 10000, rounded up.
  final ringgit = (base * percent + 9999) ~/ 10000;
  return ringgit * 100;
}

int _bandTop(int sen, int width) => ((sen + width - 1) ~/ width) * width;

/// SOCSO / EIS bands up to RM200, from the published tables, in sen:
/// (top of band, SOCSO employer, SOCSO employee, EI-only employer, EIS each).
const _lowBands = [
  (3000, 40, 10, 30, 5),
  (5000, 70, 20, 50, 10),
  (7000, 110, 30, 80, 15),
  (10000, 150, 40, 110, 20),
  (14000, 210, 60, 150, 25),
  (20000, 295, 85, 210, 35),
];

(int, int, int, int, int)? _lowBand(int wageSen) {
  for (final b in _lowBands) {
    if (wageSen <= b.$1) return b;
  }
  return null;
}

/// The middle of [wageSen]'s RM100 band, in whole ringgit, with the wage
/// held to the RM6,000 ceiling: RM1,700 is in 1,600.01-1,700, middle 1,650.
int _bandMiddleRinggit(int wageSen) {
  final capped = wageSen > _sen(socsoWageCeiling) ? _sen(socsoWageCeiling) : wageSen;
  return _bandTop(capped, 10000) ~/ 100 - 50;
}

/// Nearest 10 sen of [percentTimes100] / 100 % of [ringgit], in sen. The
/// band middles end in 50, so this never lands on a tie.
int _nearest10Sen(int ringgit, int percentTimes100) => ((ringgit * percentTimes100 + 500) ~/ 1000) * 10;

/// (employer, employee) in sen.
(int, int) _socsoFirstCategory(int wageSen) {
  if (_lowBand(wageSen) case final b?) return (b.$2, b.$3);
  final mid = _bandMiddleRinggit(wageSen);
  final employee = mid ~/ 2; // 0.5% of mid ringgit, in sen
  final total = _nearest10Sen(mid, 225);
  return (total - employee, employee);
}

int _employmentInjuryOnly(int wageSen) {
  if (_lowBand(wageSen) case final b?) return b.$4;
  return _nearest10Sen(_bandMiddleRinggit(wageSen), 125);
}

int _eis(int wageSen) {
  if (_lowBand(wageSen) case final b?) return b.$5;
  return _bandMiddleRinggit(wageSen) ~/ 5; // 0.2% of mid ringgit, in sen
}

/// A stored payslip keeps SOCSO and EIS together in its ESI columns (the
/// table has no columns of their own). EIS is a fixed function of the
/// gross, so it is worked out again and SOCSO is the rest.
({double socso, double eis}) splitSocsoEis(double gross, double combined) {
  if (combined <= 0) return (socso: 0, eis: 0);
  final eis = _rm(_eis(_sen(gross)).clamp(0, _sen(combined)));
  return (socso: _rm(_sen(combined) - _sen(eis)), eis: eis);
}
