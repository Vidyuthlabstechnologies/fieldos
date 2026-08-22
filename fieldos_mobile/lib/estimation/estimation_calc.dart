/// Pure BOQ/estimation calculation functions — a faithful Dart port of
/// `fieldos/estimation_calc.py`.
///
/// Kept free of any database or UI dependency so the precision-critical
/// formulas can be golden-tested against the client's real sheets (the same
/// "reconcile against the sheet's own totals, refuse on mismatch" discipline
/// the desktop importer enforces).
///
/// All arithmetic uses [Decimal], never [double], so rounding error does not
/// compound across hundreds of line items the way it does for the client's
/// real BOQ spreadsheets.
library;

import 'package:decimal/decimal.dart';

const calcVolume = 'volume';
const calcArea = 'area';
const calcSteelWeight = 'steel_weight';
const calcCount = 'count';

// Rounded conversions that match the Protek Consult estimation sheets exactly
// (verified against the Narapally masonry and Thumukunta steel sheets), rather
// than the more precise 0.3048 factor.
final ftToM = (Decimal.one / Decimal.parse('3.28')).toDecimal(scaleOnInfinitePrecision: 28);
final cftToCum =
    (Decimal.one / Decimal.parse('35.3147')).toDecimal(scaleOnInfinitePrecision: 28);
final kgToTonne =
    (Decimal.one / Decimal.parse('1000')).toDecimal(scaleOnInfinitePrecision: 28);

/// IS 1786 unit weight of a reinforcement bar, kg per metre: dia_mm^2 / 162.
Decimal steelUnitWeightKgPerM(Decimal barDiaMm) =>
    ((barDiaMm * barDiaMm) / Decimal.parse('162'))
        .toDecimal(scaleOnInfinitePrecision: 28);

/// Total weight (kg) for one steel reinforcement entry.
Decimal steelEntryWeightKg(Decimal barDiaMm, Decimal nos, Decimal lengthFt) {
  final lengthM = lengthFt * ftToM;
  return nos * lengthM * steelUnitWeightKgPerM(barDiaMm);
}

/// Per-row quantity for a volume/area/count measurement entry. Deductions
/// return a negative quantity so summing a cost head's entries yields the net.
Decimal measurementEntryQuantity(
  String calculationType, {
  Decimal? length,
  Decimal? width,
  Decimal? depth,
  required Decimal nos,
  bool isDeduction = false,
}) {
  late final Decimal qty;
  switch (calculationType) {
    case calcVolume:
      qty = (length ?? Decimal.zero) * (width ?? Decimal.zero) * (depth ?? Decimal.zero) * nos;
    case calcArea:
      qty = (length ?? Decimal.zero) * (width ?? Decimal.zero) * nos;
    case calcCount:
      qty = nos;
    default:
      throw ArgumentError('measurement entries do not support calculation_type=$calculationType');
  }
  return isDeduction ? -qty : qty;
}

// --- Inputs (kept structural and DB-free) -----------------------------------

class CalcMeasurement {
  const CalcMeasurement({
    this.length,
    this.width,
    this.depth,
    required this.nos,
    this.isDeduction = false,
  });
  final Decimal? length;
  final Decimal? width;
  final Decimal? depth;
  final Decimal nos;
  final bool isDeduction;
}

class CalcSteel {
  const CalcSteel({
    required this.barDiaMm,
    required this.nos,
    required this.lengthFt,
  });
  final Decimal barDiaMm;
  final Decimal nos;
  final Decimal lengthFt;
}

class CalcCostHead {
  const CalcCostHead({
    required this.id,
    required this.name,
    required this.calculationType,
    required this.billingUnit,
    required this.conversionFactor,
    this.ratePerUnit,
  });
  final String id;
  final String name;
  final String calculationType;
  final String billingUnit;
  final Decimal conversionFactor;
  final Decimal? ratePerUnit;
}

Decimal costHeadRawQuantity(
  CalcCostHead costHead, {
  Iterable<CalcMeasurement> measurements = const [],
  Iterable<CalcSteel> steel = const [],
}) {
  if (costHead.calculationType == calcSteelWeight) {
    var total = Decimal.zero;
    for (final e in steel) {
      total += steelEntryWeightKg(e.barDiaMm, e.nos, e.lengthFt);
    }
    return total;
  }
  var total = Decimal.zero;
  for (final e in measurements) {
    total += measurementEntryQuantity(
      costHead.calculationType,
      length: e.length,
      width: e.width,
      depth: e.depth,
      nos: e.nos,
      isDeduction: e.isDeduction,
    );
  }
  return total;
}

Decimal costHeadBillingQuantity(CalcCostHead costHead, Decimal rawQuantity) =>
    rawQuantity * costHead.conversionFactor;

/// Priced amount for a cost head, or null if no rate has been set yet.
Decimal? costHeadAmount(CalcCostHead costHead, Decimal billingQuantity) =>
    costHead.ratePerUnit == null ? null : billingQuantity * costHead.ratePerUnit!;

class CostHeadLine {
  const CostHeadLine({
    required this.costHeadId,
    required this.name,
    required this.billingUnit,
    required this.rawQuantity,
    required this.billingQuantity,
    required this.ratePerUnit,
    required this.amount,
  });
  final String costHeadId;
  final String name;
  final String billingUnit;
  final Decimal rawQuantity;
  final Decimal billingQuantity;
  final Decimal? ratePerUnit;
  final Decimal? amount;
}

class BOQResult {
  const BOQResult({
    this.lines = const [],
    required this.subtotal,
    this.contractorProfitPercent,
    required this.contractorProfitAmount,
    required this.grandTotal,
  });
  final List<CostHeadLine> lines;
  final Decimal subtotal;
  final Decimal? contractorProfitPercent;
  final Decimal contractorProfitAmount;
  final Decimal grandTotal;
}

/// Roll many cost heads (each with its entries) up into a priced BOQ.
BOQResult buildBoq(
  Iterable<(CalcCostHead, Iterable<CalcMeasurement>, Iterable<CalcSteel>)> costHeadsWithEntries, {
  Decimal? contractorProfitPercent,
}) {
  final lines = <CostHeadLine>[];
  var subtotal = Decimal.zero;
  for (final (costHead, entries, steelEntries) in costHeadsWithEntries) {
    final rawQty = costHeadRawQuantity(costHead, measurements: entries, steel: steelEntries);
    final billingQty = costHeadBillingQuantity(costHead, rawQty);
    final amount = costHeadAmount(costHead, billingQty);
    lines.add(CostHeadLine(
      costHeadId: costHead.id,
      name: costHead.name,
      billingUnit: costHead.billingUnit,
      rawQuantity: rawQty,
      billingQuantity: billingQty,
      ratePerUnit: costHead.ratePerUnit,
      amount: amount,
    ));
    if (amount != null) subtotal += amount;
  }
  final profitAmount = contractorProfitPercent == null
      ? Decimal.zero
      : ((subtotal * contractorProfitPercent) / Decimal.parse('100'))
          .toDecimal(scaleOnInfinitePrecision: 28);
  return BOQResult(
    lines: lines,
    subtotal: subtotal,
    contractorProfitPercent: contractorProfitPercent,
    contractorProfitAmount: profitAmount,
    grandTotal: subtotal + profitAmount,
  );
}
