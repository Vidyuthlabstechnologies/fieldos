/// Checks an accounts export the way Tally and Zoho Books read it, before
/// it leaves the phone. A file that fails is not shared, so an accountant
/// never gets an import that stops half way.
///
/// Tally voucher import: the XML is well formed and is a Vouchers import
/// for a named company. Each voucher has a known type matching its
/// VCHTYPE, a real date, a number used once, and two or more ledger lines.
/// Each line's ISDEEMEDPOSITIVE agrees with its sign, the lines add up to
/// zero, and every ledger is on the list to create. A Payment pays out of
/// Cash or the bank, and a Receipt comes into one.
///
/// Zoho Books expense import: the header has Zoho's columns, and every row
/// has the same number of fields. Each row has a real date, an amount above
/// zero, an account, and a tax rate from 0 to 100 when one is given.
library;

import 'package:xml/xml.dart';

class ExportCheck {
  const ExportCheck(this.problems, {required this.entries});

  /// What would make the import fail or come in wrong. Empty when fine.
  final List<String> problems;
  final int entries;
  bool get ok => problems.isEmpty;
}

const _voucherTypes = {'Payment', 'Receipt', 'Journal', 'Contra', 'Sales', 'Purchase'};
const _moneyLedgers = {'Cash', 'Bank Account'};

DateTime? _date(String s, RegExp shape, int Function(String) y, int Function(String) m, int Function(String) d) {
  if (!shape.hasMatch(s)) return null;
  final out = DateTime(y(s), m(s), d(s));
  return out.year == y(s) && out.month == m(s) && out.day == d(s) ? out : null;
}

DateTime? _tallyDate(String s) => _date(s, RegExp(r'^\d{8}$'), (s) => int.parse(s.substring(0, 4)),
    (s) => int.parse(s.substring(4, 6)), (s) => int.parse(s.substring(6, 8)));

DateTime? _isoDate(String s) => _date(s, RegExp(r'^\d{4}-\d{2}-\d{2}$'), (s) => int.parse(s.substring(0, 4)),
    (s) => int.parse(s.substring(5, 7)), (s) => int.parse(s.substring(8, 10)));

String _text(XmlElement parent, String name) => parent.getElement(name)?.innerText.trim() ?? '';

/// Checks Tally voucher XML. [ledgers]: the ledger list sent with it.
ExportCheck checkTallyXml(String xml, {required Iterable<String> ledgers}) {
  final problems = <String>[];
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    return ExportCheck(['The file is not valid XML: ${e.message}'], entries: 0);
  }
  final env = doc.rootElement;
  if (env.name.local != 'ENVELOPE') problems.add('The file does not start with ENVELOPE');
  final header = env.getElement('HEADER');
  if (header == null || _text(header, 'TALLYREQUEST') != 'Import Data') problems.add('TALLYREQUEST is not Import Data');
  final desc = env.getElement('BODY')?.getElement('IMPORTDATA')?.getElement('REQUESTDESC');
  if (desc == null || _text(desc, 'REPORTNAME') != 'Vouchers') problems.add('REPORTNAME is not Vouchers');
  if ((desc?.getElement('STATICVARIABLES')?.getElement('SVCURRENTCOMPANY')?.innerText.trim() ?? '').isEmpty) {
    problems.add('No company is named');
  }
  final known = ledgers.toSet();
  final numbers = <String>{};
  var count = 0;
  for (final v in env.findAllElements('VOUCHER')) {
    count++;
    final type = _text(v, 'VOUCHERTYPENAME');
    final number = _text(v, 'VOUCHERNUMBER');
    final label = number.isEmpty ? 'Voucher $count' : 'Voucher $number';
    if (!_voucherTypes.contains(type)) problems.add('$label: unknown voucher type "$type"');
    if (v.getAttribute('VCHTYPE') != type) problems.add('$label: VCHTYPE and VOUCHERTYPENAME differ');
    if (_tallyDate(_text(v, 'DATE')) == null) problems.add('$label: date "${_text(v, 'DATE')}" is not a real date');
    if (number.isEmpty) {
      problems.add('$label: no voucher number');
    } else if (!numbers.add('$type|$number')) {
      problems.add('$label: number used twice');
    }
    final lines = v.findElements('ALLLEDGERENTRIES.LIST').toList();
    if (lines.length < 2) problems.add('$label: needs at least two ledger lines');
    var sum = 0.0;
    var moneyIn = false, moneyOut = false;
    for (final l in lines) {
      final ledger = _text(l, 'LEDGERNAME');
      final amountText = _text(l, 'AMOUNT');
      final amount = RegExp(r'^-?\d+\.\d{2}$').hasMatch(amountText) ? double.parse(amountText) : null;
      if (ledger.isEmpty) problems.add('$label: a line has no ledger');
      if (ledger.isNotEmpty && !known.contains(ledger)) problems.add('$label: ledger "$ledger" is not on the list to create');
      if (amount == null) {
        problems.add('$label: amount "$amountText" is not in rupees and paise');
        continue;
      }
      if (amount == 0) problems.add('$label: a line of zero');
      final deemed = _text(l, 'ISDEEMEDPOSITIVE');
      if (deemed != (amount < 0 ? 'Yes' : 'No')) problems.add('$label: ISDEEMEDPOSITIVE disagrees with the sign on "$ledger"');
      sum += amount;
      if (_moneyLedgers.contains(ledger)) {
        if (amount < 0) moneyIn = true;
        if (amount > 0) moneyOut = true;
      }
    }
    if (sum.abs() >= 0.005) problems.add('$label: debits and credits differ by ${sum.abs().toStringAsFixed(2)}');
    if (type == 'Payment' && !moneyOut) problems.add('$label: a payment that is not paid from Cash or the bank');
    if (type == 'Receipt' && !moneyIn) problems.add('$label: a receipt that does not come into Cash or the bank');
  }
  return ExportCheck(problems, entries: count);
}

/// Splits one CSV line, with quoted fields and doubled quotes.
List<String>? _csvFields(String line) {
  final out = <String>[];
  final cur = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          cur.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cur.write(c);
      }
    } else if (c == '"' && cur.isEmpty) {
      quoted = true;
    } else if (c == ',') {
      out.add(cur.toString());
      cur.clear();
    } else {
      cur.write(c);
    }
  }
  if (quoted) return null;
  out.add(cur.toString());
  return out;
}

/// Splits CSV text into records, keeping newlines inside quotes.
List<String> _csvRecords(String text) {
  final out = <String>[];
  final cur = StringBuffer();
  var quotes = 0;
  for (final line in text.split('\n')) {
    if (cur.isNotEmpty) cur.write('\n');
    cur.write(line);
    quotes += '"'.allMatches(line).length;
    if (quotes.isEven) {
      out.add(cur.toString());
      cur.clear();
      quotes = 0;
    }
  }
  if (cur.isNotEmpty) out.add(cur.toString());
  return out;
}

/// The columns Zoho Books needs to import an expense.
const zohoRequiredColumns = ['Expense Date', 'Expense Account', 'Paid Through', 'Amount'];

ExportCheck checkZohoCsv(String csv) {
  final problems = <String>[];
  final records = _csvRecords(csv.endsWith('\n') ? csv.substring(0, csv.length - 1) : csv);
  if (records.isEmpty || records.first.trim().isEmpty) return const ExportCheck(['The file is empty'], entries: 0);
  final header = _csvFields(records.first) ?? const [];
  for (final c in zohoRequiredColumns) {
    if (!header.contains(c)) problems.add('Column "$c" is missing');
  }
  if (problems.isNotEmpty) return ExportCheck(problems, entries: 0);
  int col(String name) => header.indexOf(name);
  var rows = 0;
  for (var i = 1; i < records.length; i++) {
    final row = 'Row ${i + 1}';
    final f = _csvFields(records[i]);
    rows++;
    if (f == null) {
      problems.add('$row: a quote is not closed');
      continue;
    }
    if (f.length != header.length) {
      problems.add('$row: ${f.length} fields, the header has ${header.length}');
      continue;
    }
    if (_isoDate(f[col('Expense Date')]) == null) problems.add('$row: date "${f[col('Expense Date')]}" is not a real date');
    final amount = double.tryParse(f[col('Amount')]);
    if (amount == null || amount <= 0) problems.add('$row: amount "${f[col('Amount')]}" is not above zero');
    if (f[col('Expense Account')].trim().isEmpty) problems.add('$row: no expense account');
    if (f[col('Paid Through')].trim().isEmpty) problems.add('$row: no paid-through account');
    final t = col('Tax Percentage');
    if (t >= 0 && f[t].isNotEmpty) {
      final rate = double.tryParse(f[t]);
      if (rate == null || rate < 0 || rate > 100) problems.add('$row: tax rate "${f[t]}" is not a percentage');
    }
  }
  return ExportCheck(problems, entries: rows);
}
