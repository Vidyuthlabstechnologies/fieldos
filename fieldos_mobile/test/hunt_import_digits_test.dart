/// Lists pasted or typed on an Arabic or Urdu keyboard (the UAE app), and a
/// tool code typed by hand: none of these may crash the screen or turn a
/// phone number into money.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/supplier_import.dart';
import 'package:fieldos_mobile/features/warehouse/tools_rules.dart';
import 'package:fieldos_mobile/features/workers/worker_tools.dart';

void main() {
  test('a worker list in Arabic-Indic digits keeps phone and wage apart, and does not crash', () {
    // "Imran, Mason, 0501234567, 150" with Arabic-Indic and Persian digits.
    final r = parseWorkerLines('Imran, Mason, ٠٥٠١٢٣٤٥٦٧, ١٥٠\nAsif, Helper, ۱۲۰');
    expect(r.map((w) => w.name), ['Imran', 'Asif']);
    expect(r[0].phone, '٠٥٠١٢٣٤٥٦٧');
    expect(r[0].dailyWage, 150);
    expect(r[1].dailyWage, 120);
    expect(r[1].phone, isNull);
  });

  test('a supplier phone in Arabic-Indic digits is a phone, not an amount owed', () {
    final r = parseSupplierLines('Al Noor Cement, ٠٥٠١٢٣٤٥٦٧, ٢٥٠٠');
    expect(r.single.phone, '٠٥٠١٢٣٤٥٦٧');
    expect(r.single.openingBalance, 2500);
  });

  test('a hand-typed tool code too long for a number does not stop new codes', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final company = await db.companyDao.create('Sai Constructions');
    final dao = db.warehouseDao;
    final huge = await dao.addTool(companyId: company.id, name: 'Old drill', by: 'pm', code: 'T-99999999999999999999');
    final small = await dao.addTool(companyId: company.id, name: 'Level', by: 'pm', code: 'T-007');
    expect(nextToolCode([huge, small]), 'T-008');
  });
}
