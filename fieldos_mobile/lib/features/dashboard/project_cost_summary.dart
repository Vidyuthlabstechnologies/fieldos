/// Per-project cost-health summary for the multi-site dashboard: budget (from
/// the reconciled BOQ), actual spend (expenses + material receipts + work-order
/// billing), variance/status (via [CostControlAgent]), plus open issues and DPR
/// counts. One object powers the whole dashboard card.
library;

import 'package:fieldos_mobile/agents/cost_control_agent.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/estimation/project_boq.dart';

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

    final report = await CostControlAgent().run({'budget': boq, 'actuals': actuals});
    final d = report.data;

    final issues = await db.issueDao.forProject(project.id);
    final open = issues.where((i) => i.status != 'resolved').length;
    final dprs = await db.dprDao.forProject(project.id);

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
    );
  }
}
