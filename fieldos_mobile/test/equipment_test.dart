import 'package:fieldos_mobile/data/app_database.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('equipment create/forProject/updateStatus and log round-trip', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));

    final eq = await db.equipmentDao.create(EquipmentCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'JCB 01',
      equipmentType: const Value('excavator'),
      dailyRate: const Value(4500),
    ));
    expect(eq.status, 'available');

    final list = await db.equipmentDao.forProject(project.id);
    expect(list.length, 1);
    expect(list.first.name, 'JCB 01');

    await db.equipmentDao.updateStatus(eq.id, 'in_use');
    final updated = await db.equipmentDao.forProject(project.id);
    expect(updated.first.status, 'in_use');

    final log = await db.equipmentDao.addLog(EquipmentLogsCompanion.insert(
      id: _uuid.v4(),
      equipmentId: eq.id,
      logDate: DateTime(2026, 1, 1),
      logType: 'fuel',
      hoursUsed: const Value(6.5),
      cost: const Value(1200),
      createdBy: 'u1',
    ));
    expect(log.logType, 'fuel');

    final logs = await db.equipmentDao.logsFor(eq.id);
    expect(logs.length, 1);
    expect(logs.first.cost, 1200);
  });
}
