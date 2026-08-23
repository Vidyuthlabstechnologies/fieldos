import 'package:fieldos_mobile/data/app_database.dart';
import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('inspection create, checklist items with auto sortOrder, complete', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));

    final inspection = await db.inspectionDao.create(InspectionsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      title: 'Slab inspection',
      inspectionType: 'structural',
    ));
    expect(inspection.status, 'open');
    expect((await db.inspectionDao.forProject(project.id)).length, 1);

    final item1 = await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
      id: _uuid.v4(),
      inspectionId: inspection.id,
      itemDescription: 'Reinforcement placement',
    ));
    final item2 = await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
      id: _uuid.v4(),
      inspectionId: inspection.id,
      itemDescription: 'Cover blocks',
    ));
    // sortOrder auto-increments starting at 0 for the first item added.
    expect(item1.sortOrder, 0);
    expect(item2.sortOrder, 1);

    final items = await db.inspectionDao.itemsFor(inspection.id);
    expect(items.length, 2);
    expect(items.first.id, item1.id); // ordered by sortOrder asc

    await db.inspectionDao.updateItemStatus(item1.id, 'pass');
    await db.inspectionDao.updateItemStatus(item2.id, 'fail', notes: 'Spacing off by 20mm');
    final updatedItems = await db.inspectionDao.itemsFor(inspection.id);
    expect(updatedItems.firstWhere((i) => i.id == item1.id).status, 'pass');
    final failed = updatedItems.firstWhere((i) => i.id == item2.id);
    expect(failed.status, 'fail');
    expect(failed.notes, 'Spacing off by 20mm');

    await db.inspectionDao.complete(inspection.id, 'partial');
    final completed = (await db.inspectionDao.forProject(project.id)).first;
    expect(completed.status, 'completed');
    expect(completed.overallResult, 'partial');
    expect(completed.completedDate, isNotNull);
  });
}
