/// A supplier's statement: the opening balance, every delivery and every
/// payment in date order, with the running balance. Onsite's reviews ask
/// for a party ledger with "opening balance" and "advance given", and for
/// sending it to the party.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_book.dart' show voucherLabel;
import 'package:fieldos_mobile/features/procurement/purchase_tools.dart' show paidToSupplier;
import 'package:fieldos_mobile/features/procurement/site_stock.dart' show isOpeningStock;

enum StatementKind { opening, delivery, payment }

class StatementLine {
  StatementLine({
    required this.on,
    required this.kind,
    required this.label,
    required this.amount,
    this.site,
    this.reference,
  });

  final DateTime? on;
  final StatementKind kind;
  final String label;

  /// What it adds to the balance owed: deliveries add, payments take off.
  final double amount;
  final String? site;
  final String? reference;
  double balance = 0;
}

/// Lines oldest first, each with the balance after it.
List<StatementLine> supplierStatement({
  required Supplier supplier,
  required Iterable<MaterialReceipt> receipts,
  required Iterable<PurchaseOrder> orders,
  required Iterable<SiteExpense> expenses,
  Map<String, String> siteName = const {},
}) {
  final orderSupplier = {for (final o in orders) o.id: o.supplierId};
  final lines = <StatementLine>[
    for (final r in receipts)
      if ((r.supplierId ?? (r.poId == null ? null : orderSupplier[r.poId])) == supplier.id && !isOpeningStock(r))
        StatementLine(
          on: r.receivedOn,
          kind: StatementKind.delivery,
          label: '${r.materialName} ${fmtQty(r.quantity)}${r.unit == null ? '' : ' ${r.unit}'}',
          amount: r.amount,
          site: siteName[r.projectId],
        ),
    for (final e in expenses)
      if (paidToSupplier(e, supplier))
        StatementLine(
          on: expenseDate(e),
          kind: StatementKind.payment,
          label: e.note?.trim().isNotEmpty == true ? e.note!.trim() : e.category,
          amount: -e.amount,
          site: siteName[e.projectId],
          reference: e.voucherNo == null ? null : voucherLabel(e.voucherNo),
        ),
  ]..sort((a, b) => a.on!.compareTo(b.on!));
  final opening = supplier.openingBalance ?? 0;
  final out = [
    if (opening != 0) StatementLine(on: null, kind: StatementKind.opening, label: 'Opening balance', amount: opening),
    ...lines,
  ];
  var running = 0.0;
  for (final l in out) {
    running += l.amount;
    l.balance = (running * 100).roundToDouble() / 100;
  }
  return out;
}

DateTime expenseDate(SiteExpense e) {
  final d = DateTime.tryParse(e.incurredOn) ?? e.createdAt;
  return DateTime(d.year, d.month, d.day);
}

/// The statement as a WhatsApp message to send to the supplier.
String statementText(Supplier s, List<StatementLine> lines, {required String companyName}) {
  final b = StringBuffer('Statement: ${s.name}\nFrom $companyName\n\n');
  for (final l in lines) {
    final when = l.on == null ? '' : '${fmtDate(l.on!, short: true)} ';
    final sign = l.amount >= 0 ? '+' : '-';
    final ref = l.reference == null ? '' : ' (${l.reference})';
    b.write('$when${l.label}$ref: $sign${rupees(l.amount.abs(), paise: true)} = ${rupees(l.balance, paise: true)}\n');
  }
  final last = lines.isEmpty ? 0.0 : lines.last.balance;
  b.write('\n${last > 0 ? 'Balance due to you' : last < 0 ? 'Advance with you' : 'Settled'}'
      '${last.abs() < 0.005 ? '' : ': ${rupees(last.abs(), paise: true)}'}');
  return b.toString();
}

/// What is still owed to a supplier, by how long it has been owed.
class Ageing {
  double upTo30 = 0;
  double upTo60 = 0;
  double upTo90 = 0;
  double over90 = 0;

  /// Days since the oldest delivery still unpaid; null when none is.
  int? oldestDays;

  /// Part of the opening balance is still unpaid.
  bool openingUnpaid = false;

  double get total => upTo30 + upTo60 + upTo90 + over90;
  List<double> get buckets => [upTo30, upTo60, upTo90, over90];
}

/// Payments settle the oldest bills first, the way suppliers count them.
/// The opening balance (from before FieldOS) is the oldest of all and is
/// counted as over 90 days.
Ageing ageStatement(List<StatementLine> lines, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final debits = [
    for (final l in lines)
      if (l.amount > 0) (on: l.on, left: l.amount),
  ]..sort((a, b) => a.on == null ? -1 : b.on == null ? 1 : a.on!.compareTo(b.on!));
  var credit = lines.where((l) => l.amount < 0).fold<double>(0, (s, l) => s - l.amount);
  final out = Ageing();
  for (final d in debits) {
    final used = credit >= d.left ? d.left : credit;
    credit -= used;
    final left = d.left - used;
    if (left < 0.005) continue;
    final days = d.on == null ? 9999 : today.difference(DateTime(d.on!.year, d.on!.month, d.on!.day)).inDays;
    if (days <= 30) {
      out.upTo30 += left;
    } else if (days <= 60) {
      out.upTo60 += left;
    } else if (days <= 90) {
      out.upTo90 += left;
    } else {
      out.over90 += left;
    }
    if (d.on == null) {
      out.openingUnpaid = true;
    } else if (out.oldestDays == null || days > out.oldestDays!) {
      out.oldestDays = days;
    }
  }
  return out;
}
