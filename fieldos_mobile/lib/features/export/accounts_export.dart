/// The money book for the accountant: Tally vouchers (XML that Tally
/// Prime and Tally ERP 9 import through Import > Vouchers) and a Zoho
/// Books expense CSV. Every site expense becomes a Payment voucher and
/// every client payment a Receipt voucher, with GST split into input tax
/// ledgers and the site in the narration. Cancelled entries are left out.
///
/// Tally only accepts vouchers whose ledgers already exist, so the export
/// also lists the ledger names it used, to create once in Tally.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart' show sampleProjectId;

enum AccountsFormat { tally, zoho }

/// Ledger the money moved through: Cash for cash, else the bank.
String cashLedger(String? mode) => (mode ?? 'cash').toLowerCase() == 'cash' ? 'Cash' : 'Bank Account';

/// Expense ledger: the category, as the accountant sees it in the books.
String expenseLedger(SiteExpense e) => e.category.trim().isEmpty ? 'Site Expenses' : e.category.trim();

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _tallyDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

String _amt(double v) => v.toStringAsFixed(2);

class _Entry {
  const _Entry(this.ledger, this.amount);
  final String ledger;

  /// Tally's sign: debits are negative, credits positive.
  final double amount;
}

String _ledgerXml(_Entry e) => '<ALLLEDGERENTRIES.LIST>'
    '<LEDGERNAME>${_xml(e.ledger)}</LEDGERNAME>'
    '<ISDEEMEDPOSITIVE>${e.amount < 0 ? 'Yes' : 'No'}</ISDEEMEDPOSITIVE>'
    '<AMOUNT>${_amt(e.amount)}</AMOUNT>'
    '</ALLLEDGERENTRIES.LIST>';

String _voucherXml(String type, DateTime date, String number, String narration, List<_Entry> entries) =>
    '<TALLYMESSAGE xmlns:UDF="TallyUDF"><VOUCHER VCHTYPE="$type" ACTION="Create">'
    '<DATE>${_tallyDate(date)}</DATE>'
    '<VOUCHERTYPENAME>$type</VOUCHERTYPENAME>'
    '<VOUCHERNUMBER>${_xml(number)}</VOUCHERNUMBER>'
    '<NARRATION>${_xml(narration)}</NARRATION>'
    '${entries.map(_ledgerXml).join()}'
    '</VOUCHER></TALLYMESSAGE>';

/// The debit side of an expense: the expense ledger, plus input GST when
/// the bill carried it.
List<_Entry> _expenseDebits(SiteExpense e) {
  final rate = e.gstPct ?? 0;
  if (rate <= 0) return [_Entry(expenseLedger(e), -e.amount)];
  final g = gstSplit(e.amount, rate, interState: e.gstInterState);
  return [
    _Entry(expenseLedger(e), -g.taxable),
    if (g.igst > 0) _Entry('Input IGST', -g.igst),
    if (g.cgst > 0) _Entry('Input CGST', -g.cgst),
    if (g.sgst > 0) _Entry('Input SGST', -g.sgst),
  ];
}

String _expenseNarration(SiteExpense e, String site) => [
      site,
      if ((e.paidTo ?? '').trim().isNotEmpty) 'Paid to ${e.paidTo!.trim()}',
      if ((e.note ?? '').trim().isNotEmpty) e.note!.trim(),
      'FieldOS ${voucherLabel(e.voucherNo).isEmpty ? e.id.substring(0, 8) : voucherLabel(e.voucherNo)}',
    ].join(' | ');

class AccountsExport {
  AccountsExport({required this.text, required this.ledgers, required this.vouchers});

  /// The file's contents.
  final String text;

  /// Ledger names the vouchers use, to create in Tally first.
  final List<String> ledgers;
  final int vouchers;
}

bool _inRange(DateTime d, DateTime? from, DateTime? to) =>
    (from == null || !d.isBefore(from)) && (to == null || d.isBefore(to));

/// Tally XML for the given entries. [siteName] maps project ids to names.
AccountsExport tallyXml({
  required String companyName,
  required Iterable<SiteExpense> expenses,
  required Iterable<PaymentsReceivedData> payments,
  required Map<String, String> siteName,
  DateTime? from,
  DateTime? to,
}) {
  final ledgers = <String>{};
  final out = StringBuffer();
  var n = 0;
  final ex = expenses.where((e) => !e.voided && e.amount > 0 && _inRange(expenseDay(e), from, to)).toList()
    ..sort((a, b) => expenseDay(a).compareTo(expenseDay(b)));
  for (final e in ex) {
    final site = siteName[e.projectId] ?? '';
    final entries = [..._expenseDebits(e), _Entry(cashLedger(e.mode), e.amount)];
    ledgers.addAll(entries.map((x) => x.ledger));
    final number = '${_short(site)}/${voucherLabel(e.voucherNo).isEmpty ? e.id.substring(0, 6) : voucherLabel(e.voucherNo)}';
    out.write(_voucherXml('Payment', expenseDay(e), number, _expenseNarration(e, site), entries));
    n++;
  }
  final pay = payments.where((x) => !x.voided && x.amount > 0 && _inRange(x.receivedOn, from, to)).toList()
    ..sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
  for (final x in pay) {
    final site = siteName[x.projectId] ?? '';
    final party = x.fromParty.trim().isEmpty ? 'Client' : x.fromParty.trim();
    final entries = [_Entry(cashLedger(x.mode), -x.amount), _Entry(party, x.amount)];
    ledgers.addAll(entries.map((e) => e.ledger));
    final narration = [site, if ((x.note ?? '').trim().isNotEmpty) x.note!.trim(), 'by ${x.mode}'].join(' | ');
    out.write(_voucherXml('Receipt', x.receivedOn, '${_short(site)}/R-${x.id.substring(0, 6)}', narration, entries));
    n++;
  }
  final xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY><IMPORTDATA>'
      '<REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES>'
      '<SVCURRENTCOMPANY>${_xml(companyName)}</SVCURRENTCOMPANY>'
      '</STATICVARIABLES></REQUESTDESC><REQUESTDATA>$out</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>\n';
  return AccountsExport(text: xml, ledgers: ledgers.toList()..sort(), vouchers: n);
}

String _short(String site) {
  final words = site.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final s = words.map((w) => w[0].toUpperCase()).join();
  return s.isEmpty ? 'SITE' : (s.length > 6 ? s.substring(0, 6) : s);
}

String _csv(String s) => s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Zoho Books "Import Expenses" CSV. Amounts are what was paid, GST
/// included; the tax rate column lets Zoho split it.
AccountsExport zohoExpensesCsv({
  required Iterable<SiteExpense> expenses,
  required Map<String, String> siteName,
  DateTime? from,
  DateTime? to,
}) {
  final rows = <String>['Expense Date,Expense Account,Paid Through,Vendor,Amount,Tax Percentage,Reference#,Description,Project'];
  final ledgers = <String>{};
  final ex = expenses.where((e) => !e.voided && e.amount > 0 && _inRange(expenseDay(e), from, to)).toList()
    ..sort((a, b) => expenseDay(a).compareTo(expenseDay(b)));
  for (final e in ex) {
    ledgers
      ..add(expenseLedger(e))
      ..add(cashLedger(e.mode));
    rows.add([
      _isoDate(expenseDay(e)),
      _csv(expenseLedger(e)),
      _csv(cashLedger(e.mode)),
      _csv(e.paidTo?.trim() ?? ''),
      _amt(e.amount),
      e.gstPct == null ? '' : e.gstPct!.toStringAsFixed(e.gstPct! % 1 == 0 ? 0 : 2),
      _csv(voucherLabel(e.voucherNo)),
      _csv(e.note?.trim() ?? ''),
      _csv(siteName[e.projectId] ?? ''),
    ].join(','));
  }
  return AccountsExport(text: '${rows.join('\n')}\n', ledgers: ledgers.toList()..sort(), vouchers: ex.length);
}

/// Indian financial year (April to March) that [now] falls in.
(DateTime, DateTime) financialYear(DateTime now) {
  final startYear = now.month >= 4 ? now.year : now.year - 1;
  return (DateTime(startYear, 4), DateTime(startYear + 1, 4));
}

/// Builds the export for the company's real sites (the demo site is left
/// out) and writes it to a file to share.
Future<(File, AccountsExport)> writeAccountsExport(
  AppDatabase db, {
  required String companyId,
  required String companyName,
  required AccountsFormat format,
  DateTime? from,
  DateTime? to,
}) async {
  final sample = await sampleProjectId(db, companyId);
  final projects = (await db.projectDao.forCompany(companyId)).where((x) => x.id != sample).toList();
  final expenses = <SiteExpense>[];
  final payments = <PaymentsReceivedData>[];
  for (final x in projects) {
    expenses.addAll(await db.expenseDao.forProject(x.id));
    payments.addAll(await db.paymentDao.forProject(x.id));
  }
  final names = {for (final x in projects) x.id: x.name};
  final export = format == AccountsFormat.tally
      ? tallyXml(companyName: companyName, expenses: expenses, payments: payments, siteName: names, from: from, to: to)
      : zohoExpensesCsv(expenses: expenses, siteName: names, from: from, to: to);
  final dir = await getTemporaryDirectory();
  final safe = companyName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final file = File(p.join(dir.path, format == AccountsFormat.tally ? '${safe}_tally_vouchers.xml' : '${safe}_zoho_expenses.csv'));
  await file.writeAsString(export.text, flush: true);
  return (file, export);
}
