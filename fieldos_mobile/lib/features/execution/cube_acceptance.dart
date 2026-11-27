/// Concrete cube acceptance as IS 456:2000 asks for it.
///
/// Read from the standard itself (the scan at law.resource.org), not from
/// memory: clause 15.4, clause 16.1, Table 8 and Table 11.
///
///  - 15.4: a sample's test result is the average of three specimens. If a
///    specimen is more than 15% from that average, the sample's results are
///    invalid.
///  - 16.1: the concrete complies when BOTH hold: (a) the mean of every group
///    of four consecutive (non-overlapping) test results reaches the limit of
///    Table 11 column 2, and (b) every individual test result reaches column 3.
///  - Table 11, group of 4: fck + 0.825 x the established standard deviation
///    (rounded to the nearest 0.5 N/mm2) or fck + 3 (M15) / fck + 4 (M20 and
///    above), whichever is greater. Individual: fck - 3 (M15) or fck - 4
///    (M20 and above). The M15 digit is faint in the scan; it follows the +3 /
///    +4 split of the group column.
///  - Table 8, used when no established standard deviation exists: 3.5 for M10
///    and M15, 4.0 for M20 and M25, 5.0 for M30 and above.
///
/// The 7 and 14 day cubes are not part of this (the standard accepts concrete
/// on the 28-day result); the app shows a miss there as a warning.
library;

import 'dart:math' as math;

/// 25 for "M25". Kept here (not imported from site_ops_rules) so that file can
/// use this one without the two importing each other.
double? _fckOf(String grade) {
  final m = RegExp(r'^M\s*(\d{2})$', caseSensitive: false).firstMatch(grade.trim());
  return m == null ? null : double.parse(m.group(1)!);
}

/// The concrete grade a cube test was taken for, from its parameter
/// ("Compressive strength M25" -> "M25"), or null.
String? gradeOfTest(String parameter) {
  final m = RegExp(r'\bM\s?(\d{2})\b').firstMatch(parameter);
  return m == null ? null : 'M${m.group(1)}';
}

/// Table 8: the standard deviation assumed when the site has none of its own.
double assumedStdDev(double fck) {
  if (fck <= 15) return 3.5;
  if (fck <= 25) return 4.0;
  return 5.0;
}

/// How far above fck the group mean must be at least, whatever the standard
/// deviation says (Table 11 column 2).
double _groupFloor(double fck) => fck <= 15 ? 3 : 4;

/// How far below fck one sample may fall (Table 11 column 3).
double _individualMargin(double fck) => fck <= 15 ? 3 : 4;

double _roundToHalf(double x) => (x * 2).roundToDouble() / 2;

/// The least one sample may show (Table 11 column 3).
double individualLimit(double fck) => fck - _individualMargin(fck);

/// The least the mean of a group of four samples may show (Table 11 column
/// 2). [sd] is the site's established standard deviation, if it has one.
double groupLimit(double fck, {double? sd}) {
  final s = _roundToHalf(sd ?? assumedStdDev(fck));
  return math.max(fck + 0.825 * s, fck + _groupFloor(fck));
}

/// Three cubes of one sample, judged under clause 15.4.
class SpecimenCheck {
  const SpecimenCheck({required this.mean, required this.valid, required this.worstSpreadPct});

  /// The sample's test result: the average of its specimens.
  final double mean;

  /// False when a specimen is more than 15% from the average.
  final bool valid;

  /// The largest distance of a specimen from the average, in percent of it.
  final double worstSpreadPct;
}

/// Clause 15.4. Exactly three specimens make a sample.
SpecimenCheck checkSpecimens(List<double> specimens) {
  if (specimens.length != 3) throw ArgumentError('A sample is three specimens (IS 456 clause 15.4).');
  if (specimens.any((s) => s <= 0 || s.isNaN)) throw ArgumentError('A specimen must be a positive strength.');
  final mean = specimens.reduce((a, b) => a + b) / 3;
  final worst = specimens.map((s) => (s - mean).abs() / mean * 100).reduce(math.max);
  // A hair of tolerance so that exactly 15% (as written on the form) is valid.
  return SpecimenCheck(mean: mean, valid: worst <= 15 + 1e-9, worstSpreadPct: worst);
}

/// One group of four consecutive samples.
class GroupResult {
  const GroupResult({required this.first, required this.last, required this.mean, required this.limit});

  /// 1-based positions of its first and last sample, in the order tested.
  final int first;
  final int last;
  final double mean;
  final double limit;
  bool get complies => mean + 1e-9 >= limit;
}

/// The acceptance of one grade of concrete, from its 28-day sample results in
/// the order they were tested. An invalid sample (clause 15.4) is left out
/// before calling this.
class GradeAcceptance {
  const GradeAcceptance({
    required this.grade,
    required this.fck,
    required this.samples,
    required this.groups,
    required this.individualLimit,
    required this.belowIndividual,
  });

  final String grade;
  final double fck;
  final int samples;
  final List<GroupResult> groups;
  final double individualLimit;

  /// Positions (1-based) of samples under the individual limit.
  final List<int> belowIndividual;

  /// Samples in the group still being filled, 0 to 3.
  int get inOpenGroup => samples % 4;

  /// Samples still needed before the open group can be judged (0 when none is open).
  int get needed => inOpenGroup == 0 ? 0 : 4 - inOpenGroup;

  /// True when nothing so far breaks the standard: every complete group and
  /// every sample is within its limit. A group not yet complete is not judged.
  bool get complies => belowIndividual.isEmpty && groups.every((g) => g.complies);
}

GradeAcceptance evaluateGrade(String grade, List<double> sampleMeans, {double? sd}) {
  final fck = _fckOf(grade);
  if (fck == null) throw ArgumentError('Unknown concrete grade: $grade');
  final groups = <GroupResult>[];
  for (var i = 0; i + 4 <= sampleMeans.length; i += 4) {
    final g = sampleMeans.sublist(i, i + 4);
    groups.add(GroupResult(first: i + 1, last: i + 4, mean: g.reduce((a, b) => a + b) / 4, limit: groupLimit(fck, sd: sd)));
  }
  final limit = individualLimit(fck);
  return GradeAcceptance(
    grade: grade,
    fck: fck,
    samples: sampleMeans.length,
    groups: groups,
    individualLimit: limit,
    belowIndividual: [
      for (var i = 0; i < sampleMeans.length; i++)
        if (sampleMeans[i] + 1e-9 < limit) i + 1,
    ],
  );
}
