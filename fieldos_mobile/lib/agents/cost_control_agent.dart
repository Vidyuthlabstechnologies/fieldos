/// Cost-control agent: reconciles the priced BOQ (budget) against actual site
/// spend in real time and flags overruns.
///
/// This is the feature Onsite/civils.ai dashboards only *display* passively.
/// FieldOS makes it an agent: it maps every actual (expense, material receipt,
/// work-order billing) onto a BOQ cost head, computes variance, and raises
/// alerts the moment a line tips into "at risk" (>=90% of budget) or "over"
/// (exceeds budget). Outputs are Decimal-accurate before being rounded for the
/// UI/report.
library;

import 'package:decimal/decimal.dart';

import 'agent.dart';
import '../estimation/estimation_calc.dart';

class _LineReport {
  const _LineReport({
    required this.costHeadId,
    required this.name,
    required this.budget,
    required this.actual,
  });
  final String costHeadId;
  final String name;
  final Decimal budget;
  final Decimal actual;

  Decimal get variance => budget - actual;

  String get status {
    if (budget <= Decimal.zero) return 'over';
    final ratio = (actual / budget).toDecimal(scaleOnInfinitePrecision: 28);
    if (ratio > Decimal.one) return 'over';
    if (ratio >= Decimal.parse('0.9')) return 'at_risk';
    return 'ok';
  }
}

class CostControlAgent implements Agent {
  const CostControlAgent();

  @override
  String get name => 'cost_control';

  @override
  String get description =>
      'Reconciles the priced BOQ budget against actual site spend and flags cost overruns.';

  @override
  List<AgentTool> get tools => const [
        AgentTool(name: 'reconcile', description: 'Budget vs actuals per BOQ cost head.'),
      ];

  @override
  Future<AgentResult> run(Map<String, dynamic> input) async {
    final budget = input['budget'] as BOQResult;
    final actualsRaw = (input['actuals'] as List?) ?? const [];
    final threshold = Decimal.parse((input['overrun_threshold'] as num? ?? 0.9).toString());
    final includeUnallocated = (input['include_unallocated'] as bool?) ?? true;

    final actualsByHead = <String, Decimal>{};
    var unallocated = Decimal.zero;
    for (final a in actualsRaw) {
      final costHeadId = a['costHeadId'] as String?;
      final amount = Decimal.parse((a['amount'] as num).toString());
      if (costHeadId == null || costHeadId.isEmpty) {
        unallocated += amount;
      } else {
        actualsByHead[costHeadId] = (actualsByHead[costHeadId] ?? Decimal.zero) + amount;
      }
    }

    final lines = <_LineReport>[];
    for (final line in budget.lines) {
      final budgetAmount = line.amount ?? Decimal.zero;
      lines.add(_LineReport(
        costHeadId: line.costHeadId,
        name: line.name,
        budget: budgetAmount,
        actual: actualsByHead[line.costHeadId] ?? Decimal.zero,
      ));
    }

    final projectBudget = budget.grandTotal;
    final projectActual =
        lines.fold<Decimal>(Decimal.zero, (s, l) => s + l.actual) + unallocated;
    final projectVariance = projectBudget - projectActual;
    final projectStatus = (() {
      if (projectBudget <= Decimal.zero) return 'over';
      final ratio =
          (projectActual / projectBudget).toDecimal(scaleOnInfinitePrecision: 28);
      if (ratio > Decimal.one) return 'over';
      if (ratio >= threshold) return 'at_risk';
      return 'ok';
    })();

    final alerts = <String>[];
    for (final l in lines) {
      if (l.status == 'over') {
        alerts.add('Over budget on "${l.name}": spent ${_fmt(l.actual)} of ${_fmt(l.budget)}.');
      } else if (l.status == 'at_risk') {
        alerts.add('Approaching budget on "${l.name}": ${_fmt(l.actual)} of ${_fmt(l.budget)} (${_pct(l.actual, l.budget)}%).');
      }
    }
    if (includeUnallocated && unallocated > Decimal.zero) {
      alerts.add('Unallocated spend not mapped to a BOQ line: ${_fmt(unallocated)}.');
    }

    return AgentResult(
      ok: true,
      message: 'Reconciled ${lines.length} cost heads; project status: $projectStatus.',
      data: {
        'project_budget': projectBudget.toDouble(),
        'project_actual': projectActual.toDouble(),
        'project_variance': projectVariance.toDouble(),
        'project_status': projectStatus,
        'unallocated_actual': unallocated.toDouble(),
        'lines': [
          for (final l in lines)
            {
              'cost_head_id': l.costHeadId,
              'name': l.name,
              'budget': l.budget.toDouble(),
              'actual': l.actual.toDouble(),
              'variance': l.variance.toDouble(),
              'status': l.status,
            }
        ],
        'alerts': alerts,
      },
    );
  }
}

String _fmt(Decimal d) => d.toStringAsFixed(2);
String _pct(Decimal actual, Decimal budget) {
  if (budget <= Decimal.zero) return '100';
  final ratio = (actual / budget).toDecimal(scaleOnInfinitePrecision: 28);
  return (ratio * Decimal.fromInt(100)).toStringAsFixed(0);
}
