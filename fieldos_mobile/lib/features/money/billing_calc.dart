/// Client bills: running account (RA) bills and GST tax invoices.
///
/// An RA bill lists the work measured since the last bill, item by item,
/// with what was billed before and the total to date. The money side adds
/// GST (CGST + SGST inside the state, IGST across states), then takes off
/// retention and TDS to give what the client should pay now.
///
/// Pure code on plain values so every figure is unit-tested.
library;

import 'dart:convert';

const billKinds = {'ra': 'Running bill (RA)', 'tax_invoice': 'Tax invoice'};

/// Construction services SAC (works contract). Editable per bill.
const defaultSac = '995411';

class BillLine {
  const BillLine({required this.description, required this.unit, required this.rate, required this.qty});

  final String description;
  final String unit;
  final double rate;

  /// Quantity billed on this bill.
  final double qty;

  double get amount => _round2(qty * rate);

  Map<String, dynamic> toJson() => {'d': description, 'u': unit, 'r': rate, 'q': qty};

  static BillLine fromJson(Map<String, dynamic> j) => BillLine(
        description: (j['d'] as String? ?? '').trim(),
        unit: (j['u'] as String? ?? '').trim(),
        rate: (j['r'] as num? ?? 0).toDouble(),
        qty: (j['q'] as num? ?? 0).toDouble(),
      );

  /// Lines with the same description and unit are the same BOQ item.
  String get itemKey => '${description.toLowerCase()}|${unit.toLowerCase()}';
}

String encodeLines(List<BillLine> lines) => jsonEncode([for (final l in lines) l.toJson()]);

List<BillLine> decodeLines(String json) {
  if (json.trim().isEmpty) return const [];
  final raw = jsonDecode(json);
  if (raw is! List) return const [];
  return [for (final j in raw) if (j is Map<String, dynamic>) BillLine.fromJson(j)];
}

double _round2(double v) => (v * 100).roundToDouble() / 100;

class BillTotals {
  const BillTotals({
    required this.gross,
    required this.cgst,
    required this.sgst,
    required this.igst,
    required this.retention,
    required this.tds,
  });

  /// Value of work on this bill, before tax.
  final double gross;
  final double cgst;
  final double sgst;
  final double igst;
  final double retention;
  final double tds;

  double get gst => _round2(cgst + sgst + igst);

  /// The bill's value with GST: the invoice total.
  double get invoiceTotal => _round2(gross + gst);

  /// What the client pays now: invoice total less retention and TDS.
  double get netPayable => _round2(invoiceTotal - retention - tds);
}

/// [gstRate] is the full rate (18 means 18%). Inside the state it splits
/// half CGST, half SGST; across states it is all IGST. Retention and TDS
/// are taken on the value before GST, as contracts and section 194C do.
BillTotals billTotals(
  List<BillLine> lines, {
  double gstRate = 18,
  bool interState = false,
  double retentionPct = 0,
  double tdsPct = 0,
}) {
  final gross = _round2(lines.fold<double>(0, (s, l) => s + l.amount));
  final tax = _round2(gross * gstRate / 100);
  final half = _round2(tax / 2);
  return BillTotals(
    gross: gross,
    cgst: interState ? 0 : half,
    sgst: interState ? 0 : _round2(tax - half),
    igst: interState ? tax : 0,
    retention: _round2(gross * retentionPct / 100),
    tds: _round2(gross * tdsPct / 100),
  );
}

/// Quantity of each item billed on earlier bills, by [BillLine.itemKey].
Map<String, double> previousQuantities(Iterable<List<BillLine>> earlierBills) {
  final out = <String, double>{};
  for (final bill in earlierBills) {
    for (final l in bill) {
      out[l.itemKey] = (out[l.itemKey] ?? 0) + l.qty;
    }
  }
  return out;
}

/// The next number in the project's series: "RA-03", "INV-0012". Looks at
/// the existing numbers with the same prefix and adds one.
String nextBillNumber(Iterable<String> existing, String kind) {
  final prefix = kind == 'ra' ? 'RA-' : 'INV-';
  final width = kind == 'ra' ? 2 : 4;
  var max = 0;
  for (final n in existing) {
    if (!n.toUpperCase().startsWith(prefix)) continue;
    final v = int.tryParse(n.substring(prefix.length).trim());
    if (v != null && v > max) max = v;
  }
  return '$prefix${(max + 1).toString().padLeft(width, '0')}';
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
  'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

String _belowHundred(int n) => n < 20 ? _ones[n] : [_tens[n ~/ 10], if (n % 10 > 0) _ones[n % 10]].join(' ');

String _belowThousand(int n) {
  final h = n ~/ 100, r = n % 100;
  return [if (h > 0) '${_ones[h]} Hundred', if (r > 0) _belowHundred(r)].join(' ');
}

/// Whole number in Indian words: 12,34,567 is "Twelve Lakh Thirty Four
/// Thousand Five Hundred Sixty Seven".
String indianNumberWords(int n) {
  if (n == 0) return 'Zero';
  if (n < 0) return 'Minus ${indianNumberWords(-n)}';
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final rest = n % 1000;
  return [
    if (crore > 0) '${crore >= 100 ? indianNumberWords(crore) : _belowHundred(crore)} Crore',
    if (lakh > 0) '${_belowHundred(lakh)} Lakh',
    if (thousand > 0) '${_belowHundred(thousand)} Thousand',
    if (rest > 0) _belowThousand(rest),
  ].join(' ');
}

/// "Rupees Twelve Thousand Five Hundred and Fifty Paise Only".
String rupeesInWords(double amount) {
  final paiseTotal = (amount.abs() * 100).round();
  final r = paiseTotal ~/ 100, p = paiseTotal % 100;
  final words = 'Rupees ${indianNumberWords(r)}';
  return p == 0 ? '$words Only' : '$words and ${_belowHundred(p)} Paise Only';
}

/// GST state codes, as printed on invoices (first two digits of a GSTIN).
const gstStates = {
  '01': 'Jammu and Kashmir', '02': 'Himachal Pradesh', '03': 'Punjab', '04': 'Chandigarh', '05': 'Uttarakhand',
  '06': 'Haryana', '07': 'Delhi', '08': 'Rajasthan', '09': 'Uttar Pradesh', '10': 'Bihar', '11': 'Sikkim',
  '12': 'Arunachal Pradesh', '13': 'Nagaland', '14': 'Manipur', '15': 'Mizoram', '16': 'Tripura',
  '17': 'Meghalaya', '18': 'Assam', '19': 'West Bengal', '20': 'Jharkhand', '21': 'Odisha', '22': 'Chhattisgarh',
  '23': 'Madhya Pradesh', '24': 'Gujarat', '26': 'Dadra and Nagar Haveli and Daman and Diu', '27': 'Maharashtra',
  '29': 'Karnataka', '30': 'Goa', '31': 'Lakshadweep', '32': 'Kerala', '33': 'Tamil Nadu', '34': 'Puducherry',
  '35': 'Andaman and Nicobar Islands', '36': 'Telangana', '37': 'Andhra Pradesh', '38': 'Ladakh',
};

final _gstinPattern = RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');

/// A GSTIN's shape: 15 characters, a known state code, PAN in the middle.
bool isValidGstin(String gstin) {
  final g = gstin.trim().toUpperCase();
  return _gstinPattern.hasMatch(g) && gstStates.containsKey(g.substring(0, 2));
}

/// Inter-state when both GSTINs are known and their state codes differ.
bool isInterState(String? ours, String? theirs) {
  final a = (ours ?? '').trim(), b = (theirs ?? '').trim();
  if (a.length < 2 || b.length < 2) return false;
  return a.substring(0, 2) != b.substring(0, 2);
}

/// The project's money picture: billed, received, spent, and the margin.
class ProjectPnl {
  const ProjectPnl({required this.billed, required this.received, required this.spent, required this.owed});

  /// Bills' value before GST (GST is the government's, not income).
  final double billed;
  final double received;
  final double spent;

  /// What the client still has to pay on bills not marked paid.
  final double owed;

  double get margin => _round2(billed - spent);

  /// Margin as a share of billed work, or null before the first bill.
  double? get marginPct => billed <= 0 ? null : margin / billed * 100;
}
