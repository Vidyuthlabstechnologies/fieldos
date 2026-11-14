/// EPF, SOCSO and EIS on the wage sheet, in the Malaysia app: for each
/// worker, what is cut from their wages, what the employer pays on top,
/// and the net pay. Every other market gets nothing here.
///
/// Kept beside wage_sheet.dart, not in it: it only reads a built sheet.
library;

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/features/payroll/malaysia_contributions.dart';

/// Whether the wage sheet shows statutory contributions.
bool get wageSheetContributionsShown => currentMarket == Market.malaysia;

/// Workers on a foreign worker's permit: a PLKS (Pas Lawatan Kerja
/// Sementara) is only ever issued to non-citizens, so a worker with one on
/// file is foreign. A passport alone is not taken as proof either way.
Set<String> foreignWorkerIds(Iterable<WorkerPermit> permits) => {
      for (final p in permits)
        if (p.kind == 'plks') p.workerId,
    };

class WageContribution {
  const WageContribution({required this.earned, required this.contributions, required this.foreign});

  final double earned;
  final MalaysiaContributions contributions;
  final bool foreign;

  /// The wages less the worker's own EPF, SOCSO and EIS.
  double get netPay => ((earned - contributions.employeeTotal) * 100).roundToDouble() / 100;
}

/// Each line's contributions, by [WageLine.key], on what it earned in the
/// sheet's period: for daily-rated workers the period's wages stand for
/// the month's. Lines that earned nothing are left out; outside Malaysia
/// the map is empty.
Map<String, WageContribution> wageContributions(WageSheet sheet, {Set<String> foreign = const {}}) {
  if (!wageSheetContributionsShown) return const {};
  final out = <String, WageContribution>{};
  for (final l in sheet.lines) {
    if (l.earned <= 0) continue;
    final isForeign = l.workerId != null && foreign.contains(l.workerId);
    out[l.key] = WageContribution(
      earned: l.earned,
      contributions: malaysiaContributions(l.earned, foreign: isForeign),
      foreign: isForeign,
    );
  }
  return out;
}

/// The sheet's totals: what the workers pay and what the employer pays.
({double employee, double employer}) contributionTotals(Map<String, WageContribution> byLine) {
  var ee = 0, er = 0;
  for (final c in byLine.values) {
    ee += (c.contributions.employeeTotal * 100).round();
    er += (c.contributions.employerTotal * 100).round();
  }
  return (employee: ee / 100, employer: er / 100);
}
