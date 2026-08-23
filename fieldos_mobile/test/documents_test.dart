import 'package:fieldos_mobile/data/app_database.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('document create and same-name versioning', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'P',
      status: const Value('planning'),
    ));

    final first = await db.documentDao.create(DocumentsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'Site Plan',
      category: const Value('drawing'),
      filePath: '/media/documents/a.pdf',
      uploadedBy: 'u1',
    ));
    expect(first.version, 1);

    // A second document with the SAME name for the SAME project must bump
    // the version to 2, mirroring the desktop backend's versioning rule.
    final second = await db.documentDao.create(DocumentsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'Site Plan',
      category: const Value('drawing'),
      filePath: '/media/documents/b.pdf',
      uploadedBy: 'u1',
    ));
    expect(second.version, 2);

    // A different name starts fresh at version 1.
    final other = await db.documentDao.create(DocumentsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'Safety Permit',
      category: const Value('permit'),
      filePath: '/media/documents/c.pdf',
      uploadedBy: 'u1',
    ));
    expect(other.version, 1);

    final all = await db.documentDao.forProject(project.id);
    expect(all.length, 3);

    final versions = await db.documentDao.versionsOf(project.id, 'Site Plan');
    expect(versions.length, 2);
    expect(versions.first.version, 2); // ordered by version desc
    expect(versions.last.version, 1);
  });
}
