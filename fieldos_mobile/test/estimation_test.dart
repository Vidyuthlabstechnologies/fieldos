import 'package:decimal/decimal.dart';
import 'package:fieldos_mobile/estimation/estimation_calc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Golden figures verified against the Protek Consult BOQ spreadsheets that the
  // desktop importers reconcile against (importers/narapally_boq.py,
  // importers/thumukunta_boq.py). The Dart engine must reproduce the sheet's
  // own stated totals exactly.
  group('estimation engine matches sheets', () {
    test('Narapally masonry wall 9" = 718.509375 CFT', () {
      final q = measurementEntryQuantity(
        calcVolume,
        length: Decimal.parse('108.25'),
        width: Decimal.parse('0.75'),
        depth: Decimal.parse('8.85'),
        nos: Decimal.parse('1'),
      );
      expect(q, Decimal.parse('718.509375'));
    });

    test('Narapally deduction D1 = -18.375 CFT', () {
      final q = measurementEntryQuantity(
        calcVolume,
        length: Decimal.parse('3.5'),
        width: Decimal.parse('0.75'),
        depth: Decimal.parse('7'),
        nos: Decimal.parse('1'),
        isDeduction: true,
      );
      expect(q, Decimal.parse('-18.375'));
    });

    test('Thumukunta footing = 1220.57 CFT', () {
      final q = measurementEntryQuantity(
        calcVolume,
        length: Decimal.parse('10.66'),
        width: Decimal.parse('9.16'),
        depth: Decimal.parse('6.25'),
        nos: Decimal.parse('2'),
      );
      expect(q, Decimal.parse('1220.57'));
    });

    test('cost head rolls measurements up with deductions', () {
      final ch = CalcCostHead(
        id: 'ch',
        name: 'Masonry',
        calculationType: calcVolume,
        billingUnit: 'cft',
        conversionFactor: Decimal.parse('1'),
      );
      final raw = costHeadRawQuantity(
        ch,
        measurements: [
          CalcMeasurement(
            length: Decimal.parse('108.25'),
            width: Decimal.parse('0.75'),
            depth: Decimal.parse('8.85'),
            nos: Decimal.parse('1'),
          ),
          CalcMeasurement(
            length: Decimal.parse('3.5'),
            width: Decimal.parse('0.75'),
            depth: Decimal.parse('7'),
            nos: Decimal.parse('1'),
            isDeduction: true,
          ),
        ],
      );
      expect(raw, Decimal.parse('700.134375')); // 718.509375 - 18.375
    });
  });
}
