# Tally and Zoho exports, checked before they are sent

This is part of item 5 of the weekly-close plan. Settings > Send to your accountant writes:

- Tally voucher XML, plus a Tally ledgers file to import first;
- or a Zoho Books expense CSV.

Before the share sheet opens, the file is read back the way the importer
reads it. If any check fails, nothing is sent, and the phone says what was
wrong.

- Export: `fieldos_mobile/lib/features/export/accounts_export.dart`
- Checks: `fieldos_mobile/lib/features/export/accounts_check.dart`

## Tally

1. Import `<company>_tally_ledgers.xml` first, from Gateway > Import >
   Masters. It creates each ledger the vouchers use, in this group:
   - Bank Accounts for the bank;
   - Duties & Taxes (GST) for input IGST, CGST and SGST;
   - Sundry Debtors for clients;
   - Direct Expenses for expense categories.

   Cash is left out because every Tally company has it.
2. Then import `<company>_tally_vouchers.xml` from Import > Vouchers.

The vouchers file is checked for these things:

- It is well-formed XML, and an Import Data / Vouchers request for a
  named company.
- Each voucher:
  - has a known type that matches `VCHTYPE`;
  - has a date that exists;
  - has a number used only once;
  - has two or more ledger lines.
- Each line has an amount in rupees and paise, and its `ISDEEMEDPOSITIVE`
  agrees with its sign.
- Every voucher balances to the paisa.
- Every ledger is in the ledgers file.
- A Payment goes out of Cash or the bank. A Receipt comes into one.

Two sites with the same initials could produce the same voucher number,
such as `KV/V-4`. The later voucher gets `-2` added.

## Zoho Books

The file is imported from Purchases > Expenses > Import. It is checked for
these things:

- Zoho's columns are there (Expense Date, Expense Account, Paid Through,
  Amount).
- Every row has as many fields as the header. Quoted commas, quotes and
  new lines are handled.
- Each row has a real `yyyy-mm-dd` date, an amount above zero, an
  account, and a tax rate from 0 to 100 when one is given.

## Limits

These checks follow the importers' published rules. They were not run
against a live Tally or Zoho company here. The first customer import
should be watched, and anything it rejects added as a check.

## Tests

`test/accounts_check_test.dart` covers two things:
- A year of random expenses and receipts passes every check. That is 400
  expenses at every GST rate, with commas, quotes and new lines, on two
  sites with the same initials.
- Each kind of broken file is caught.
