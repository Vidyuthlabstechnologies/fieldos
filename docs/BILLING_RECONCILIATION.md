# Measurement to billing, and reconciliation

Item 4 of the weekly-close plan (schema v18). It adds four things:

1. Approved measured work becomes the client's RA bill.
2. Payments received are put against bills.
3. Retention is released.
4. Suppliers' invoices are checked against the PO and what arrived.

Rules: `fieldos_mobile/lib/features/money/billing_reconcile.dart`.
Storage: `BillingRecordsDao`.

## Measurement book

Each site > menu > **Measurement book** (also from Money > Bills).

1. Anyone on the site measures work done against a BOQ item, or any item
   with a unit and rate. They can add where it was done, such as "Block A,
   2nd floor". A minus quantity corrects an earlier measurement.
   Measurements are never edited.
2. The owner or a project manager approves all of a measurement or part of
   it, or rejects it. Each measurement gets one decision, and decisions are
   insert-only on the server.
3. **Make the next RA bill** works out each item's approved quantity to
   date less what earlier RA bills billed. The rate is the measurement's,
   or else the BOQ cost head's. An item with no rate is held back until it
   has one. The usual bill screen then opens with these lines filled in.

The builder also accepts approved extras, such as variations, as plain
lines: description, unit, quantity and rate. Each extra is billed once.
The variations register lives in the commercial-controls work (PR #122).
That thread wires approved client-instruction and design-change variations into `extras`, keyed '<title> (VO-<id>)' so none is billed twice, once it has this commit. The client rate is entered on the RA screen, because variations carry only cost.

## Payments against bills, and retention

Money > Bills.

- **Put against bills** spreads every payment's unallocated amount over the
  oldest bills still due.
- On one bill, **Payment against this bill** takes part of a chosen payment.
  **Release retention** records retention coming back.
- A bill whose net amount is covered is marked paid. Undoing the allocation
  makes it due again.
- Each bill shows what was received, what is still due, and the retention
  held.

The server checks the same limits in the trigger
`site_bill_allocations_check`:

- the payment and the bill are on the same site;
- the payment is not cancelled;
- the allocations never add up to more than the payment;
- a bill is never paid more than its net amount, and its retention never
  released beyond what was kept.

Only owners and PMs read or write allocations, the same as bills.

## Supplier invoice against PO and GRN

Each site > menu > **Supplier invoices**. Anyone on the site enters the
invoice: supplier, PO, number, date, total with GST, and optionally the GST
and the quantity. The phone flags an invoice that is:

- not against a purchase order;
- a repeat of an invoice number already entered from that supplier;
- more than the PO, counting earlier invoices on the same PO;
- more than the value received on the PO's GRNs, with the difference shown;
- for more quantity than was received;
- against nothing received yet.

A rupee either way counts as rounding. Owners and PMs can cancel an
invoice (long press) with a reason. The server allows no other change.

## Production

Apply `supabase/migrations/20261110310000_billing_reconciliation.sql`
after `20261110210000_site_roles.sql`.

## Tests

- `test/billing_reconcile_test.dart` covers the rules and the DAO.
- `test/billing_cloud_test.dart` runs on phones against local Supabase. It
  checks that:
  - the engineer's approval is refused;
  - an approved quantity above what was measured is refused;
  - an allocation beyond the payment is refused;
  - an invoice edit is refused;
  - pulls bring everything to a new manager's phone.
