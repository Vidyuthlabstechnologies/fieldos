import 'package:fieldos_mobile/data/app_database.dart';
import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('worker directory create/forProject/setStatus', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));

    final worker = await db.workerDao.create(WorkersCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'Ramesh',
      role: const Value('mason'),
      dailyWage: const Value(800),
    ));
    expect(worker.status, 'active');

    final list = await db.workerDao.forProject(project.id);
    expect(list.length, 1);
    expect(list.first.name, 'Ramesh');

    await db.workerDao.setStatus(worker.id, 'inactive');
    final updated = await db.workerDao.forProject(project.id);
    expect(updated.first.status, 'inactive');
  });

  test('LabourAttendance accepts punch-ins with and without a workerId', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));
    final worker = await db.workerDao.create(WorkersCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'Suresh',
    ));

    // Directory-linked punch-in.
    await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      workerName: worker.name,
      recordedBy: 'u1',
      punchIn: DateTime(2026, 1, 1, 8),
      workerId: Value(worker.id),
    ));

    // Free-text punch-in, exactly as the pre-existing flow works today —
    // workerId simply absent, backward compatible.
    await db.attendanceDao.punchIn(LabourAttendanceCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      workerName: 'Casual Labourer',
      recordedBy: 'u1',
      punchIn: DateTime(2026, 1, 1, 8, 30),
    ));

    final rows = await db.attendanceDao.forProject(project.id);
    expect(rows.length, 2);
    final linked = rows.firstWhere((r) => r.workerName == 'Suresh');
    final freeText = rows.firstWhere((r) => r.workerName == 'Casual Labourer');
    expect(linked.workerId, worker.id);
    expect(freeText.workerId, isNull);
  });
}
