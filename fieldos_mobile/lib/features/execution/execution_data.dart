/// Loading site execution records for the screens.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/execution/execution_rules.dart';
import 'package:fieldos_mobile/providers.dart';

Future<ExecutionData> loadExecutionData(AppDatabase db, String projectId) async {
  final x = db.siteExecutionDao;
  return ExecutionData(
    projectId: projectId,
    tasks: await db.taskDao.forProject(projectId),
    constraints: await x.constraintsFor(projectId),
    drawings: await x.drawingsFor(projectId),
    revisions: await x.revisionsFor(projectId),
    rfis: await x.rfisFor(projectId),
    holdPoints: await x.holdPointsFor(projectId),
    defects: await x.defectsFor(projectId),
    photos: await x.photosFor(projectId),
    units: await x.unitsFor(projectId),
    checks: await x.checksFor(projectId),
  );
}

final executionDataProvider = FutureProvider.autoDispose.family<ExecutionData, String>(
    (ref, projectId) => loadExecutionData(ref.watch(appDatabaseProvider), projectId));

/// Every site of the company with its execution summary, for the
/// portfolio report.
final portfolioExecutionProvider =
    FutureProvider.autoDispose.family<List<(Project, ExecutionData)>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  return [
    for (final p in await db.projectDao.forCompany(companyId)) (p, await loadExecutionData(db, p.id)),
  ];
});

final companyStandardsProvider = FutureProvider.autoDispose.family<List<CompanyStandard>, String>(
    (ref, companyId) => ref.watch(appDatabaseProvider).siteExecutionDao.standardsFor(companyId));
