import 'package:drift/drift.dart' show Value;
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('subcontractor create + forCompany', () async {
    final db = AppDatabase.memory();
    await db.subcontractorDao.create(SubcontractorsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'Steel Fab Co',
      contactPhone: const Value('123'),
      trade: const Value('Structural steel'),
    ));
    final rows = await db.subcontractorDao.forCompany('c1');
    expect(rows.length, 1);
    expect(rows.first.name, 'Steel Fab Co');
    expect(rows.first.trade, 'Structural steel');
  });
}
