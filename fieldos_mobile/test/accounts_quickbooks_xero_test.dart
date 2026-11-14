import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/export/accounts_check.dart';
import 'package:fieldos_mobile/features/export/accounts_export.dart';

/// Outside India the accountant works in QuickBooks Online or Xero. Both
/// take a bank statement CSV per account with no chart of accounts set up.
void main() {
  tearDown(() => debugSetMarket(Market.india));

  SiteExpense e(String id, double amount, String day,
          {String category = 'Transport', String? mode, double? gst, bool voided = false, int? no, String? paidTo, String? note}) =>
      SiteExpense(
        id: '$id-0000-0000',
        projectId: 'p',
        category: category,
        amount: amount,
        incurredOn: day,
        recordedBy: 'u',
        createdAt: DateTime(2026, 1, 1),
        mode: mode,
        gstPct: gst,
        gstInterState: false,
        voided: voided,
        voucherNo: no,
        paidTo: paidTo,
        note: note,
      );
  PaymentsReceivedData pay(String id, double amount, DateTime on, {String mode = 'bank'}) => PaymentsReceivedData(
        id: '$id-0000-0000',
        projectId: 'p',
        amount: amount,
        receivedOn: on,
        fromParty: 'Smith, Jones & Co',
        mode: mode,
        recordedBy: 'u',
        createdAt: on,
        voided: false,
      );

  final expenses = [
    e('a', 150, '2026-11-02', mode: 'cash', no: 4, paidTo: 'Dumpster "Bob"'),
    e('b', 1200, '2026-11-03', category: 'Material', mode: 'card', gst: 20, no: 5, note: 'Rebar,\nfirst floor'),
    e('d', 90, '2026-11-05', voided: true, no: 7),
    e('f', 70, '2026-10-30', no: 3),
  ];
  final payments = [pay('m', 5000, DateTime(2026, 11, 6)), pay('n', 300, DateTime(2026, 11, 1), mode: 'cash')];

  Map<String, AccountsExport> run(AccountsFormat f) => bankStatementCsvs(
        format: f,
        expenses: expenses,
        payments: payments,
        siteName: {'p': 'Oak Street Duplex'},
        from: DateTime(2026, 11),
        to: DateTime(2026, 12),
      );

  test('QuickBooks (US): one file per account, signed amounts, month-first dates, oldest first', () {
    debugSetMarket(Market.us);
    final out = run(AccountsFormat.quickbooks);
    expect(out.keys, ['Bank Account', 'Cash']);
    final cash = out['Cash']!.text.trim().split('\n');
    expect(cash.first, 'Date,Description,Amount');
    expect(cash[1], startsWith('11/01/2026,'));
    expect(cash[1], endsWith(',300.00'));
    expect(cash[2], startsWith('11/02/2026,'));
    expect(cash[2], endsWith(',-150.00'));
    expect(out['Bank Account']!.vouchers, 2);
    expect(out['Bank Account']!.text, contains('Material | Oak Street Duplex'));
    expect(out['Bank Account']!.text, contains('incl.'));
    for (final x in out.values) {
      final check = checkBankStatementCsv(x.text, xero: false);
      expect(check.problems, isEmpty);
    }
    expect(out.values.fold<int>(0, (n, x) => n + x.vouchers), 4, reason: 'cancelled and out-of-period left out');
  });

  test('Xero (UK): payee and reference columns, day-first dates, quotes and newlines kept safe', () {
    debugSetMarket(Market.uk);
    final out = run(AccountsFormat.xero);
    final bank = out['Bank Account']!.text;
    expect(bank.split('\n').first, 'Date,Amount,Payee,Description,Reference');
    expect(bank, contains('03/11/2026,-1200.00,,'));
    expect(bank, contains('06/11/2026,5000.00,"Smith, Jones & Co"'));
    expect(out['Cash']!.text, contains('"Dumpster ""Bob"""'));
    for (final x in out.values) {
      expect(checkBankStatementCsv(x.text, xero: true).problems, isEmpty);
    }
  });

  test('the check refuses what the import would refuse', () {
    debugSetMarket(Market.us);
    expect(checkBankStatementCsv('Date,Description,Amount\n13/01/2026,x,5\n', xero: false).ok, isFalse);
    expect(checkBankStatementCsv('Date,Description,Amount\n01/13/2026,x,0\n', xero: false).ok, isFalse);
    expect(checkBankStatementCsv('Date,Amount\n01/13/2026,5\n', xero: false).ok, isFalse, reason: 'no Description');
    expect(checkBankStatementCsv('Date,Amount\n01/13/2026,5\n', xero: true).ok, isTrue);
    expect(checkBankStatementCsv('', xero: true).ok, isFalse);
  });

  test('financial year follows the market', () {
    expect(financialYear(DateTime(2026, 2, 1)), (DateTime(2025, 4), DateTime(2026, 4)));
    debugSetMarket(Market.us);
    expect(financialYear(DateTime(2026, 2, 1)), (DateTime(2026), DateTime(2027)));
    debugSetMarket(Market.uk);
    expect(financialYear(DateTime(2026, 5, 1)), (DateTime(2026, 4), DateTime(2027, 4)));
  });
}
