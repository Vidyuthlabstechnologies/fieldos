/// Measurement to billing, and reconciliation. Pure code on plain values:
///
/// - The next RA bill: approved measured quantity to date, item by item,
///   less what earlier bills billed, plus approved extras (variations).
/// - What each bill has been paid, and how much retention is still held.
/// - Spreading a payment over the oldest unpaid bills.
/// - A supplier's invoice checked against its PO and what was received.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/l10n/language.dart';

double _r2(double v) => (v * 100).roundToDouble() / 100;
double _r3(double v) => (v * 1000).roundToDouble() / 1000;

// --- RA bill from approved measurements ------------------------------------

class ApprovedItem {
  ApprovedItem(this.description, this.unit, this.rate);
  final String description;
  final String unit;
  double? rate;
  double qty = 0;
  String get itemKey => '${description.toLowerCase()}|${unit.toLowerCase()}';
}

/// Approved quantity to date per BOQ item (same key as [BillLine.itemKey]),
/// counting measurements on or before [upTo]. The rate is the latest one
/// given; [boqRates] (by cost head id) fills it when none was.
Map<String, ApprovedItem> approvedToDate(
  List<WorkMeasurement> measurements,
  Map<String, WorkMeasurementDecision> decisions, {
  DateTime? upTo,
  Map<String, double> boqRates = const {},
}) {
  final out = <String, ApprovedItem>{};
  final sorted = [...measurements]..sort((a, b) => a.measuredOn.compareTo(b.measuredOn));
  for (final m in sorted) {
    if (upTo != null && m.measuredOn.isAfter(upTo)) continue;
    final d = decisions[m.id];
    if (d == null || d.decision != 'approved' || d.approvedQty == null) continue;
    final item = ApprovedItem(m.description.trim(), m.unit.trim(), null);
    final it = out.putIfAbsent(item.itemKey, () => item);
    it.qty = _r3(it.qty + d.approvedQty!);
    it.rate = m.rate ?? it.rate ?? (m.costHeadId == null ? null : boqRates[m.costHeadId]);
  }
  return out;
}

/// Something approved outside the measurement book that the client pays
/// for, such as a variation: billed once, in full, on the next bill.
class ApprovedExtra {
  const ApprovedExtra({required this.description, required this.unit, required this.qty, required this.rate});
  final String description;
  final String unit;
  final double qty;
  final double rate;
}

class RaDraft {
  const RaDraft(this.lines, {required this.noRate});
  final List<BillLine> lines;

  /// Items with approved quantity but no rate: set one before billing.
  final List<String> noRate;
}

/// The lines of the next RA bill: for each item, approved to date less
/// billed before. Extras already billed (same description and unit with
/// at least the quantity) are left out.
RaDraft nextRaLines({
  required Map<String, ApprovedItem> approved,
  required Iterable<List<BillLine>> earlierBills,
  List<ApprovedExtra> extras = const [],
}) {
  final before = previousQuantities(earlierBills);
  final lines = <BillLine>[];
  final noRate = <String>[];
  for (final a in approved.values) {
    final qty = _r3(a.qty - (before[a.itemKey] ?? 0));
    if (qty.abs() < 0.0005) continue;
    if (a.rate == null) {
      noRate.add(a.description);
      continue;
    }
    lines.add(BillLine(description: a.description, unit: a.unit, rate: a.rate!, qty: qty));
  }
  for (final e in extras) {
    final key = '${e.description.toLowerCase()}|${e.unit.toLowerCase()}';
    final left = _r3(e.qty - (before[key] ?? 0));
    if (left <= 0.0005) continue;
    lines.add(BillLine(description: e.description, unit: e.unit, rate: e.rate, qty: left));
  }
  return RaDraft(lines, noRate: noRate);
}

// --- What each bill has been paid -----------------------------------------

class BillBalance {
  BillBalance(this.bill);
  final ClientBill bill;
  double paid = 0;
  double retentionReleased = 0;

  double get retentionKept => _r2(bill.gross * bill.retentionPct / 100);
  double get outstanding => _r2(bill.netPayable - paid) > 0.005 ? _r2(bill.netPayable - paid) : 0;
  double get retentionHeld => _r2(retentionKept - retentionReleased) > 0.005 ? _r2(retentionKept - retentionReleased) : 0;
  bool get settled => outstanding == 0;
}

/// Oldest bill first.
List<BillBalance> billBalances(List<ClientBill> bills, List<BillAllocation> allocations) {
  final by = {for (final b in bills) b.id: BillBalance(b)};
  for (final a in allocations) {
    final b = by[a.billId];
    if (b == null) continue;
    if (a.kind == 'retention') {
      b.retentionReleased = _r2(b.retentionReleased + a.amount);
    } else {
      b.paid = _r2(b.paid + a.amount);
    }
  }
  final out = by.values.toList()
    ..sort((x, y) {
      final c = x.bill.billDate.compareTo(y.bill.billDate);
      return c != 0 ? c : x.bill.billNumber.compareTo(y.bill.billNumber);
    });
  return out;
}

/// What is left of each payment to put against bills.
Map<String, double> unallocated(List<PaymentsReceivedData> payments, List<BillAllocation> allocations) {
  final out = {for (final p in payments) if (!p.voided) p.id: p.amount};
  for (final a in allocations) {
    if (out.containsKey(a.paymentId)) out[a.paymentId] = _r2(out[a.paymentId]! - a.amount);
  }
  return out;
}

/// How to spread [amount] over the oldest bills still unpaid: (bill id,
/// amount) pairs. Whatever is left over stays on the payment.
List<(String, double)> planAllocation(double amount, List<BillBalance> balances) {
  var left = _r2(amount);
  final out = <(String, double)>[];
  for (final b in balances) {
    if (left <= 0.005) break;
    if (b.outstanding <= 0) continue;
    final take = left < b.outstanding ? left : b.outstanding;
    out.add((b.bill.id, _r2(take)));
    left = _r2(left - take);
  }
  return out;
}

// --- Supplier invoice against PO and GRN ----------------------------------

enum InvoiceFlag { noPo, duplicate, overOrder, overReceived, qtyOverReceived, nothingReceived }

class InvoiceCheck {
  const InvoiceCheck({
    required this.invoice,
    required this.flags,
    this.ordered,
    required this.received,
    required this.receivedQty,
    required this.invoicedBefore,
  });
  final SupplierInvoice invoice;
  final List<InvoiceFlag> flags;

  /// The PO's value, when there is a PO.
  final double? ordered;

  /// Value and quantity received against the PO (or, with no PO, from the
  /// supplier on this site up to the invoice date).
  final double received;
  final double receivedQty;

  /// Earlier invoices on the same PO (cancelled ones left out).
  final double invoicedBefore;

  bool get matched => flags.isEmpty;

  /// What this invoice asks for beyond what was received.
  double get overBy => _r2(invoicedBefore + invoice.amount - received) > 0.5 ? _r2(invoicedBefore + invoice.amount - received) : 0;
}

/// A rupee either way is rounding.
const invoiceTolerance = 1.0;

/// Checks [invoice] against its PO and the receipts. [others]: the
/// company's other invoices from suppliers (for duplicates and what was
/// invoiced on the same PO before).
InvoiceCheck checkSupplierInvoice(
  SupplierInvoice invoice, {
  PurchaseOrder? order,
  required List<MaterialReceipt> receipts,
  required List<SupplierInvoice> others,
}) {
  final flags = <InvoiceFlag>[];
  final live = others.where((o) => !o.voided && o.id != invoice.id).toList();
  if (live.any((o) =>
      o.supplierId == invoice.supplierId &&
      o.invoiceNumber.trim().toLowerCase() == invoice.invoiceNumber.trim().toLowerCase())) {
    flags.add(InvoiceFlag.duplicate);
  }
  final List<MaterialReceipt> against;
  double invoicedBefore = 0;
  if (order == null) {
    flags.add(InvoiceFlag.noPo);
    against = [
      for (final r in receipts)
        if (r.supplierId == invoice.supplierId && r.projectId == invoice.projectId && r.poId == null) r,
    ];
  } else {
    against = [for (final r in receipts) if (r.poId == order.id) r];
    invoicedBefore = live
        .where((o) => o.poId == order.id && (o.invoiceDate.isBefore(invoice.invoiceDate) ||
            (o.invoiceDate == invoice.invoiceDate && o.createdAt.isBefore(invoice.createdAt))))
        .fold(0.0, (s, o) => s + o.amount);
  }
  final received = _r2(against.fold(0.0, (s, r) => s + r.amount));
  final receivedQty = _r3(against.fold(0.0, (s, r) => s + r.quantity));
  final total = invoicedBefore + invoice.amount;
  if (order != null && order.totalAmount != null && total > order.totalAmount! + invoiceTolerance) {
    flags.add(InvoiceFlag.overOrder);
  }
  if (against.isEmpty) {
    flags.add(InvoiceFlag.nothingReceived);
  } else if (total > received + invoiceTolerance) {
    flags.add(InvoiceFlag.overReceived);
  }
  if (invoice.qty != null && order != null) {
    final qtyBefore = live
        .where((o) => o.poId == order.id && o.qty != null && o.invoiceDate.isBefore(invoice.invoiceDate))
        .fold(0.0, (s, o) => s + o.qty!);
    if (qtyBefore + invoice.qty! > receivedQty + 0.0005) flags.add(InvoiceFlag.qtyOverReceived);
  }
  return InvoiceCheck(
    invoice: invoice,
    flags: flags,
    ordered: order?.totalAmount,
    received: received,
    receivedQty: receivedQty,
    invoicedBefore: _r2(invoicedBefore),
  );
}

String invoiceFlagLabel(InvoiceFlag f) => switch (f) {
      InvoiceFlag.noPo => tr('Not against a purchase order'),
      InvoiceFlag.duplicate => tr('Same invoice number entered before'),
      InvoiceFlag.overOrder => tr('More than the purchase order'),
      InvoiceFlag.overReceived => tr('More than what was received'),
      InvoiceFlag.qtyOverReceived => tr('More quantity than was received'),
      InvoiceFlag.nothingReceived => tr('Nothing received against it yet'),
    };
