/// Stores and stock moves: what each store holds and what it is worth,
/// what is on the way, and what moved in and out of a site.
///
/// A move goes from one place to another, each place a store or a site.
/// Material bought into a store has no "from"; a count correction
/// (adjust) has only one end. A transfer leaves the sender when it is sent
/// and reaches the receiver when they count it, so material on a lorry is
/// in neither place's stock, and a short count shows as a shortage.
library;

import 'package:fieldos_mobile/data/app_database.dart';

const moveKinds = ['inward', 'transfer', 'adjust'];
const moveStatuses = ['in_transit', 'received', 'cancelled'];

const moveStatusLabels = {
  'in_transit': 'On the way',
  'received': 'Received',
  'cancelled': 'Cancelled',
};

const adjustReasonChoices = ['Count was short', 'Count was more', 'Damaged', 'Theft', 'Expired'];

String normMaterial(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
String materialKey(String name, String? unit) => '${normMaterial(name)}|${normMaterial(unit ?? '')}';

/// What reached the receiving end: what they counted, or all of it when
/// no count was entered.
double arrivedQty(StockMove m) => m.receivedQty ?? m.quantity;

/// Sent less what arrived, for a received transfer; 0 otherwise.
double shortage(StockMove m) =>
    m.kind == 'transfer' && m.status == 'received' ? (m.quantity - arrivedQty(m)).clamp(0, double.infinity) : 0;

bool _counts(StockMove m) => m.status != 'cancelled';

class StoreStockLine {
  StoreStockLine(this.name, this.unit);
  final String name;
  final String? unit;
  double inQty = 0;
  double outQty = 0;
  double _pricedQty = 0;
  double _pricedValue = 0;
  double get balance => inQty - outQty;

  /// Weighted average of what was paid for it (inward moves with a rate),
  /// or of the rates it arrived at.
  double? get avgRate => _pricedQty > 0 ? _pricedValue / _pricedQty : null;
  double get value => balance > 0 && avgRate != null ? balance * avgRate! : 0;
}

/// Everything held in [storeId], problems (below zero) first then by name.
List<StoreStockLine> storeStock(Iterable<StockMove> moves, String storeId) {
  final lines = <String, StoreStockLine>{};
  StoreStockLine lineFor(StockMove m) {
    final u = (m.unit == null || m.unit!.trim().isEmpty) ? null : m.unit!.trim();
    return lines.putIfAbsent(materialKey(m.materialName, u), () => StoreStockLine(m.materialName.trim(), u));
  }

  for (final m in moves) {
    if (!_counts(m)) continue;
    if (m.toStoreId == storeId && m.status == 'received') {
      final l = lineFor(m)..inQty += arrivedQty(m);
      if (m.rate != null && m.rate! > 0) {
        l._pricedQty += arrivedQty(m);
        l._pricedValue += arrivedQty(m) * m.rate!;
      }
    }
    if (m.fromStoreId == storeId) lineFor(m).outQty += m.quantity;
  }
  final out = lines.values.where((l) => l.inQty != 0 || l.outQty != 0).toList()
    ..sort((a, b) {
      final neg = (a.balance < 0 ? 0 : 1).compareTo(b.balance < 0 ? 0 : 1);
      return neg != 0 ? neg : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return out;
}

/// The average rate of a material in a store, to price a transfer out.
double? storeRate(Iterable<StockMove> moves, String storeId, String name, String? unit) {
  final k = materialKey(name, unit);
  for (final l in storeStock(moves, storeId)) {
    if (materialKey(l.name, l.unit) == k) return l.avgRate;
  }
  return null;
}

/// How much of a material is in a store now (0 when it has none).
double storeBalance(Iterable<StockMove> moves, String storeId, String name, String? unit) {
  final k = materialKey(name, unit);
  for (final l in storeStock(moves, storeId)) {
    if (materialKey(l.name, l.unit) == k) return l.balance;
  }
  return 0;
}

double storeValue(Iterable<StockMove> moves, String storeId) =>
    storeStock(moves, storeId).fold(0.0, (s, l) => s + l.value);

/// Transfers on the way to a store or a site, oldest first.
List<StockMove> onTheWayTo(Iterable<StockMove> moves, {String? storeId, String? projectId}) => [
      for (final m in moves)
        if (m.status == 'in_transit' &&
            ((storeId != null && m.toStoreId == storeId) || (projectId != null && m.toProjectId == projectId)))
          m
    ]..sort((a, b) => a.sentOn.compareTo(b.sentOn));

/// Quantities that came into and left a site through moves, by material
/// key (see [materialKey]).
Map<String, ({double inQty, double outQty})> siteMoveTotals(Iterable<StockMove> moves, String projectId) {
  final out = <String, ({double inQty, double outQty})>{};
  for (final m in moves) {
    if (!_counts(m)) continue;
    final k = materialKey(m.materialName, m.unit);
    if (m.toProjectId == projectId && m.status == 'received') {
      final c = out[k] ?? (inQty: 0.0, outQty: 0.0);
      out[k] = (inQty: c.inQty + arrivedQty(m), outQty: c.outQty);
    }
    if (m.fromProjectId == projectId) {
      final c = out[k] ?? (inQty: 0.0, outQty: 0.0);
      out[k] = (inQty: c.inQty, outQty: c.outQty + m.quantity);
    }
  }
  return out;
}

/// What material moved to a site is worth, less what it sent away: a
/// site that gets cement from the store carries its cost; a site that
/// sends its leftover steel on gives it up.
double siteTransferValue(Iterable<StockMove> moves, String projectId) {
  var v = 0.0;
  for (final m in moves) {
    if (!_counts(m) || m.rate == null) continue;
    if (m.toProjectId == projectId && m.status == 'received') v += arrivedQty(m) * m.rate!;
    if (m.fromProjectId == projectId) v -= m.quantity * m.rate!;
  }
  return v;
}

/// The checks a move must pass before it is saved. Returns the problem in
/// plain words, or null.
String? checkMove({
  required String kind,
  String? fromStoreId,
  String? fromProjectId,
  String? toStoreId,
  String? toProjectId,
  required String materialName,
  required double quantity,
  String? note,
}) {
  if (!moveKinds.contains(kind)) return 'Unknown kind of move.';
  if (materialName.trim().isEmpty) return 'Enter the material.';
  if (!(quantity > 0)) return 'Enter a quantity more than zero.';
  if (fromStoreId != null && fromProjectId != null) return 'A move leaves one place.';
  if (toStoreId != null && toProjectId != null) return 'A move goes to one place.';
  final from = fromStoreId ?? fromProjectId;
  final to = toStoreId ?? toProjectId;
  switch (kind) {
    case 'inward':
      if (toStoreId == null || from != null) return 'Material bought comes into a store.';
    case 'transfer':
      if (from == null || to == null) return 'Pick where it goes from and to.';
      if (from == to) return 'Pick two different places.';
    case 'adjust':
      if (fromProjectId != null || toProjectId != null) return 'Count corrections are for stores.';
      if ((fromStoreId == null) == (toStoreId == null)) return 'A correction is a loss or a gain at one store.';
      if ((note ?? '').trim().isEmpty) return 'Say why the count changed.';
  }
  return null;
}
