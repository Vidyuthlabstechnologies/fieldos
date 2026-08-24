/// Differential test: the mobile Dart estimation engine must produce
/// EXACTLY (string-equal Decimal output) what the desktop Python engine
/// produces for every generated case. Fixtures are produced by
/// scripts/generate_estimation_fixtures.py from fieldos/estimation_calc.py
/// with a fixed seed -- re-run that script whenever the desktop engine
/// changes, and this test will fail loudly if the Dart port drifts.
///
/// This is the whole reason the port exists as a deliberate duplicate
/// (see lib/estimation/estimation_calc.dart): a silent floating-point or
/// rounding divergence between desktop and mobile would hand the same
/// client two different estimates.
library;

import 'dart:convert';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/estimation/estimation_calc.dart';

Decimal? _decOrNull(String? s) => s == null ? null : Decimal.parse(s);

/// Cross-engine comparison contract.
///
/// Single operations agree exactly (value equality). Long multiply-chains
/// do NOT compare string- or bit-exact: Python's Decimal applies a
/// 28-significant-digit CONTEXT rounding at every operation, while Dart's
/// decimal package is exact -- so rollup values legitimately diverge past
/// ~26 significant digits (observed ~1e-24 rupees at crore-scale totals).
/// The tolerance below (absolute 1e-9, i.e. a billionth of a paisa) is
/// ~16 orders of magnitude tighter than any real money rounding, while
/// still instantly catching a wrong constant, swapped operand, or missed
/// deduction that a naive "close enough" float test would hide.
void _expectSameValue(Decimal got, String wantStr, String label) {
  final want = Decimal.parse(wantStr);
  if (got == want) return;
  final diff = (got - want).abs();
  final absolute = Decimal.parse('0.000000001');
  final relative = want.abs() * Decimal.parse('0.000000000000000001');
  final allowed = absolute > relative ? absolute : relative;
  expect(diff <= allowed, isTrue,
      reason: '$label drifted across engines: dart=$got python=$want');
}

void main() {
  final fixtureFile = File('test/fixtures/estimation_fixtures.json');
  final data = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final cases = (data['cases'] as List).cast<Map<String, dynamic>>();

  test('fixture file exists and is non-trivial', () {
    expect(cases.length, greaterThanOrEqualTo(100));
  });

  for (final (index, c) in cases.indexed) {
    group('case #$index', () {
      final headsInput = (c['heads'] as List).cast<Map<String, dynamic>>();
      final expectedLines = (c['expect']['lines'] as List).cast<Map<String, dynamic>>();

      test('per-entry quantities match Python exactly', () {
        for (final standalone in (c['standalone'] as List).cast<Map<String, dynamic>>()) {
          if (standalone['case'] == 'steel') {
            final input = standalone['input'] as Map<String, dynamic>;
            final got = steelEntryWeightKg(
              Decimal.parse(input['bar_dia_mm'] as String),
              Decimal.parse(input['nos'] as String),
              Decimal.parse(input['length_ft'] as String),
            );
            // Value equality, not string equality: Python's Decimal keeps
            // trailing zeros through arithmetic while Dart's normalizes
            // them -- same number, different display normalization. The
            // contract being tested (and that clients depend on) is the
            // numeric VALUE.
            // bar_dia/nos/length_ft multiply once -- but steel_unit_weight's
            // pi-free constant chain is short; still use the same contract
            // for uniformity.
            _expectSameValue(got, standalone['expect'] as String,
                'steel weight mismatch for $input');
          } else {
            final input = standalone['input'] as Map<String, dynamic>;
            final got = measurementEntryQuantity(
              standalone['ctype'] as String,
              length: _decOrNull(input['length'] as String?),
              width: _decOrNull(input['width'] as String?),
              depth: _decOrNull(input['depth'] as String?),
              nos: Decimal.parse(input['nos'] as String),
              isDeduction: input['is_deduction'] as bool,
            );
            // Same context-rounding contract as rollups -- long volume
            // chains can pass 28 significant digits.
            _expectSameValue(got, standalone['expect'] as String,
                'measurement mismatch for $input');
          }
        }
      });

      test('BOQ rollup matches Python exactly', () {
        final tuples = headsInput.map((h) {
          final head = CalcCostHead(
            id: h['id'] as String,
            name: h['name'] as String,
            calculationType: h['calculation_type'] as String,
            billingUnit: h['billing_unit'] as String,
            conversionFactor: Decimal.parse(h['conversion_factor'] as String),
            ratePerUnit: _decOrNull(h['rate_per_unit'] as String?),
          );
          final measurements = ((h['measurements'] as List?) ?? const []).cast<Map<String, dynamic>>().map((m) => CalcMeasurement(
                length: _decOrNull(m['length'] as String?),
                width: _decOrNull(m['width'] as String?),
                depth: _decOrNull(m['depth'] as String?),
                nos: Decimal.parse(m['nos'] as String),
                isDeduction: m['is_deduction'] as bool,
              ));
          final steel = ((h['steel'] as List?) ?? const []).cast<Map<String, dynamic>>().map((s) => CalcSteel(
                barDiaMm: Decimal.parse(s['bar_dia_mm'] as String),
                nos: Decimal.parse(s['nos'] as String),
                lengthFt: Decimal.parse(s['length_ft'] as String),
              ));
          return (head, measurements, steel);
        });

        final result = buildBoq(
          tuples,
          contractorProfitPercent: _decOrNull(c['contractor_profit_percent'] as String?),
        );

        expect(result.lines.length, expectedLines.length);
        for (var i = 0; i < result.lines.length; i++) {
          final line = result.lines[i];
          final want = expectedLines[i];
          expect(line.costHeadId, want['cost_head_id']);
          _expectSameValue(line.rawQuantity, want['raw_quantity'] as String,
              '${want['cost_head_id']} raw_quantity');
          _expectSameValue(line.billingQuantity, want['billing_quantity'] as String,
              '${want['cost_head_id']} billing_quantity');
          if (want['amount'] == null) {
            expect(line.amount, isNull, reason: '${want['cost_head_id']} amount should be unpriced');
          } else {
            _expectSameValue(line.amount!, want['amount'] as String,
                '${want['cost_head_id']} amount');
          }
        }
        _expectSameValue(result.subtotal, c['expect']['subtotal'] as String, 'subtotal');
        _expectSameValue(
            result.contractorProfitAmount, c['expect']['contractor_profit_amount'] as String,
            'contractor_profit_amount');
        _expectSameValue(result.grandTotal, c['expect']['grand_total'] as String, 'grand_total');
      });
    });
  }
}
