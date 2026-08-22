/// Reconciliation — the heart of the "parse, then reconcile against the
/// sheet's own stated totals, refuse output on any mismatch" discipline used
/// by the desktop BOQ importers (e.g. `importers/narapally_boq.py`).
///
/// An importer parses a client spreadsheet, computes each quantity with the
/// [estimation_calc] engine, and compares the computed value to the total the
/// sheet *itself* states. If they disagree beyond tolerance, the import is
/// rejected rather than silently shipping wrong numbers.
library;

import 'package:decimal/decimal.dart';

class ReconciliationItem {
  ReconciliationItem({
    required this.label,
    required this.computed,
    required this.expected,
    Decimal? tolerance,
  }) : tolerance = tolerance ?? Decimal.zero;

  final String label;
  final Decimal computed;
  final Decimal expected;
  final Decimal tolerance;

  /// Absolute difference between computed and expected.
  Decimal get delta => (computed - expected).abs();

  bool get matches => delta <= tolerance;
}

class ReconciliationResult {
  const ReconciliationResult({this.items = const []});
  final List<ReconciliationItem> items;

  List<ReconciliationItem> get mismatches =>
      items.where((i) => !i.matches).toList();

  /// True only when every item reconciles within tolerance.
  bool get ok => mismatches.isEmpty;

  String get report => ok
      ? 'All ${items.length} figures reconciled against the source sheet.'
      : 'Reconciliation FAILED (${mismatches.length}/${items.length} mismatch):\n'
          '${mismatches.map((m) => '  - ${m.label}: computed ${m.computed} vs sheet ${m.expected} (Δ ${m.delta})').join('\n')}';
}

ReconciliationResult reconcile(List<ReconciliationItem> items) =>
    ReconciliationResult(items: items);

/// Convenience: assert a single computed quantity matches the sheet's stated
/// total, throwing [ReconciliationException] (carrying the full report) on
/// mismatch — i.e. an importer refuses to continue.
class ReconciliationException implements Exception {
  ReconciliationException(this.result);
  final ReconciliationResult result;
  @override
  String toString() => result.report;
}

void requireReconciled(ReconciliationResult result) {
  if (!result.ok) throw ReconciliationException(result);
}
