/// US customary units in the converter, rebar sizes, and quantities typed
/// in US units; India's units unchanged.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/estimation/estimation_screen.dart' show barSizeFromMm, barSizeToMm, lbPerKg;
import 'package:fieldos_mobile/features/procurement/material_check.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';

SiteUnit _u(String k) => unitGroups.expand((g) => g.units).firstWhere((x) => x.key == k);

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('India keeps its units, brass and guntha included', () {
    debugSetMarket(Market.india);
    expect(unitGroups.first.units.first.key, 'm');
    expect(_u('brass').label, 'Brass (100 cft)');
    expect(_u('guntha').key, 'guntha');
  });

  test('the US converter starts in feet, cubic yards and pounds', () {
    debugSetMarket(Market.us);
    final first = {for (final g in unitGroups) g.label: g.units.first.key};
    expect(first, {'Length': 'ft', 'Area': 'sqft', 'Volume': 'cuyd', 'Weight': 'lb'});
    expect(convertUnits(1, _u('cuyd'), _u('cft')), closeTo(27, 1e-9));
    expect(convertUnits(1, _u('ton'), _u('lb')), closeTo(2000, 1e-6));
    expect(convertUnits(1, _u('square'), _u('sqft')), closeTo(100, 1e-9));
    expect(convertUnits(1, _u('bag'), _u('lb')), closeTo(94, 1e-6));
    expect(unitGroups.expand((g) => g.units).map((u) => u.key), isNot(contains('brass')));
  });

  test('other metric markets drop the Indian land and sand units', () {
    for (final m in [Market.malaysia, Market.uae, Market.uk]) {
      debugSetMarket(m);
      final keys = unitGroups.expand((g) => g.units).map((u) => u.key).toSet();
      expect(keys.intersection({'brass', 'guntha', 'quintal', 'rft'}), isEmpty, reason: m.name);
      expect(unitGroups.first.units.first.key, 'm');
    }
  });

  test('rebar: bar sizes, weights match d x d / 162', () {
    expect(barSizeToMm(4), closeTo(12.7, 1e-9));
    for (final n in [3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 18]) {
      expect(barSizeFromMm(barSizeToMm(n)), n);
    }
    // #4 by the metric rule, in lb per foot, against the ASTM table.
    final lbPerFt = steelKgPerMetre(barSizeToMm(4)) * lbPerKg * 0.3048;
    expect(lbPerFt, closeTo(rebarLbPerFoot[4]!, 0.005));
    for (final e in rebarLbPerFoot.entries) {
      final calc = steelKgPerMetre(barSizeToMm(e.key)) * lbPerKg * 0.3048;
      expect(calc, closeTo(e.value, e.value * 0.01), reason: '#${e.key}');
    }
  });

  test('quantities typed in US units', () {
    debugSetMarket(Market.us);
    expect(baseQty(10, 'cu yd')!.qty, closeTo(7.64555, 1e-4));
    expect(baseQty(100, 'lbs')!.qty, closeTo(45.3592, 1e-3));
    expect(baseQty(1, 'ton')!.qty, closeTo(907.185, 1e-3));
    expect(baseQty(1, 'tonne')!.qty, 1000);
    debugSetMarket(Market.india);
    expect(baseQty(1, 'ton')!.qty, 1000);
  });
}
