# Commercial controls (FOS-201 to FOS-204)

One connected flow that answers three questions on every site: what did we
agree to pay, what work was actually accepted, and what will the project
cost to finish.

## Where it is

- Each site: menu > **Work orders, variations and cost** (tabs: work
  orders, variations, cost to complete).
- Home > menu > **Commercial exceptions**: one queue across sites.
- Subcontractors: paywall or company setup > **Subcontractor? Join free
  with the builder's code**. The owner or a project manager shares the code
  from the subcontractor's page (key icon).

Code: `fieldos_mobile/lib/features/commercial/` (rules in
`commercial_rules.dart`, loading in `commercial_data.dart`, the statement
PDF/CSV and the trace in `commercial_pack.dart`, screens in
`commercial_screens.dart`, `exceptions_screen.dart` and
`subcontractor_portal.dart`). Server: `supabase/migrations/20261110100000_commercial_controls.sql`.

## FOS-201: certifying a subcontractor's work

- A work order has a unit, agreed quantity, rate and budget line. Those are
  the baseline; once any quantity is certified the server refuses changes
  to them ("record a variation instead").
- A subcontractor (or the engineer for them) submits a **claim**: quantity,
  where, note, photos. Claims are insert-only.
- The engineer records a **certificate** against the claim: accepted and
  rejected quantity, a note and photos. The app suggests the split and
  shows previous certificates, the current claim and what is left.
- The same quantity cannot be certified twice. A trigger on
  `work_certifications` locks the work order and refuses a certificate when
  the claim's accepted + rejected would pass its quantity, or the order's
  accepted would pass agreed quantity + approved variations.

## FOS-202: variation register

- `variations` holds origin (claim over order, client instruction, design
  change, site condition, other), owner, evidence, quantity, cost and
  schedule impact, and the work order and budget line it changes.
- `variation_decisions` holds at most one decision per variation, by the
  owner or a project manager. Pending, approved and rejected are kept apart.
- Approval raises the order's current quantity and value and the budget
  line's revised budget. The original baseline stays as it was.

## FOS-203: cost to complete, per budget line

Original budget, approved changes, revised budget, open commitments (PO
value not yet received + work-order value not yet certified), actuals,
estimated remaining, projected final cost and overrun. A receipt or
certificate moves money from commitment to actual, so nothing is counted
twice. Each line drills down to the records behind its numbers.

## FOS-204: exceptions inbox

Raised from the records themselves: work beyond approved scope (variation
waiting), quantity above contract, overdue certification (7 days) and
forecast overrun. Each has an owner, due date, decision and source record.
Most clear when the record is acted on; the rest are resolved in the inbox
with a recorded note (`commercial_exception_actions`, insert-only). A
resolved exception comes back if its numbers change (fingerprint).

## Subcontractor access

Free, claims-only. `join_as_subcontractor(code)` links a signed-in user to
one subcontractor firm. RLS lets them read only their firm's work orders,
claims, certificates and attachments, plus the site name. They skip the
paywall and land on **My work**.

## Demo script (the acceptance cycle)

1. Owner: on a site, add a budget line `PL-01 Plaster`, then a work order
   for the plaster subcontractor: Internal plaster, 100 m² at ₹250.
2. Owner: open the subcontractor, tap the key, share the code.
3. Subcontractor phone: join with the code, claim 120 m² with a photo.
4. Engineer: certify the claim. The app suggests 100 accepted; switch on
   "Send the other 20 to the variation register". The certificate is saved
   and V-1 is raised.
5. Director: Commercial exceptions shows "Work beyond approved scope". Open
   V-1: the forecast impact on PL-01 is shown. Approve it.
6. Engineer: certify the remaining 20 against V-1. The order now shows 120
   of 120 certified; PL-01's revised budget includes the change.
7. Anyone: on the claim, tap Trace to follow claim > certificate >
   variation > decision with the photos. Share the work order statement
   (PDF or CSV) to accounts.

`test/subcontractor_payment_cycle_test.dart` runs this end to end against
a local Supabase stack with three phones.
