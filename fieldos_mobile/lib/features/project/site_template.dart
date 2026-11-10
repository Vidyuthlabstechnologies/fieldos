/// A new site from an existing one: the same task list, workers, estimate
/// rates, site team and geofence size, so a company opening its tenth site
/// doesn't type it all again. Nothing that happened on the old site comes
/// across: no reports, attendance, money, material or progress.
library;

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';

class SiteTemplateParts {
  const SiteTemplateParts({
    this.tasks = true,
    this.workers = true,
    this.estimate = true,
    this.team = true,
    this.geofence = true,
  });
  final bool tasks;
  final bool workers;
  final bool estimate;
  final bool team;
  final bool geofence;
}

class SiteTemplateResult {
  const SiteTemplateResult(this.project, {this.tasks = 0, this.workers = 0, this.costHeads = 0, this.team = 0});
  final Project project;
  final int tasks;
  final int workers;
  final int costHeads;
  final int team;
}

/// Creates [name] from [source]. Everything is written in one transaction
/// and queued for sync, so a failure leaves no half-made site.
/// [createdBy]: the person making it (the estimate's author).
Future<SiteTemplateResult> newSiteFromTemplate(
  AppDatabase db, {
  required Project source,
  required String name,
  String? clientName,
  String status = 'planning',
  required String createdBy,
  SiteTemplateParts copy = const SiteTemplateParts(),
}) {
  const uuid = Uuid();
  final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (clean.isEmpty) throw ArgumentError('Give the new site a name.');
  return db.transaction(() async {
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: uuid.v4(),
      companyId: source.companyId,
      name: clean,
      clientName: Value(clientName?.trim().isEmpty ?? true ? null : clientName!.trim()),
      status: Value(status),
    ));
    var tasks = 0, workers = 0, heads = 0, team = 0;

    if (copy.tasks) {
      for (final t in await db.taskDao.forProject(source.id)) {
        await db.taskDao.create(TasksCompanion.insert(
          id: uuid.v4(),
          projectId: project.id,
          title: t.title,
          priority: Value(t.priority),
        ));
        tasks++;
      }
    }

    if (copy.workers) {
      for (final w in await db.workerDao.forProject(source.id)) {
        if (w.status != 'active') continue;
        await db.workerDao.create(WorkersCompanion.insert(
          id: uuid.v4(),
          projectId: project.id,
          name: w.name,
          role: Value(w.role),
          phone: Value(w.phone),
          dailyWage: Value(w.dailyWage),
        ));
        workers++;
      }
    }

    if (copy.estimate) {
      for (final e in await db.estimationDao.forProject(source.id)) {
        final est = await db.estimationDao.create(EstimationsCompanion.insert(
          id: uuid.v4(),
          projectId: project.id,
          name: e.name,
          contractorProfitPercent: Value(e.contractorProfitPercent),
          createdBy: createdBy,
        ));
        for (final h in await db.estimationDao.costHeadsFor(e.id)) {
          await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
            id: uuid.v4(),
            estimationId: est.id,
            name: h.name,
            calculationType: h.calculationType,
            rawUnit: h.rawUnit,
            billingUnit: h.billingUnit,
            conversionFactor: Value(h.conversionFactor),
            ratePerUnit: Value(h.ratePerUnit),
            sortOrder: Value(h.sortOrder),
          ));
          heads++;
        }
      }
    }

    if (copy.team) {
      for (final m in await db.siteTeamDao.membersFor(source.id)) {
        await db.siteTeamDao
            .setMember(projectId: project.id, userId: m.userId, role: m.role, approvalLimit: m.approvalLimit);
        team++;
      }
      if (await db.siteTeamDao.isMembersOnly(source.id)) await db.siteTeamDao.setMembersOnly(project.id, true);
    }

    var made = project;
    // The radius only: the new site is somewhere else.
    if (copy.geofence && source.geofenceRadiusM != null) {
      await db.projectDao.setGeofenceRadius(project.id, source.geofenceRadiusM!);
      made = (await db.projectDao.byId(project.id))!;
    }
    return SiteTemplateResult(made, tasks: tasks, workers: workers, costHeads: heads, team: team);
  });
}
