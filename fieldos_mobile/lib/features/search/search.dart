/// Search across the company: projects, tasks, issues, workers, daily
/// reports and suppliers, by any word in their name or text. Plain SQL
/// LIKE on the phone's own database, so it works offline.
library;

import 'package:drift/drift.dart';

import 'package:fieldos_mobile/data/app_database.dart';

enum SearchKind { project, task, issue, worker, report, supplier }

class SearchHit {
  const SearchHit({required this.kind, required this.title, required this.projectId, this.projectName, this.detail});
  final SearchKind kind;
  final String title;
  final String? projectId;
  final String? projectName;
  final String? detail;
}

/// LIKE pattern for [query], with %, _ and \ taken literally.
String likePattern(String query) =>
    '%${query.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

/// Up to [limit] hits for [query] in [companyId], projects first.
Future<List<SearchHit>> searchCompany(AppDatabase db, String companyId, String query, {int limit = 60}) async {
  if (query.trim().length < 2) return const [];
  final like = likePattern(query);
  const esc = r"ESCAPE '\'";
  final rows = await db
      .customSelect(
        '''
    SELECT 0 AS k, p.name AS title, p.id AS pid, p.name AS pname, p.client_name AS detail
      FROM projects p WHERE p.company_id = ?1 AND (p.name LIKE ?2 $esc OR p.client_name LIKE ?2 $esc)
    UNION ALL
    SELECT 1, t.title, p.id, p.name, t.status
      FROM tasks t JOIN projects p ON p.id = t.project_id WHERE p.company_id = ?1 AND t.title LIKE ?2 $esc
    UNION ALL
    SELECT 2, i.description, p.id, p.name, i.status
      FROM issues i JOIN projects p ON p.id = i.project_id WHERE p.company_id = ?1 AND i.description LIKE ?2 $esc
    UNION ALL
    SELECT 3, w.name, p.id, p.name, w.role
      FROM workers w JOIN projects p ON p.id = w.project_id
      WHERE p.company_id = ?1 AND (w.name LIKE ?2 $esc OR w.role LIKE ?2 $esc OR w.phone LIKE ?2 $esc)
    UNION ALL
    SELECT 4, d.work_summary, p.id, p.name, NULL
      FROM dpr_entries d JOIN projects p ON p.id = d.project_id
      WHERE p.company_id = ?1 AND d.work_summary LIKE ?2 $esc
    UNION ALL
    SELECT 5, s.name, NULL, NULL, s.contact_phone
      FROM suppliers s
      WHERE s.company_id = ?1 AND (s.name LIKE ?2 $esc OR s.contact_phone LIKE ?2 $esc OR s.contact_person LIKE ?2 $esc)
    ORDER BY 1
    LIMIT ?3
    ''',
        variables: [Variable(companyId), Variable(like), Variable(limit)],
        readsFrom: {db.projects, db.tasks, db.issues, db.workers, db.dprEntries, db.suppliers},
      )
      .get();
  return [
    for (final r in rows)
      SearchHit(
        kind: SearchKind.values[r.read<int>('k')],
        title: r.read<String>('title'),
        projectId: r.readNullable<String>('pid'),
        projectName: r.readNullable<String>('pname'),
        detail: r.data['detail']?.toString(),
      ),
  ];
}
