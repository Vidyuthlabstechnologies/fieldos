# Weekly site close and approvals

The first thing FieldOS sells to a company with several sites: every week,
each site's records become one review queue. A project manager approves
what is payable, sends back what is wrong, closes the week, and sends one
pack to accounts.

## Where it is

- Home > menu > **Weekly close**: every running site's week, the ones that
  need someone first.
- Approvals: a card at the top leads there.
- Each site: menu > **Weekly close**.

Code: `fieldos_mobile/lib/features/close/` (rules in `week_close.dart`,
loading and decisions in `week_close_data.dart`, the PDF and CSV in
`week_close_pack.dart`, screens in `week_close_screen.dart`).

## What is in the queue

| Item | From | Flagged when |
|---|---|---|
| Wages, one per worker | wage sheet (punches and hand marks) and wage payments | punch-out missing, no daily wage set, advance not worked off |
| Days without attendance | Mon to Sat up to today | nobody punched in or was marked, on a site with workers or with a report |
| Expenses | money book, cancelled ones too | no bill photo (wage payments excepted), voucher number not confirmed by the server, edited after entry, cancelled |
| Deliveries | goods receipts | not against a PO, no delivery slip photo, no invoice amount, order closed short, more than ordered |

## Decisions

Every decision is one row in `site_close_reviews` (phone: `close_reviews`).
Rows are only ever added; the server grants select and insert, nothing
else, so the dated history can't be rewritten.

| Decision | Who | Effect |
|---|---|---|
| approved | owner, project manager | item is approved; for a delivery, records the quantity accepted |
| sent_back | owner, project manager | item goes back to the site with a note |
| fixed | anyone on the site | "sorted" for a fix that changed nothing on record |
| closed / reopened | owner, project manager | the whole week |

Each decision stores the item's fingerprint (amount, category, quantity...).
An approved item edited later shows as **Changed after approval**; a sent
back item that is edited shows as **Corrected, review again**; a closed
week with such an item shows as **Changed since close**. The week can be
closed only when everything is approved and nothing is out on send-back.

`created_at` is when the decision was made on the phone (kept, so an
offline Saturday approval still reads Saturday; future times are clamped
to the server's clock); `synced_at` is when the server got it.

## Delivery slips

The GRN dialog's photo is now a real attachment (`site_receipt_attachments`,
file at `{projectId}/receipt-slips/{id}.{ext}` in the `documents` bucket),
synced like expense bills. Before v15 the photo path was written into the
receipt's note and never left the phone; the v15 upgrade moves those into
slips and queues them.

## The pack for accounts

A PDF (summary, wages and advances, expense vouchers, material receipts
with ordered / accepted quantities, days without attendance, approval
history, up to 40 bill and slip photos) and a CSV with one line per item.
English, like the bill and voucher PDFs.

## Production

Migration `supabase/migrations/20261110030000_weekly_close.sql` must be
applied after the three migrations of PR #119 (issue #118).

## The demo (one complete transaction)

`fieldos_mobile/test/cement_delivery_demo_test.dart` runs it on two phones
against the local Supabase stack. For a live demo, two Android phones on
the same company:

1. Office phone (owner or PM): Procure > raise a request for 100 bags of
   cement, make the PO, send it to the supplier.
2. Supervisor phone, airplane mode on: Procure > the PO > Receive. 95 bags,
   invoice amount, **Photograph the delivery slip**, tick "Everything on
   this order has come", Receive.
3. Turn airplane mode off. Team & sync > Sync now (or wait a minute).
4. Office phone: Home > menu > Weekly close > the site. The cement shows
   against PO-xxxx, "Short by 5 bags against the order", with the slip one
   tap away. Approve, enter 93 accepted ("2 bags split").
5. Close the week, then the PDF button: the pack goes to accounts on
   WhatsApp or email.
6. Supervisor phone after a sync: the delivery reads Approved, 93 accepted.
