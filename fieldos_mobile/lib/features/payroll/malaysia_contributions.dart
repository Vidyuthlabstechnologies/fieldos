/// Malaysia's statutory contributions on a month's wages: EPF (KWSP),
/// SOCSO (PERKESO) and EIS (SIP), the employee's share cut from pay and
/// the employer's share paid on top.
///
/// Worked in sen (whole numbers) so a band edge never lands a cent off.
///
/// Sources, checked November 2026 (test/market_malaysia_contributions_test
/// holds the official rows these are tested against):
///
/// - SOCSO and EIS: PERKESO's booklet, which prints both tables in full
///   (Act 4, pp. 35-38; Act 800, pp. 51-54), every row of which the tests
///   check: https://perkeso.gov.my/images/dokumen/risalah/2025-BOOKLET_PERKESO_BI.pdf
///   (and the Malay 2025-BOOKLET_PERKESO_BM.pdf beside it). The booklet
///   prints no date of its own; the tables end at RM6,000, the ceiling in
///   force from 1 October 2024 wages
///   (https://perkeso.gov.my/en/contribution-rate.html).
/// - EPF Third Schedule, Part A: kwsp.gov.my turned every request away
///   (a bot check), so the official PDF could not be read. The bands,
///   rounding and the 13%/12% step at RM5,000 match a copy of Jadual
///   Ketiga Bahagian A hosted by a third party
///   (https://cpagroup.com.my/supplementary/EPF%20Table.pdf, undated), not
///   KWSP itself.
/// - EPF for non-citizens, Part F (from October 2025 wages): NOT checked
///   against the official schedule (https://www.kwsp.gov.my/documents/d/guest/jadual-ketiga-bm-1-okt-2025,
///   unreachable). Three secondary write-ups agree on 2% each of the
///   month's wage itself (no bands), nothing on RM10 or less, rounded up to
///   the next ringgit; that is what is used.
///
/// The rules:
///
/// - EPF, Part A, Malaysians under 60: the employee pays 11%; the employer
///   13% on wages up to RM5,000 and 12% above. The schedule charges each
///   rate on the top of the wage's band (RM20 bands up to RM5,000, RM100
///   bands up to RM20,000) and rounds up to the next ringgit; above
///   RM20,000 the rate is on the wage itself, again rounded up. Nothing is
///   due on RM10 or less.
/// - SOCSO, First Category (Employment Injury and Invalidity), on wages up
///   to RM6,000. From RM200 up the table is in RM100 bands, charged on the
///   band's middle: the employee pays 0.5% of it and the two shares
///   together are 2.25% rounded to the nearest 10 sen (the employer's
///   ~1.75% is the rest), which gives every published row. The six bands
///   up to RM200 do not follow one formula and are copied from the table.
/// - Foreign workers are in the same First Category, employee share
///   included, since the Invalidity Scheme covered them from 1 July 2024
///   (booklet p. 19-20); only those 55 or over when first covered, or 60
///   and over, are in the Second Category (Employment Injury only,
///   [socsoEmploymentInjuryOnly]). No EIS for foreign workers (p. 46).
/// - EIS, Employment Insurance System Act 2017: 0.2% each of the band's
///   middle on the same bands and RM6,000 ceiling.
///
/// Not handled, because the app does not record them: workers aged 60 and
/// over (EPF and SOCSO change, EIS stops), foreign workers first covered at
/// 55 or over, EIS's exemption for those who start work after 57, the
/// employee's choice to pay EPF above 11%, the 13% employer rate on a bonus
/// that lifts a RM5,000-or-less wage above RM5,000, and MTD/PCB income tax.
/// Nor is LINDUNG 24 Jam (the Non-Employment Injury Scheme, SKBBK): an
/// employee-only share of about 0.75% that PERKESO publishes as a column
/// beside the Act 4 table
/// (https://perkeso.gov.my/images/lindung/lindung-24-jam/NewContributionRateIncludingSKBBK.pdf,
/// undated). Reported from June 2026 and made voluntary for Malaysians on
/// 8 July 2026 (Sinar Harian, 8 July 2026); whether it binds foreign
/// workers, and from when, was not confirmed from an official source.
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
/// the period's wages). [foreign] is a worker on a foreign worker's permit:
/// EPF 2% each, SOCSO as for a Malaysian, no EIS.
///
/// [epfWages] is the part of the wage EPF is charged on, when it differs:
/// overtime pay is not "wages" for EPF (EPF Act 1991, s2), but SOCSO and
/// EIS are charged on it. Left out, EPF uses the whole wage.
MalaysiaContributions malaysiaContributions(double monthlyWage, {bool foreign = false, double? epfWages}) {
  final w = _sen(monthlyWage);
  if (w <= 0) return MalaysiaContributions.none;
  final e = epfWages == null ? w : _sen(epfWages.clamp(0, monthlyWage).toDouble());
  final (socsoEr, socsoEe) = _socsoFirstCategory(w);
  if (foreign) {
    return MalaysiaContributions(
      epfEmployee: _rm(epfNonCitizenShare(e)),
      epfEmployer: _rm(epfNonCitizenShare(e)),
      socsoEmployee: _rm(socsoEe),
      socsoEmployer: _rm(socsoEr),
    );
  }
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

/// A non-citizen's EPF share in sen (Part F, from October 2025 wages): 2%
/// of the wage itself, rounded up to the next ringgit; nothing on RM10 or
/// less. Unverified against the official schedule: see the library note.
int epfNonCitizenShare(int wageSen) {
  if (wageSen <= 1000) return 0;
  return (wageSen * 2 + 9999) ~/ 10000 * 100;
}

int _bandTop(int sen, int width) => ((sen + width - 1) ~/ width) * width;

/// SOCSO / EIS bands up to RM200, copied from PERKESO's tables (booklet
/// above), in sen: (top of band, First Category employer, First Category
/// employee, Employment Injury only employer, EIS each).
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

/// SOCSO's Second Category (Employment Injury only), employer's share in
/// RM: 1.25% of the band's middle to the nearest 10 sen. For workers the
/// app cannot pick out yet (see the library note), kept because the table
/// is checked row by row.
double socsoEmploymentInjuryOnly(double monthlyWage) {
  final w = _sen(monthlyWage);
  if (w <= 0) return 0;
  if (_lowBand(w) case final b?) return _rm(b.$4);
  return _rm(_nearest10Sen(_bandMiddleRinggit(w), 125));
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
