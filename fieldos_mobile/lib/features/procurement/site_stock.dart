/// Material on site: received (GRNs) minus used, per material and unit.
/// Names are matched ignoring case and extra spaces, so "Cement " and
/// "cement" are one line; different units ("bags" vs "kg") stay separate
/// rather than being guessed at.
library;

import 'package:fieldos_mobile/data/app_database.dart';

enum StockStatus { ok, low, out, overused }

/// Below this share of everything received, a material is flagged low.
const lowStockShare = 0.15;

class StockLine {
  StockLine(this.name, this.unit);
  final String name;
  final String? unit;
  double received = 0;
  double used = 0;
  double get balance => received - used;

  StockStatus get status {
    const eps = 1e-9;
    if (balance < -eps) return StockStatus.overused;
    if (balance.abs() <= eps) return StockStatus.out;
    if (received > 0 && balance <= received * lowStockShare) return StockStatus.low;
    return StockStatus.ok;
  }
}

String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

List<StockLine> buildSiteStock(List<MaterialReceipt> receipts, List<MaterialUsageData> usage) {
  final lines = <String, StockLine>{};
  StockLine lineFor(String name, String? unit) {
    final u = (unit == null || unit.trim().isEmpty) ? null : unit.trim();
    return lines.putIfAbsent('${_norm(name)}|${_norm(u ?? '')}', () => StockLine(name.trim(), u));
  }

  for (final r in receipts) {
    lineFor(r.materialName, r.unit).received += r.quantity;
  }
  for (final u in usage) {
    lineFor(u.materialName, u.unit).used += u.quantity;
  }
  final out = lines.values.toList()
    ..sort((a, b) {
      final s = b.status.index.compareTo(a.status.index); // problems first
      return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return out;
}
