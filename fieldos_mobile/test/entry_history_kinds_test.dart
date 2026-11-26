/// The change history now also keeps wage rates, attendance marks and
/// purchase orders and requests (20261127110000). They must read as what they
/// are, with the wage as money, never as a raw table name.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/entry_history.dart';

EntryHistoryData _row(String table, Map<String, Object?> before, Map<String, Object?>? after, {String op = 'update'}) =>
    EntryHistoryData(
      id: 'h1',
      projectId: 'p1',
      sourceTable: table,
      rowId: 'r1',
      op: op,
      oldJson: jsonEncode(before),
      newJson: after == null ? null : jsonEncode(after),
      changedBy: 'u1',
      changedAt: DateTime(2026, 11, 27),
    );

void main() {
  test('every table the server keeps history for has a readable kind', () {
    for (final t in ['workers', 'site_attendance_marks', 'purchase_orders', 'purchase_requisitions']) {
      expect(historyKinds[t], isNotNull, reason: '$t would show as a raw table name');
    }
    expect(HistoryItem(_row('workers', {'name': 'Raju'}, {'name': 'Raju'})).kind, 'Worker');
    expect(HistoryItem(_row('purchase_orders', {}, {})).kind, 'Purchase order');
  });

  test('a changed wage is shown as money, with the worker named', () {
    final item = HistoryItem(_row('workers', {'name': 'Raju', 'daily_wage': 700, 'role': 'Mason'},
        {'name': 'Raju', 'daily_wage': 900, 'role': 'Mason'}));
    expect(item.changes.map((c) => c.field), ['daily_wage']);
    expect(fieldLabel('daily_wage'), 'Daily wage');
    expect(moneyFields, contains('daily_wage'));
    expect(item.summary, 'Raju');
  });

  test('a changed order amount and a request cost are amounts', () {
    expect(fieldLabel('total_amount'), 'Amount');
    expect(fieldLabel('estimated_cost'), 'Amount');
    expect(moneyFields, containsAll(['total_amount', 'estimated_cost']));
    final item = HistoryItem(_row('purchase_requisitions', {'item_name': 'TMT 12mm', 'estimated_cost': 50000},
        {'item_name': 'TMT 12mm', 'estimated_cost': 9000}));
    expect(item.summary, 'TMT 12mm');
    expect(item.changes.single.field, 'estimated_cost');
  });

  test('a deleted worker keeps what the row held', () {
    final item = HistoryItem(_row('workers', {'name': 'Raju', 'daily_wage': 900}, null, op: 'delete'));
    expect(item.deleted, isTrue);
    expect(item.summary, 'Raju');
  });
}
