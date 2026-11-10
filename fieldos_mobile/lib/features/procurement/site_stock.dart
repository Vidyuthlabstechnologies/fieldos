/// Material on site: received (GRNs) minus used, per material and unit.
/// Names are matched ignoring case and extra spaces, so "Cement " and
/// "cement" are one line; different units ("bags" vs "kg") stay separate
/// rather than being guessed at.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart' show siteMoveTotals;

enum StockStatus { ok, low, out, overused }

/// Below this share of everything received, a material is flagged low.
const lowStockShare = 0.15;

/// The note that marks a receipt as stock already on site when FieldOS
/// started being used (at no cost, so it never adds to the spending).
const openingStockNote = 'Opening stock';

bool isOpeningStock(MaterialReceipt r) => r.notes == openingStockNote && r.amount == 0 && r.poId == null;

class StockLine {
  StockLine(this.name, this.unit);
  final String name;
  final String? unit;
  double received = 0;
  double used = 0;

  /// Part of [received] that was opening stock.
  double opening = 0;

  /// Came from a store or another site, and sent away from here.
  double transferredIn = 0;
  double transferredOut = 0;
  double get balance => received + transferredIn - used - transferredOut;

  StockStatus get status {
    const eps = 1e-9;
    if (balance < -eps) return StockStatus.overused;
    if (balance.abs() <= eps) return StockStatus.out;
    final had = received + transferredIn;
    if (had > 0 && balance <= had * lowStockShare) return StockStatus.low;
    return StockStatus.ok;
  }
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// With [moves] and [projectId], transfers in (once counted at the site)
/// and out (once sent) count too.
List<StockLine> buildSiteStock(List<MaterialReceipt> receipts, List<MaterialUsageData> usage,
    {List<StockMove> moves = const [], String? projectId}) {
  final lines = <String, StockLine>{};
  StockLine lineFor(String name, String? unit) {
    final u = (unit == null || unit.trim().isEmpty) ? null : unit.trim();
    return lines.putIfAbsent('${_norm(name)}|${_norm(u ?? '')}', () => StockLine(name.trim(), u));
  }

  for (final r in receipts) {
    final line = lineFor(r.materialName, r.unit)..received += r.quantity;
    if (isOpeningStock(r)) line.opening += r.quantity;
  }
  for (final u in usage) {
    lineFor(u.materialName, u.unit).used += u.quantity;
  }
  if (projectId != null && moves.isNotEmpty) {
    final names = <String, ({String name, String? unit})>{
      for (final m in moves) '${_norm(m.materialName)}|${_norm(m.unit?.trim() ?? '')}': (name: m.materialName, unit: m.unit),
    };
    for (final MapEntry(:key, :value) in siteMoveTotals(moves, projectId).entries) {
      final n = names[key]!;
      lineFor(n.name, n.unit)
        ..transferredIn += value.inQty
        ..transferredOut += value.outQty;
    }
  }
  final out = lines.values.toList()
    ..sort((a, b) {
      final s = b.status.index.compareTo(a.status.index); // problems first
      return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return out;
}
