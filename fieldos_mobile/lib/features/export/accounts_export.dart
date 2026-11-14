/// The money book for the accountant: Tally vouchers (XML that Tally
/// Prime and Tally ERP 9 import through Import > Vouchers) and a Zoho
/// Books expense CSV. Every site expense becomes a Payment voucher and
/// every client payment a Receipt voucher, with GST split into input tax
/// ledgers and the site in the narration. Cancelled entries are left out.
///
/// Tally only accepts vouchers whose ledgers already exist, so the export
/// also lists the ledger names it used, to create once in Tally.
///
/// Outside India the books are in QuickBooks Online or Xero. Both import a
/// bank statement CSV into one bank or cash account without any chart of
/// accounts set up first, so that is what they get: one file per account
/// the money moved through. Their bills/invoice imports need the firm's own
/// account codes, which the phone does not know, so they are not used.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/accounts_check.dart';
import 'package:fieldos_mobile/features/money/money_book.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart' show sampleProjectId;

enum AccountsFormat { tally, zoho, quickbooks, xero }

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
  AccountsExport({required this.text, required this.ledgers, required this.vouchers, this.groups = const {}});

  /// The file's contents.
  final String text;

  /// Ledger names the vouchers use, to create in Tally first.
  final List<String> ledgers;
  final int vouchers;

  /// The Tally group each ledger belongs under, for [tallyLedgerMastersXml].
  final Map<String, String> groups;
}

/// Tally's group for a ledger the export uses.
String tallyGroup(String ledger, {required bool party}) => switch (ledger) {
      'Cash' => 'Cash-in-Hand',
      'Bank Account' => 'Bank Accounts',
      'Input IGST' || 'Input CGST' || 'Input SGST' => 'Duties & Taxes',
      _ => party ? 'Sundry Debtors' : 'Direct Expenses',
    };

/// The ledgers as Tally masters, to import once before the vouchers
/// (Gateway > Import > Masters). Cash is left out: every Tally company
/// already has it.
String tallyLedgerMastersXml(String companyName, AccountsExport export) {
  final out = StringBuffer();
  for (final l in export.ledgers) {
    if (l == 'Cash') continue;
    final group = export.groups[l] ?? 'Direct Expenses';
    out.write('<TALLYMESSAGE xmlns:UDF="TallyUDF"><LEDGER NAME="${_xml(l)}" ACTION="Create">'
        '<NAME.LIST><NAME>${_xml(l)}</NAME></NAME.LIST>'
        '<PARENT>${_xml(group)}</PARENT>'
        '${group == 'Duties & Taxes' ? '<TAXTYPE>GST</TAXTYPE>' : ''}'
        '</LEDGER></TALLYMESSAGE>');
  }
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY><IMPORTDATA>'
      '<REQUESTDESC><REPORTNAME>All Masters</REPORTNAME><STATICVARIABLES>'
      '<SVCURRENTCOMPANY>${_xml(companyName)}</SVCURRENTCOMPANY>'
      '</STATICVARIABLES></REQUESTDESC><REQUESTDATA>$out</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>\n';
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
  final parties = <String>{};
  final used = <String>{};
  // Two sites with the same initials could share a number; Tally would
  // then show two vouchers as one, so the later one gets a suffix.
  String unique(String number) {
    var n = number;
    for (var i = 2; !used.add(n); i++) {
      n = '$number-$i';
    }
    return n;
  }

  final out = StringBuffer();
  var n = 0;
  final ex = expenses.where((e) => !e.voided && e.amount > 0 && _inRange(expenseDay(e), from, to)).toList()
    ..sort((a, b) => expenseDay(a).compareTo(expenseDay(b)));
  for (final e in ex) {
    final site = siteName[e.projectId] ?? '';
    final entries = [..._expenseDebits(e), _Entry(cashLedger(e.mode), e.amount)];
    ledgers.addAll(entries.map((x) => x.ledger));
    final number = '${_short(site)}/${voucherLabel(e.voucherNo).isEmpty ? e.id.substring(0, 6) : voucherLabel(e.voucherNo)}';
    out.write(_voucherXml('Payment', expenseDay(e), unique(number), _expenseNarration(e, site), entries));
    n++;
  }
  final pay = payments.where((x) => !x.voided && x.amount > 0 && _inRange(x.receivedOn, from, to)).toList()
    ..sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
  for (final x in pay) {
    final site = siteName[x.projectId] ?? '';
    final party = x.fromParty.trim().isEmpty ? 'Client' : x.fromParty.trim();
    final entries = [_Entry(cashLedger(x.mode), -x.amount), _Entry(party, x.amount)];
    ledgers.addAll(entries.map((e) => e.ledger));
    parties.add(party);
    final narration = [site, if ((x.note ?? '').trim().isNotEmpty) x.note!.trim(), 'by ${x.mode}'].join(' | ');
    out.write(_voucherXml('Receipt', x.receivedOn, unique('${_short(site)}/R-${x.id.substring(0, 6)}'), narration, entries));
    n++;
  }
  final xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<ENVELOPE><HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER><BODY><IMPORTDATA>'
      '<REQUESTDESC><REPORTNAME>Vouchers</REPORTNAME><STATICVARIABLES>'
      '<SVCURRENTCOMPANY>${_xml(companyName)}</SVCURRENTCOMPANY>'
      '</STATICVARIABLES></REQUESTDESC><REQUESTDATA>$out</REQUESTDATA></IMPORTDATA></BODY></ENVELOPE>\n';
  return AccountsExport(
    text: xml,
    ledgers: ledgers.toList()..sort(),
    vouchers: n,
    groups: {for (final l in ledgers) l: tallyGroup(l, party: parties.contains(l))},
  );
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

String _statementDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0'), mm = d.month.toString().padLeft(2, '0');
  return market.dateOrder == DateOrder.mdy ? '$mm/$dd/${d.year}' : '$dd/$mm/${d.year}';
}

/// Header of the bank statement CSV each product reads. QuickBooks Online's
/// three-column layout (signed amount); Xero's statement import, where Date
/// and Amount are the required columns.
const quickbooksColumns = ['Date', 'Description', 'Amount'];
const xeroColumns = ['Date', 'Amount', 'Payee', 'Description', 'Reference'];

/// QuickBooks Online or Xero bank statement CSVs, one per account the money
/// moved through ("Cash", "Bank Account"): spending negative, client
/// payments positive, oldest first. Dates in the market's order, which is
/// how both products read a statement for a company in that country.
Map<String, AccountsExport> bankStatementCsvs({
  required AccountsFormat format,
  required Iterable<SiteExpense> expenses,
  required Iterable<PaymentsReceivedData> payments,
  required Map<String, String> siteName,
  DateTime? from,
  DateTime? to,
}) {
  assert(format == AccountsFormat.quickbooks || format == AccountsFormat.xero);
  final xero = format == AccountsFormat.xero;
  final lines = <String, List<(DateTime, String)>>{};
  final ledgers = <String, Set<String>>{};
  void add(String account, DateTime day, String row, String category) {
    lines.putIfAbsent(account, () => []).add((day, row));
    ledgers.putIfAbsent(account, () => {}).add(category);
  }

  for (final e in expenses.where((e) => !e.voided && e.amount > 0 && _inRange(expenseDay(e), from, to))) {
    final site = siteName[e.projectId] ?? '';
    final payee = e.paidTo?.trim() ?? '';
    final rate = e.gstPct ?? 0;
    final description = [
      expenseLedger(e),
      site,
      if (!xero && payee.isNotEmpty) payee,
      if ((e.note ?? '').trim().isNotEmpty) e.note!.trim(),
      if (rate > 0) '${market.tax.name} ${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2)}% incl.',
    ].join(' | ');
    final ref = voucherLabel(e.voucherNo).isEmpty ? e.id.substring(0, 8) : voucherLabel(e.voucherNo);
    final amount = _amt(-e.amount);
    final day = expenseDay(e);
    add(
      cashLedger(e.mode),
      day,
      xero
          ? [_statementDate(day), amount, _csv(payee), _csv(description), _csv(ref)].join(',')
          : [_statementDate(day), _csv('$description | $ref'), amount].join(','),
      expenseLedger(e),
    );
  }
  for (final x in payments.where((x) => !x.voided && x.amount > 0 && _inRange(x.receivedOn, from, to))) {
    final site = siteName[x.projectId] ?? '';
    final party = x.fromParty.trim().isEmpty ? 'Client' : x.fromParty.trim();
    final description = [
      'Client payment',
      site,
      if (!xero) party,
      if ((x.note ?? '').trim().isNotEmpty) x.note!.trim(),
      'by ${x.mode}',
    ].join(' | ');
    final ref = 'R-${x.id.substring(0, 6)}';
    add(
      cashLedger(x.mode),
      x.receivedOn,
      xero
          ? [_statementDate(x.receivedOn), _amt(x.amount), _csv(party), _csv(description), _csv(ref)].join(',')
          : [_statementDate(x.receivedOn), _csv('$description | $ref'), _amt(x.amount)].join(','),
      'Client payments',
    );
  }
  final header = (xero ? xeroColumns : quickbooksColumns).join(',');
  return {
    for (final account in lines.keys.toList()..sort())
      account: AccountsExport(
        text: '$header\n${((lines[account]!..sort((a, b) => a.$1.compareTo(b.$1))).map((l) => l.$2)).join('\n')}\n',
        ledgers: ledgers[account]!.toList()..sort(),
        vouchers: lines[account]!.length,
      ),
  };
}

/// The financial year [now] falls in: April to March in India and the UK
/// (its tax year), the calendar year in the US, Malaysia and the UAE, where
/// most small firms keep their books that way.
(DateTime, DateTime) financialYear(DateTime now) {
  final start = currentMarket == Market.india || currentMarket == Market.uk ? 4 : 1;
  final startYear = now.month >= start ? now.year : now.year - 1;
  return (DateTime(startYear, start), DateTime(startYear + 1, start));
}

/// The files to share: the vouchers, and for Tally the ledgers to import
/// first. [check] passed, or the files were not written.
class AccountsFiles {
  const AccountsFiles(this.file, this.export, this.check, {this.ledgersFile, this.moreFiles = const []});
  final File file;
  final File? ledgersFile;

  /// QuickBooks/Xero: the statements for the other accounts (one file each).
  final List<File> moreFiles;
  final AccountsExport export;
  final ExportCheck check;
}

/// The export failed its own check; it is not shared.
class AccountsExportProblem implements Exception {
  const AccountsExportProblem(this.check);
  final ExportCheck check;
  @override
  String toString() => 'The export did not pass its check: ${check.problems.take(3).join('; ')}';
}

/// Builds the export for the company's real sites (the demo site is left
/// out), checks it as Tally or Zoho would read it, and writes it to share.
Future<AccountsFiles> writeAccountsExport(
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
  final dir = await getTemporaryDirectory();
  final safe = companyName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  if (format == AccountsFormat.quickbooks || format == AccountsFormat.xero) {
    final xero = format == AccountsFormat.xero;
    final statements =
        bankStatementCsvs(format: format, expenses: expenses, payments: payments, siteName: names, from: from, to: to);
    final files = <File>[];
    final problems = <String>[];
    var rows = 0;
    for (final MapEntry(key: account, value: export) in statements.entries) {
      final check = checkBankStatementCsv(export.text, xero: xero);
      problems.addAll(check.problems.map((x) => '$account: $x'));
      rows += check.entries;
      final file = File(p.join(dir.path,
          '${safe}_${xero ? 'xero' : 'quickbooks'}_${account.replaceAll(' ', '_').toLowerCase()}.csv'));
      files.add(file);
      if (check.ok) await file.writeAsString(export.text, flush: true);
    }
    final check = ExportCheck(problems, entries: rows);
    if (!check.ok) throw AccountsExportProblem(check);
    final all = AccountsExport(
      text: statements.values.map((x) => x.text).join(),
      ledgers: {for (final x in statements.values) ...x.ledgers}.toList()..sort(),
      vouchers: rows,
    );
    if (files.isEmpty) {
      final empty = File(p.join(dir.path, '${safe}_${xero ? 'xero' : 'quickbooks'}.csv'));
      return AccountsFiles(empty, all, check);
    }
    return AccountsFiles(files.first, all, check, moreFiles: files.skip(1).toList());
  }
  final tally = format == AccountsFormat.tally;
  final export = tally
      ? tallyXml(companyName: companyName, expenses: expenses, payments: payments, siteName: names, from: from, to: to)
      : zohoExpensesCsv(expenses: expenses, siteName: names, from: from, to: to);
  final check = tally ? checkTallyXml(export.text, ledgers: export.ledgers) : checkZohoCsv(export.text);
  if (!check.ok) throw AccountsExportProblem(check);
  final file = File(p.join(dir.path, tally ? '${safe}_tally_vouchers.xml' : '${safe}_zoho_expenses.csv'));
  await file.writeAsString(export.text, flush: true);
  File? ledgersFile;
  if (tally) {
    ledgersFile = File(p.join(dir.path, '${safe}_tally_ledgers.xml'));
    await ledgersFile.writeAsString(tallyLedgerMastersXml(companyName, export), flush: true);
  }
  return AccountsFiles(file, export, check, ledgersFile: ledgersFile);
}
