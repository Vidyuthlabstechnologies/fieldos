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

import 'package:fieldos_mobile/core/market.dart';

/// The two kinds of client bill, named the way this market names them.
Map<String, String> get billKinds => {
      'ra': market.progressBillName,
      'tax_invoice': switch (currentMarket) {
        Market.us => 'Invoice',
        Market.uk => 'VAT invoice',
        _ => 'Tax invoice',
      },
    };

/// The tax lines on a bill: CGST + SGST or IGST in India, one line named
/// after the market's tax ("Sales tax 8.25%", "VAT 20%") everywhere else.
/// Outside India the single line is kept in the IGST column, so bills,
/// sync and old exports need no new fields.
List<(String, double)> taxLines(BillTotals t, {required double rate, required bool interState}) {
  if (!market.tax.splitsInsideState) {
    return rate > 0 || t.igst != 0 ? [('${market.tax.name} ${_pctLabel(rate)}%', t.igst)] : const [];
  }
  if (interState) return [('IGST ${_pctLabel(rate)}%', t.igst)];
  if (rate <= 0) return const [];
  return [('CGST ${_pctLabel(rate / 2)}%', t.cgst), ('SGST ${_pctLabel(rate / 2)}%', t.sgst)];
}

String _pctLabel(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

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

/// Rounds to paise, half up, as money_book.dart does. The nudge keeps an
/// exact half such as 46.25 x 18% = 8.325 (stored as 8.32499...) from
/// rounding down a paisa on the invoice.
double _round2(double v) => ((v * 100) + (v < 0 ? -1e-6 : 1e-6)).roundToDouble() / 100;

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
/// Outside India there is no CGST/SGST split: the whole tax is one line
/// (held in [BillTotals.igst]), whatever [interState] says.
BillTotals billTotals(
  List<BillLine> lines, {
  double gstRate = 18,
  bool interState = false,
  double retentionPct = 0,
  double tdsPct = 0,
}) {
  if (!market.tax.splitsInsideState) interState = true;
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

/// Whole number in international words, for every market but India:
/// 1,234,567 is "One Million Two Hundred Thirty Four Thousand Five Hundred
/// Sixty Seven" (British style adds "and": "Five Hundred and Sixty Seven").
String westernNumberWords(int n, {bool and = false}) {
  if (n == 0) return 'Zero';
  if (n < 0) return 'Minus ${westernNumberWords(-n, and: and)}';
  String chunk(int v) {
    final h = v ~/ 100, r = v % 100;
    return [
      if (h > 0) '${_ones[h]} Hundred',
      if (r > 0) '${and && h > 0 ? 'and ' : ''}${_belowHundred(r)}',
    ].join(' ');
  }

  const scales = ['', 'Thousand', 'Million', 'Billion', 'Trillion'];
  final parts = <String>[];
  var rest = n, i = 0;
  while (rest > 0 && i < scales.length) {
    final c = rest % 1000;
    if (c > 0) parts.insert(0, [chunk(c), if (scales[i].isNotEmpty) scales[i]].join(' '));
    rest ~/= 1000;
    i++;
  }
  if (rest > 0) parts.insert(0, '${westernNumberWords(rest, and: and)} Quadrillion');
  // "One Thousand and Five": British style joins a last chunk under 100.
  if (and && parts.length > 1 && n % 1000 > 0 && n % 1000 < 100) {
    parts[parts.length - 1] = 'and ${parts.last}';
  }
  return parts.join(' ');
}

/// A whole number in this market's words: lakh and crore in India,
/// thousand and million elsewhere.
String numberWords(int n) =>
    market.indianGrouping ? indianNumberWords(n) : westernNumberWords(n, and: market.wordsAnd);

/// An amount in words for bills and cheques: "Rupees Twelve Thousand Five
/// Hundred and Fifty Paise Only" in India, "Twelve Thousand Five Hundred
/// Dollars and Fifty Cents Only" in the US.
String amountInWords(double amount) {
  final minorTotal = (amount.abs() * 100).round();
  final major = minorTotal ~/ 100, minor = minorTotal % 100;
  final m = market;
  if (m.currencyWordsFirst) {
    final words = '${m.majorUnitWords} ${numberWords(major)}';
    if (m.minorWordsFirst && minor != 0) return '$words and ${m.minorUnitWords} ${_belowHundred(minor)} Only';
    return minor == 0 ? '$words Only' : '$words and ${_belowHundred(minor)} ${m.minorUnitWords} Only';
  }
  final words = '${numberWords(major)} ${m.majorUnitWords}';
  return minor == 0 ? '$words Only' : '$words and ${_belowHundred(minor)} ${m.minorUnitWords} Only';
}

/// [amountInWords] under its older name; follows the build's market.
String rupeesInWords(double amount) => amountInWords(amount);

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
/// A tax invoice number under rule 46(b) of the CGST Rules: at most 16
/// characters, only letters, digits, hyphen and slash, unique in the
/// financial year (the screen checks the bills already made).
bool isValidInvoiceNumber(String number) => RegExp(r'^[A-Za-z0-9/-]{1,16}$').hasMatch(number.trim());

/// The place of supply printed on a bill, as (state name, code), or null
/// when it can't be told. Building work is supplied where the site is
/// (section 12(3) of the IGST Act): inside the state that is our own GST
/// state; across states the client's GSTIN is the best guess the bill has.
(String, String)? placeOfSupply({required String ourGstin, String? clientGstin, required bool interState}) {
  final from = interState ? (clientGstin ?? '') : ourGstin;
  if (from.trim().length < 2) return null;
  final code = from.trim().substring(0, 2);
  final name = gstStates[code];
  return name == null ? null : (name, code);
}

/// The heading of a bill that is not an RA bill. Only a GST-registered
/// supplier issues a tax invoice; with no GST on the bill it is a bill of
/// supply, and without a GSTIN a plain invoice.
String invoiceTitle({required String ourGstin, required double gstRate}) {
  if (ourGstin.trim().isEmpty) return 'INVOICE';
  return gstRate > 0 ? 'TAX INVOICE' : 'BILL OF SUPPLY';
}

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

/// The retention % this bill may keep so that all retention on the
/// contract stays within the limit of retention fund: [pct] of [gross],
/// cut down to what is left of [limitPctOfContract] of [contractSum] after
/// [alreadyKept]. [pct] unchanged when there is no limit or no sum.
double retentionPctWithinLimit({
  required double pct,
  required double gross,
  required double alreadyKept,
  double? contractSum,
  double? limitPctOfContract,
}) {
  if (limitPctOfContract == null || contractSum == null || contractSum <= 0 || gross <= 0 || pct <= 0) return pct;
  final room = contractSum * limitPctOfContract / 100 - alreadyKept;
  if (room <= 0) return 0;
  final wanted = gross * pct / 100;
  if (wanted <= room + 0.005) return pct;
  // Rounded down to 4 places so the money never goes over the limit.
  return (room / gross * 100 * 10000).floorToDouble() / 10000;
}

