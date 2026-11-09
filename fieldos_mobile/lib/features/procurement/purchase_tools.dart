/// Purchasing helpers: what is still to come on a PO when the supplier sends
/// part of it, what each supplier has been ordered and has delivered, how a
/// material's rate has moved, and the site units (bags, brass, rft) people
/// actually use.
library;

import 'package:fieldos_mobile/data/app_database.dart';

String _norm(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Statuses after which nothing more is expected on an order.
const closedOrderStatuses = {'delivered', 'cancelled', 'closed'};

class PoProgress {
  const PoProgress({required this.ordered, required this.received, required this.unit, required this.amountReceived});

  /// From the purchase request, null when the PO was raised without one.
  final double? ordered;
  final double received;
  final String unit;
  final double amountReceived;

  double? get pending => ordered == null ? null : (ordered! - received).clamp(0, double.infinity).toDouble();
  bool get partlyReceived => received > 0 && (pending ?? 0) > 0;
}

PoProgress poProgress(PurchaseOrder order, PurchaseRequest? request, Iterable<MaterialReceipt> receipts) {
  var qty = 0.0;
  var amount = 0.0;
  for (final r in receipts) {
    if (r.poId != order.id) continue;
    qty += r.quantity;
    amount += r.amount;
  }
  return PoProgress(
    ordered: request?.quantity,
    received: qty,
    unit: request?.unit ?? '',
    amountReceived: amount,
  );
}

/// An open order whose delivery date has passed.
bool poIsLate(PurchaseOrder order, DateTime now) {
  final due = order.deliveryDate;
  if (due == null || closedOrderStatuses.contains(order.status)) return false;
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(due.year, due.month, due.day).isBefore(today);
}

class SupplierLedger {
  SupplierLedger(this.supplierId);
  final String supplierId;
  double ordered = 0;
  double received = 0;
  int openOrders = 0;
  int lateOrders = 0;
  DateTime? lastDelivery;

  /// Ordered but not delivered yet, by value.
  double get toCome => ordered > received ? ordered - received : 0;

  /// Owed when the company started using FieldOS (negative: an advance).
  double opening = 0;

  /// Paid to them from any site's money book.
  double paid = 0;

  /// Still owed to them; negative is an advance they hold.
  double get balance => opening + received - paid;
}

String _party(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Whether an expense was paid to [supplier]: its "Paid to" names them.
bool paidToSupplier(SiteExpense e, Supplier supplier) =>
    !e.voided && e.paidTo != null && _party(e.paidTo!) == _party(supplier.name);

/// Per supplier: value of POs, value of goods received (with or without a
/// PO), and how many orders are open or late. Cancelled orders don't count.
///
/// With [suppliers] and [expenses], each ledger also carries the opening
/// balance and what was paid, so [SupplierLedger.balance] is what is owed.
Map<String, SupplierLedger> supplierLedgers(
    Iterable<PurchaseOrder> orders, Iterable<MaterialReceipt> receipts, DateTime now,
    {Iterable<Supplier> suppliers = const [], Iterable<SiteExpense> expenses = const []}) {
  final out = <String, SupplierLedger>{};
  for (final s in suppliers) {
    final paid = expenses.where((e) => paidToSupplier(e, s)).fold<double>(0, (t, e) => t + e.amount);
    if ((s.openingBalance ?? 0) == 0 && paid == 0) continue;
    out.putIfAbsent(s.id, () => SupplierLedger(s.id))
      ..opening = s.openingBalance ?? 0
      ..paid = paid;
  }
  final orderSupplier = <String, String>{};
  for (final o in orders) {
    orderSupplier[o.id] = o.supplierId;
    if (o.status == 'cancelled') continue;
    final l = out.putIfAbsent(o.supplierId, () => SupplierLedger(o.supplierId));
    l.ordered += o.totalAmount ?? 0;
    if (!closedOrderStatuses.contains(o.status)) l.openOrders++;
    if (poIsLate(o, now)) l.lateOrders++;
  }
  for (final r in receipts) {
    final sid = r.supplierId ?? (r.poId == null ? null : orderSupplier[r.poId]);
    if (sid == null) continue;
    final l = out.putIfAbsent(sid, () => SupplierLedger(sid));
    l.received += r.amount;
    if (l.lastDelivery == null || r.receivedOn.isAfter(l.lastDelivery!)) l.lastDelivery = r.receivedOn;
  }
  return out;
}

class RatePoint {
  const RatePoint(this.on, this.rate, this.supplierId);
  final DateTime on;
  final double rate;
  final String? supplierId;
}

class MaterialRate {
  MaterialRate(this.name, this.unit, this.points);
  final String name;
  final String? unit;

  /// Oldest first.
  final List<RatePoint> points;

  double get latest => points.last.rate;
  double? get previous => points.length < 2 ? null : points[points.length - 2].rate;

  /// Change from the previous delivery, in percent.
  double? get changePct {
    final p = previous;
    if (p == null || p == 0) return null;
    return (latest - p) / p * 100;
  }

  double get lowest => points.map((p) => p.rate).reduce((a, b) => a < b ? a : b);
  double get highest => points.map((p) => p.rate).reduce((a, b) => a > b ? a : b);
}

/// Rate per unit for each material, from the deliveries that have both a
/// quantity and an amount. Receipts with a different unit for the same
/// material are kept apart, so bags and tonnes don't mix.
List<MaterialRate> materialRates(Iterable<MaterialReceipt> receipts) {
  final groups = <String, List<MaterialReceipt>>{};
  for (final r in receipts) {
    if (r.quantity <= 0 || r.amount <= 0) continue;
    groups.putIfAbsent('${_norm(r.materialName)}|${_norm(r.unit ?? '')}', () => []).add(r);
  }
  final out = <MaterialRate>[];
  for (final g in groups.values) {
    g.sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
    out.add(MaterialRate(
      g.first.materialName.trim(),
      (g.first.unit ?? '').trim().isEmpty ? null : g.first.unit!.trim(),
      [for (final r in g) RatePoint(r.receivedOn, r.amount / r.quantity, r.supplierId)],
    ));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

// --- Quote check -----------------------------------------------------------

/// How a new rate compares with what the company usually pays.
class RateCheck {
  const RateCheck({
    required this.rate,
    required this.usual,
    required this.deliveries,
    this.best,
  });

  /// Rate per unit of the quote or bill being entered.
  final double rate;

  /// Median of the recent deliveries' rates, so one odd bill doesn't skew it.
  final double usual;
  final int deliveries;

  /// The cheapest recent delivery, to name who to call.
  final RatePoint? best;

  double get diffPct => usual == 0 ? 0 : (rate - usual) / usual * 100;

  /// 5% either way is normal day-to-day movement.
  bool get high => diffPct >= 5;
  bool get low => diffPct <= -5;

  /// What the difference costs on [qty] units.
  double extraOn(double qty) => (rate - usual) * qty;
}

/// Compares [amount] for [qty] of [material] with the company's own recent
/// deliveries of the same material in the same unit (any site). Null until
/// there are two earlier deliveries to compare with, or when the entry has
/// no quantity or amount yet.
RateCheck? checkRate({
  required String material,
  required String? unit,
  required double? qty,
  required double? amount,
  required Iterable<MaterialReceipt> history,
  int recent = 6,
  DateTime? now,
}) {
  if (qty == null || amount == null || qty <= 0 || amount <= 0 || material.trim().isEmpty) return null;
  final key = '${_norm(material)}|${_norm(unit ?? '')}';
  final match = materialRates(history).where((r) => '${_norm(r.name)}|${_norm(r.unit ?? '')}' == key).firstOrNull;
  if (match == null || match.points.length < 2) return null;
  final since = (now ?? DateTime.now()).subtract(const Duration(days: 180));
  final pts = match.points.where((p) => p.on.isAfter(since)).toList();
  final last = (pts.length >= 2 ? pts : match.points).reversed.take(recent).toList();
  final sorted = [for (final p in last) p.rate]..sort();
  final mid = sorted.length ~/ 2;
  final usual = sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  final best = last.reduce((a, b) => b.rate < a.rate ? b : a);
  return RateCheck(rate: amount / qty, usual: usual, deliveries: last.length, best: best);
}

// --- Site units -------------------------------------------------------------

class SiteUnit {
  const SiteUnit(this.key, this.label, this.toBase);
  final String key;
  final String label;

  /// How many of the group's base unit one of this is.
  final double toBase;
}

class UnitGroup {
  const UnitGroup(this.label, this.units);
  final String label;
  final List<SiteUnit> units;
}

/// Base units: metre, square metre, cubic metre, kilogram.
const unitGroups = [
  UnitGroup('Length', [
    SiteUnit('m', 'Metre', 1),
    SiteUnit('rft', 'Running feet', 0.3048),
    SiteUnit('in', 'Inch', 0.0254),
    SiteUnit('mm', 'Millimetre', 0.001),
  ]),
  UnitGroup('Area', [
    SiteUnit('sqm', 'Square metre', 1),
    SiteUnit('sqft', 'Square feet', 0.09290304),
    SiteUnit('sqyd', 'Square yard (gaj)', 0.83612736),
    SiteUnit('guntha', 'Guntha', 101.17141056),
    SiteUnit('acre', 'Acre', 4046.8564224),
  ]),
  UnitGroup('Volume', [
    SiteUnit('cum', 'Cubic metre', 1),
    SiteUnit('cft', 'Cubic feet', 0.028316846592),
    SiteUnit('brass', 'Brass (100 cft)', 2.8316846592),
    SiteUnit('l', 'Litre', 0.001),
  ]),
  UnitGroup('Weight', [
    SiteUnit('kg', 'Kilogram', 1),
    SiteUnit('t', 'Tonne', 1000),
    SiteUnit('quintal', 'Quintal', 100),
    SiteUnit('bag', 'Cement bag (50 kg)', 50),
  ]),
];

double convertUnits(double value, SiteUnit from, SiteUnit to) => value * from.toBase / to.toBase;

/// Weight of a steel bar per metre, by the site rule d² / 162 (d in mm).
double steelKgPerMetre(double diameterMm) => diameterMm * diameterMm / 162;
