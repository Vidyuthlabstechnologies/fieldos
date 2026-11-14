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

  // Audit 2026-11-14: a sortOrder given by the caller was overwritten with
  // 0, so a checklist built in a set order (a template) came out jumbled.
  test('a given sortOrder is kept', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final inspection = await db.inspectionDao.create(InspectionsCompanion.insert(
      id: _uuid.v4(),
      projectId: 'p1',
      title: 'Pre-pour check',
      inspectionType: 'quality',
    ));
    final last = await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
      id: _uuid.v4(),
      inspectionId: inspection.id,
      itemDescription: 'Curing arranged',
      sortOrder: const Value(5),
    ));
    final first = await db.inspectionDao.addItem(InspectionItemsCompanion.insert(
      id: _uuid.v4(),
      inspectionId: inspection.id,
      itemDescription: 'Shuttering level',
      sortOrder: const Value(1),
    ));
    expect(last.sortOrder, 5);
    expect(first.sortOrder, 1);
    expect([for (final i in await db.inspectionDao.itemsFor(inspection.id)) i.id], [first.id, last.id]);
  });
}
