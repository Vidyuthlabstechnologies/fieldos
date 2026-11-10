/// Per-project cost-health summary for the multi-site dashboard: budget (from
/// the reconciled BOQ), actual spend (expenses + material receipts + work-order
/// billing + material moved in from stores, less material sent on), variance/status (via [CostControlAgent]), plus open issues and DPR
/// counts. One object powers the whole dashboard card.
library;

import 'package:fieldos_mobile/agents/cost_control_agent.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/estimation/project_boq.dart';
import 'package:fieldos_mobile/features/project/task_plan.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart' show siteTransferValue;

/// Spent so far scaled up to the whole job by the share of work done.
double? forecastAtCompletion(double spent, int progressPct) {
  if (progressPct < 10 || spent <= 0) return null;
  if (progressPct >= 100) return spent;
  return spent * 100 / progressPct;
}

class ProjectCostSummary {
  const ProjectCostSummary({
    required this.projectId,
    required this.projectName,
    required this.budget,
    required this.actual,
    required this.variance,
    required this.status,
    required this.openIssues,
    required this.dprCount,
    required this.alerts,
    this.progress = 0,
  });

  final String projectId;
  final String projectName;
  final double budget;
  final double actual;
  final double variance;
  /// 'ok' | 'at_risk' | 'over' | 'no_budget' (no priced BOQ yet, so
  /// there is nothing to be over).
  final String status;
  final int openIssues;
  final int dprCount;
  final List<String> alerts;

  /// Work done, 0-100, from the tasks.
  final int progress;

  /// What the whole job will cost at the rate money is going out: spent so
  /// far divided by the share of work done. Null before 10% of the work
  /// (too early to tell) or with nothing spent.
  double? get forecast => forecastAtCompletion(actual, progress);

  /// Forecast less budget; positive means heading over.
  double? get forecastOver => forecast == null || budget <= 0 ? null : forecast! - budget;

  static Future<ProjectCostSummary> forProject(AppDatabase db, Project project) async {
    final boq = await buildProjectBoq(db.estimationDao, project.id);

    final expenses = await db.expenseDao.forProject(project.id);
    final receipts = await db.materialDao.forProject(project.id);
    final workOrders = await db.workOrderDao.workOrdersFor(project.id);

    final actuals = <Map<String, dynamic>>[];
    for (final e in expenses) {
      actuals.add({'costHeadId': e.costHeadId, 'amount': e.amount});
    }
    for (final r in receipts) {
      actuals.add({'costHeadId': r.costHeadId, 'amount': r.amount});
    }
    for (final w in workOrders) {
      actuals.add({'costHeadId': null, 'amount': w.billedAmount});
    }
    // Material from the company store (or another site) carries its value
    // here; material this site sent on is taken off.
    final moved = siteTransferValue(await db.warehouseDao.movesForSite(project.id), project.id);
    if (moved != 0) actuals.add({'costHeadId': null, 'amount': moved});

    final report = await CostControlAgent().run({'budget': boq, 'actuals': actuals});
    final d = report.data;

    final issues = await db.issueDao.forProject(project.id);
    final open = issues.where((i) => i.status != 'resolved').length;
    final dprs = await db.dprDao.forProject(project.id);
    final tasks = await db.taskDao.forProject(project.id);

    final budget = d['project_budget'] as double;
    final noBudget = budget <= 0;
    return ProjectCostSummary(
      projectId: project.id,
      projectName: project.name,
      budget: budget,
      actual: d['project_actual'] as double,
      variance: d['project_variance'] as double,
      status: noBudget ? 'no_budget' : d['project_status'] as String,
      openIssues: open,
      dprCount: dprs.length,
      alerts: noBudget ? const [] : List<String>.from(d['alerts'] as List),
      progress: projectProgress(tasks),
    );
  }
}
