/// IS 456:2000 cube acceptance (clauses 15.4 and 16.1, Tables 8 and 11),
/// checked against the standard's own formulas worked out by hand.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/features/execution/cube_acceptance.dart';

void main() {
  test('Table 8: the standard deviation assumed when the site has none', () {
    expect(assumedStdDev(15), 3.5);
    expect(assumedStdDev(20), 4.0);
    expect(assumedStdDev(25), 4.0);
    expect(assumedStdDev(30), 5.0);
    expect(assumedStdDev(40), 5.0);
  });

  test('Table 11 column 3: the least one sample may show is fck - 3 for M15, fck - 4 above', () {
    expect(individualLimit(15), 12);
    expect(individualLimit(20), 16);
    expect(individualLimit(25), 21);
    expect(individualLimit(30), 26);
    expect(individualLimit(40), 36);
  });

  test('Table 11 column 2: group of four, fck + 0.825 s (s to the nearest 0.5) or the floor, whichever is greater', () {
    // M15: 15 + 0.825 x 3.5 = 17.8875, floor 15 + 3 = 18.
    expect(groupLimit(15), 18);
    // M20: 20 + 0.825 x 4 = 23.3, floor 24. M25: 25 + 3.3 = 28.3, floor 29.
    expect(groupLimit(20), 24);
    expect(groupLimit(25), 29);
    // M30: 30 + 0.825 x 5 = 34.125 beats the floor of 34. M40: 44.125.
    expect(groupLimit(30), closeTo(34.125, 1e-9));
    expect(groupLimit(40), closeTo(44.125, 1e-9));
  });

  test('a site\'s own established standard deviation replaces Table 8, rounded to the nearest 0.5', () {
    // s = 6.0: 25 + 0.825 x 6 = 29.95, above the floor of 29.
    expect(groupLimit(25, sd: 6.0), closeTo(29.95, 1e-9));
    // s = 3.2 rounds to 3.0: 25 + 2.475 = 27.475, under the floor, so 29.
    expect(groupLimit(25, sd: 3.2), 29);
    // s = 5.8 rounds to 6.0.
    expect(groupLimit(25, sd: 5.8), closeTo(29.95, 1e-9));
  });

  group('clause 15.4: three specimens make a sample', () {
    test('the result is their average', () {
      final c = checkSpecimens([27, 28, 29]);
      expect(c.mean, 28);
      expect(c.valid, isTrue);
    });

    test('a specimen more than 15% from the average makes the sample invalid', () {
      final c = checkSpecimens([20, 28, 29]); // mean 25.67; 20 is 22% below
      expect(c.valid, isFalse);
      expect(c.worstSpreadPct, closeTo(22.1, 0.1));
    });

    test('exactly 15% is still valid', () {
      expect(checkSpecimens([17, 20, 23]).valid, isTrue); // mean 20, 3 off = 15%
      expect(checkSpecimens([16.9, 20, 23.1]).valid, isFalse);
    });

    test('anything but three, or a non-strength, is refused', () {
      expect(() => checkSpecimens([27, 28]), throwsArgumentError);
      expect(() => checkSpecimens([27, 28, 29, 30]), throwsArgumentError);
      expect(() => checkSpecimens([27, 28, 0]), throwsArgumentError);
    });
  });

  group('clause 16.1: both conditions must hold', () {
    test('four good samples comply', () {
      final r = evaluateGrade('M25', [28, 30, 31, 29.5]);
      expect(r.groups, hasLength(1));
      expect(r.groups.single.mean, 29.625);
      expect(r.groups.single.limit, 29);
      expect(r.groups.single.complies, isTrue);
      expect(r.complies, isTrue);
    });

    test('a group can fail although every sample alone is above the individual limit', () {
      // Each is over 21, but the mean 26.5 is under 29: the old rule (each >= 25) failed some, this one fails the GROUP.
      final r = evaluateGrade('M25', [26, 27, 28, 25]);
      expect(r.belowIndividual, isEmpty);
      expect(r.groups.single.complies, isFalse);
      expect(r.complies, isFalse);
    });

    test('one sample under the individual limit fails even if the group mean is fine', () {
      final r = evaluateGrade('M25', [34, 34, 34, 20.9]); // mean 30.7 passes the group; 20.9 < 21
      expect(r.groups.single.complies, isTrue);
      expect(r.belowIndividual, [4]);
      expect(r.complies, isFalse);
    });

    test('exactly on the individual limit passes (fck - 4 for M25)', () {
      expect(evaluateGrade('M25', [21.0]).belowIndividual, isEmpty);
      expect(evaluateGrade('M25', [20.99]).belowIndividual, [1]);
    });

    test('groups are four consecutive samples, not overlapping, in the order tested', () {
      final r = evaluateGrade('M20', [30, 30, 30, 30, 20, 20, 20, 20]);
      expect(r.groups.map((g) => (g.first, g.last)), [(1, 4), (5, 8)]);
      expect(r.groups[0].complies, isTrue);
      expect(r.groups[1].complies, isFalse, reason: 'mean 20 is under 24');
    });

    test('a group still being filled is not judged, and the app says how many more are needed', () {
      final r = evaluateGrade('M25', [30, 31, 29, 28, 30, 31]);
      expect(r.groups, hasLength(1));
      expect(r.inOpenGroup, 2);
      expect(r.needed, 2);
      final none = evaluateGrade('M25', [30, 31, 29, 28]);
      expect(none.needed, 0);
      expect(evaluateGrade('M25', const []).needed, 0);
    });

    test('an unknown grade is refused', () {
      expect(() => evaluateGrade('steel', [30]), throwsArgumentError);
    });
  });
}
