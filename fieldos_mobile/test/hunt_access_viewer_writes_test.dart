/// Hunt (access): a viewer "can see the site, changes nothing" (site_roles).
/// The screens hide the buttons, but the assistant on Home is open to
/// everyone and saves through the DAOs: it must refuse a viewer's changes
/// too, before the confirm card, and still answer their questions.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/auth/site_roles.dart';
import 'package:fieldos_mobile/data/app_database.dart';

void main() {
  late AppDatabase db;
  final now = DateTime(2026, 11, 9, 10, 30);

  AssistantTools as(String role, {String userId = 'u9'}) =>
      AssistantTools(db: db, companyId: 'c1', userId: userId, role: role, clock: () => now);

  setUp(() async {
    db = AppDatabase.memory();
    await db.projectDao.create(ProjectsCompanion.insert(id: 'p1', companyId: 'c1', name: 'Villa', status: const Value('active')));
  });
  tearDown(() => db.close());

  test('a company viewer cannot add an expense through the assistant', () async {
    final out = await as('viewer').run('add_expense', {'project_id': 'p1', 'amount': 4500, 'category': 'material'});
    expect(out.isError, isTrue);
    expect(await db.expenseDao.forProject('p1'), isEmpty);
  });

  test('a company viewer cannot open a new site or report an issue', () async {
    final v = as('viewer');
    expect((await v.run('create_project', {'name': 'Tower C'})).isError, isTrue);
    expect((await v.run('report_issue', {'project_id': 'p1', 'description': 'Crack'})).isError, isTrue);
    expect(await db.projectDao.forCompany('c1'), hasLength(1));
    expect(await db.issueDao.forProject('p1'), isEmpty);
  });

  test('no confirm card is offered to a viewer', () async {
    expect(() => as('viewer').describe('add_expense', {'project_id': 'p1', 'amount': 10, 'category': 'material'}),
        throwsA(isA<ToolInputError>()));
  });

  test("a viewer on this site's team cannot write here", () async {
    await db.siteTeamDao.setMember(projectId: 'p1', userId: 'u9', role: SiteRole.viewer);
    final out = await as('member').run('add_expense', {'project_id': 'p1', 'amount': 4500, 'category': 'material'});
    expect(out.isError, isTrue);
    expect(await db.expenseDao.forProject('p1'), isEmpty);
  });

  test('a viewer still reads, and a member still writes', () async {
    expect((await as('viewer').run('list_projects', const {})).isError, isFalse);
    final out = await as('member').run('add_expense', {'project_id': 'p1', 'amount': 4500, 'category': 'material'});
    expect(out.isError, isFalse, reason: out.result);
    expect(await db.expenseDao.forProject('p1'), hasLength(1));
  });
}
