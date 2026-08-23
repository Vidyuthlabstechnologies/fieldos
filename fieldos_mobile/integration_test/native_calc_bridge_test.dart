/// Runs ON A REAL DEVICE/EMULATOR (not the pure-Dart VM `flutter test` runs
/// in) -- this is the only way to actually exercise the Chaquopy platform
/// channel and prove the on-device Python calc_bridge module really works,
/// not just that the Dart/Kotlin code compiles.
library;

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fieldos_mobile/estimation/native_calc_bridge.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('NativeCalcBridge (real on-device Python via Chaquopy)', () {
    testWidgets('volume measurement quantity, plain and deducted', (tester) async {
      final qty = await NativeCalcBridge.measurementEntryQuantity(
        calculationType: 'volume',
        length: Decimal.parse('10'),
        width: Decimal.parse('5'),
        depth: Decimal.parse('2'),
        nos: Decimal.parse('1'),
      );
      expect(qty, Decimal.parse('100'));

      final deducted = await NativeCalcBridge.measurementEntryQuantity(
        calculationType: 'volume',
        length: Decimal.parse('10'),
        width: Decimal.parse('5'),
        depth: Decimal.parse('2'),
        nos: Decimal.parse('1'),
        isDeduction: true,
      );
      expect(deducted, Decimal.parse('-100'));
    });

    testWidgets('area measurement quantity', (tester) async {
      final qty = await NativeCalcBridge.measurementEntryQuantity(
        calculationType: 'area',
        length: Decimal.parse('12'),
        width: Decimal.parse('8'),
        nos: Decimal.parse('2'),
      );
      expect(qty, Decimal.parse('192')); // 12*8*2
    });

    testWidgets('steel entry weight uses the exact IS 1786 formula, full precision preserved', (tester) async {
      // length_ft = 3.28 makes length_m = 3.28 * (1/3.28) = 1 exactly, isolating
      // the unit-weight division (16^2/162) as the only source of repeating
      // decimals -- a real stress test that the string-marshaled Decimal
      // round-trips across the platform channel without truncation.
      final weight = await NativeCalcBridge.steelEntryWeightKg(
        barDiaMm: Decimal.parse('16'),
        nos: Decimal.parse('1'),
        lengthFt: Decimal.parse('3.28'),
      );
      // 16*16/162 computed independently in Dart for comparison.
      final expected = (Decimal.parse('256') / Decimal.parse('162')).toDecimal(scaleOnInfinitePrecision: 20);
      expect((weight - expected).abs() < Decimal.parse('0.00000000000000000001'), isTrue,
          reason: 'got $weight, expected ~$expected');
    });

    testWidgets('billing quantity and amount, including the null-rate case', (tester) async {
      final billingQty = await NativeCalcBridge.costHeadBillingQuantity(
        rawQuantity: Decimal.parse('100'),
        conversionFactor: Decimal.parse('2'),
      );
      expect(billingQty, Decimal.parse('200'));

      final amount = await NativeCalcBridge.costHeadAmount(
        billingQuantity: Decimal.parse('200'),
        ratePerUnit: Decimal.parse('50'),
      );
      expect(amount, Decimal.parse('10000'));

      final unpriced = await NativeCalcBridge.costHeadAmount(
        billingQuantity: Decimal.parse('200'),
        ratePerUnit: null,
      );
      expect(unpriced, isNull);
    });
  });
}
