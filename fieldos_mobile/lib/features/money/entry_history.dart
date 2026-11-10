/// Reading the change history: which entry changed, what each field was
/// and became, or what a deleted entry held.
library;

import 'dart:convert';

import 'package:fieldos_mobile/data/app_database.dart';

/// The kinds of entry the server keeps history for, by server table.
const historyKinds = {
  'site_expenses': 'Expense',
  'site_payments_received': 'Payment received',
  'site_material_receipts': 'Material received',
  'site_material_usage': 'Material used',
  'site_client_bills': 'Client bill',
  'site_attendance': 'Attendance punch',
  'site_supplier_invoices': 'Supplier invoice',
  'site_work_measurements': 'Work measurement',
};

/// Fields that are ids or bookkeeping, never shown as a change.
const _hidden = {
  'id', 'project_id', 'created_at', 'edited_at', 'edited_by', 'recorded_by', 'received_by', 'measured_by',
  'cost_head_id', 'cost_code_id', 'worker_id', 'supplier_id', 'po_id', 'photo_id', 'lines', 'voucher_no',
};

/// Fields holding rupees.
const moneyFields = {'amount', 'gross', 'net_payable', 'gst_amount', 'rate'};

/// The label for a field, in English (the screen translates it).
String fieldLabel(String f) => switch (f) {
      'amount' => 'Amount',
      'category' => 'Category',
      'incurred_on' => 'Date',
      'received_on' => 'Date',
      'used_on' => 'Date',
      'measured_on' => 'Date',
      'bill_date' => 'Date',
      'invoice_date' => 'Date',
      'paid_to' => 'Paid to',
      'mode' => 'Paid by',
      'note' || 'notes' => 'Note',
      'gst_pct' => 'GST %',
      'material_name' => 'Material',
      'quantity' || 'qty' => 'Quantity',
      'unit' => 'Unit',
      'from_party' => 'From',
      'worker_name' => 'Worker',
      'punch_in' => 'In',
      'punch_out' => 'Out',
      'within_geofence' => 'Inside the site fence',
      'voided' => 'Cancelled',
      'void_reason' => 'Reason',
      'description' => 'Work',
      'rate' => 'Rate',
      'location' => 'Location',
      'invoice_number' => 'Invoice number',
      'bill_number' => 'Bill number',
      'gst_amount' => 'GST',
      'gross' => 'Gross',
      'net_payable' => 'Net payable',
      'status' => 'Status',
      'client_name' => 'Client',
      _ => f.replaceAll('_', ' ').replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase()),
    };

class FieldChange {
  const FieldChange(this.field, this.before, this.after);
  final String field;
  final Object? before;
  final Object? after;
}

class HistoryItem {
  HistoryItem(this.row)
      : old = _decode(row.oldJson),
        now = row.newJson == null ? null : _decode(row.newJson!);
  final EntryHistoryData row;
  final Map<String, dynamic> old;
  final Map<String, dynamic>? now;

  static Map<String, dynamic> _decode(String s) {
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return const {};
    }
  }

  bool get deleted => row.op == 'delete';
  String get kind => historyKinds[row.sourceTable] ?? row.sourceTable;

  /// Was cancelled in this change (a void, not a correction).
  bool get cancelled => !deleted && old['voided'] != true && now?['voided'] == true;

  /// What changed, in a fixed order (money first), bookkeeping left out.
  List<FieldChange> get changes {
    final n = now;
    if (n == null) return const [];
    final keys = {...old.keys, ...n.keys}.where((k) => !_hidden.contains(k)).toList()
      ..sort((a, b) {
        final ma = moneyFields.contains(a) ? 0 : 1, mb = moneyFields.contains(b) ? 0 : 1;
        return ma != mb ? ma.compareTo(mb) : a.compareTo(b);
      });
    return [
      for (final k in keys)
        if (!_same(old[k], n[k])) FieldChange(k, old[k], n[k]),
    ];
  }

  /// A few words on what the entry was, for a deleted one or a title.
  String get summary {
    final r = now ?? old;
    final what = r['category'] ?? r['material_name'] ?? r['from_party'] ?? r['worker_name'] ??
        r['description'] ?? r['bill_number'] ?? r['invoice_number'] ?? r['client_name'];
    return [if (what != null) '$what', if (r['paid_to'] != null) '${r['paid_to']}'].join(' · ');
  }

  /// The entry's amount as it stood before the change, if it has one.
  num? get amountBefore => (old['amount'] ?? old['net_payable']) as num?;

  static bool _same(Object? a, Object? b) {
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return jsonEncode(a) == jsonEncode(b);
  }
}

Future<List<HistoryItem>> loadSiteHistory(AppDatabase db, String projectId) async =>
    [for (final r in await db.entryHistoryDao.forProject(projectId)) HistoryItem(r)];
