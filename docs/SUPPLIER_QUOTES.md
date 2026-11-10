# Comparing supplier quotes

Purchases > Requests: tap a request to open **Compare quotes**.

- **Ask suppliers for rates**: one message with the material, quantity,
  site (with a map link when the site has a location) and what to quote.
  Share it anywhere, or open WhatsApp straight to a supplier who has a phone
  number (10-digit numbers get +91).
- **Add quote**: supplier, rate a unit, GST (0, 5, 12, 18 or 28%),
  transport, days to deliver, payment terms, valid until and a note. The
  landed total updates as you type. A second price from the same supplier
  replaces their first while nothing is decided.
- **Compared on landed cost**: rate times quantity, plus GST on the
  material, plus transport. Cheapest first, with what it saves against the
  next quote and against the request's estimate. Expired and turned-down
  quotes go to the bottom and are never "Cheapest". A quote that takes
  longer to deliver than another valid one shows its days in amber.
- **Give order** (owners and project managers): makes the PO for the
  request at the landed total, with the quote's terms in the PO notes and a
  delivery date from its days. That quote shows "Ordered"; the others are
  turned down. A second tap gives the same PO back.
- Anyone on the site can enter quotes. Only owners and project managers
  turn one down or give the order.

## Data

| Phone (Drift v23) | Server | Notes |
|---|---|---|
| `supplier_quotes` | `site_supplier_quotes` | `supplier_id` on the phone is `vendor_id` on the server |

Migration: `supabase/migrations/20261110420000_supplier_quotes.sql`.

The server checks the request and PO are on the quote's site and the vendor
is in the same company, stamps `created_by`, keeps a new quote from a
non-manager as "received", allows one accepted quote per request, and
keeps a decided quote as it was decided (a phone resending the same
decision changes nothing). The person who entered a quote may correct it
while it is undecided.

## Tests

- `test/quote_compare_test.dart`: landed cost, cheapest by landed not by
  rate, expiry, replacing a supplier's price, bad figures, giving the order.
- `test/quote_compare_screen_test.dart`: two quotes to a PO on a phone,
  Telugu on a 320 px phone.
- `test/schema_v23_upgrade_test.dart`: upgrade from v22.
- `test/supplier_quotes_cloud_test.dart`: engineer and owner phones against
  the local Supabase stack.
