/// Reconstructs a priced [BOQResult] for a project from its stored estimation
/// rows. This is the bridge between the offline SQLite estimation tables and the
/// shared, golden-tested [buildBoq] engine, so the same Decimal-precise math
/// that reconciles the client's sheets also drives live budget-vs-actuals.
library;

import 'package:decimal/decimal.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/estimation/estimation_calc.dart';

Future<BOQResult> buildProjectBoq(EstimationDao dao, String projectId) async {
  final estimations = await dao.forProject(projectId);
  // Each estimation carries its own contractor profit, so each is priced on
  // its own and the results added up (audit 2026-11-14: one estimation's
  // percentage used to be put on every estimation's work).
  final parts = <BOQResult>[];

  for (final est in estimations) {
    final records = <(CalcCostHead, List<CalcMeasurement>, List<CalcSteel>)>[];
    final profitPercent =
        est.contractorProfitPercent == null ? null : Decimal.parse(est.contractorProfitPercent.toString());
    final heads = await dao.costHeadsFor(est.id);
    for (final h in heads) {
      final meas = await dao.measurements(h.id);
      final steel = await dao.steel(h.id);
      records.add((
        CalcCostHead(
          id: h.id,
          name: h.name,
          calculationType: h.calculationType,
          billingUnit: h.billingUnit,
          conversionFactor: Decimal.parse(h.conversionFactor.toString()),
          ratePerUnit: h.ratePerUnit == null ? null : Decimal.parse(h.ratePerUnit.toString()),
        ),
        meas
            .map((m) => CalcMeasurement(
                  length: m.length == null ? null : Decimal.parse(m.length.toString()),
                  width: m.width == null ? null : Decimal.parse(m.width.toString()),
                  depth: m.depth == null ? null : Decimal.parse(m.depth.toString()),
                  nos: Decimal.parse(m.nos.toString()),
                  isDeduction: m.isDeduction,
                ))
            .toList(),
        steel
            .map((s) => CalcSteel(
                  barDiaMm: Decimal.parse(s.barDiaMm.toString()),
                  nos: Decimal.parse(s.nos.toString()),
                  lengthFt: Decimal.parse(s.lengthFt.toString()),
                ))
            .toList(),
      ));
    }
    parts.add(buildBoq(records, contractorProfitPercent: profitPercent));
  }

  if (parts.length == 1) return parts.single;
  final percents = {for (final p in parts) p.contractorProfitPercent};
  var subtotal = Decimal.zero;
  var profit = Decimal.zero;
  for (final p in parts) {
    subtotal += p.subtotal;
    profit += p.contractorProfitAmount;
  }
  return BOQResult(
    lines: [for (final p in parts) ...p.lines],
    subtotal: subtotal,
    // One percentage only when every estimation has the same one.
    contractorProfitPercent: percents.length == 1 ? percents.single : null,
    contractorProfitAmount: profit,
    grandTotal: subtotal + profit,
  );
}
