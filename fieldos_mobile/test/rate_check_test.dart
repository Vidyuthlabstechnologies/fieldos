import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart';
import 'package:fieldos_mobile/features/procurement/rate_hint.dart';

/// Rate intelligence: a quote or bill is checked against what the company
/// itself paid on recent deliveries, before the order goes out.
void main() {
  final now = DateTime(2026, 11, 9);
  MaterialReceipt r(String id, String name, double qty, double amount, DateTime on, {String unit = 'bags', String? sup}) =>
      MaterialReceipt(
        id: id,
        projectId: 'p',
        materialName: name,
        quantity: qty,
        unit: unit,
        amount: amount,
        receivedBy: 'u',
        receivedOn: on,
        supplierId: sup,
        createdAt: on,
      );

  final history = [
    r('1', 'Cement', 50, 19000, DateTime(2026, 9, 1), sup: 'balaji'), // 380
    r('2', 'cement ', 40, 15600, DateTime(2026, 10, 1), sup: 'sai'), // 390
    r('3', 'Cement', 20, 8000, DateTime(2026, 10, 20), sup: 'sai'), // 400
    r('4', 'Cement', 10, 3900, DateTime(2026, 11, 1), sup: 'sai'), // 390
    r('5', 'Cement', 1, 999, DateTime(2026, 11, 2), unit: 'tonne'), // other unit
    r('6', 'Sand', 2, 9000, DateTime(2026, 11, 2), unit: 'brass'),
  ];

  test('a high quote is flagged with the extra it costs and the cheapest recent supplier', () {
    final c = checkRate(material: 'CEMENT', unit: 'Bags', qty: 40, amount: 16800, history: history, now: now)!;
    expect(c.rate, 420);
    expect(c.usual, 390); // median of 380, 390, 390, 400
    expect(c.deliveries, 4);
    expect(c.high, isTrue);
    expect(c.diffPct.round(), 8);
    expect(c.extraOn(40), 1200);
    expect(c.best!.supplierId, 'balaji');
    expect(rateCheckLine(c, unit: 'bags', qty: 40), '8% above your usual ₹390 per bags: ₹1,200 extra on this order');
  });

  test('normal and good prices say so', () {
    final ok = checkRate(material: 'Cement', unit: 'bags', qty: 10, amount: 3950, history: history, now: now)!;
    expect(ok.high || ok.low, isFalse);
    expect(rateCheckLine(ok, unit: 'bags'), 'In line with your usual ₹390 per bags');
    final low = checkRate(material: 'Cement', unit: 'bags', qty: 10, amount: 3500, history: history, now: now)!;
    expect(low.low, isTrue);
    expect(rateCheckLine(low, unit: 'bags'), '10% below your usual ₹390 per bags. A good price.');
  });

  test('nothing to say without a quantity, an amount or two earlier deliveries', () {
    expect(checkRate(material: 'Cement', unit: 'bags', qty: null, amount: 100, history: history), isNull);
    expect(checkRate(material: 'Cement', unit: 'bags', qty: 10, amount: 0, history: history), isNull);
    expect(checkRate(material: 'Sand', unit: 'brass', qty: 1, amount: 5000, history: history), isNull);
    expect(checkRate(material: 'Steel', unit: 'kg', qty: 1, amount: 70, history: history), isNull);
  });

  test('old deliveries give way to the last six months when there are enough', () {
    final h = [
      r('a', 'Steel', 100, 5000, DateTime(2025, 1, 1), unit: 'kg'), // 50, too old
      r('b', 'Steel', 100, 7000, DateTime(2026, 9, 1), unit: 'kg'),
      r('c', 'Steel', 100, 7200, DateTime(2026, 10, 1), unit: 'kg'),
    ];
    expect(checkRate(material: 'Steel', unit: 'kg', qty: 1, amount: 71, history: h, now: now)!.usual, 71);
  });
}
