# Free supplier and client portals

Suppliers and a site's client use FieldOS free, like subcontractors. They
are not company members, nothing of the company is synced to their phones,
and every screen is one server call that returns only what that party may
see (`supabase/migrations/20261110440000_supplier_client_portals.sql`).

## The builder's side (owner or PM)

| Where | What |
|---|---|
| Supplier statement, app bar | **App access for the supplier**: shows and shares the supplier's code. |
| Site, More menu | **Share with the client**: shows and shares the site's client code. |
| Compare quotes, app bar | **Ask for a price in the app**: tick suppliers; those who joined see the request. |
| Procurement, PO tile | "on the way in TS09 AB 1234 since 10 Nov" once the supplier says so; **Receive** stays. |

Codes are made once per supplier or site and stay the same. Only an owner
or PM of the company can make one.

## The supplier's app

Join from **Supplier or client? Join free with the builder's code** (company
setup or the paywall). Two tabs:

- **Price requests**: the requests they were invited to, with their own
  price. They can send or change a price while the request is open and
  their price is not decided. The price lands on the builder's Compare
  quotes as a received quote, through normal sync.
- **Orders**: POs given to them. **On the way** records the vehicle and a
  note; the PO moves to `acknowledged`, and the builder's phone pulls
  `dispatched_on`, `dispatch_vehicle` and `supplier_note`.

They never see other suppliers' prices, costs, sites, or any company table.

## The client's app

**My site**: progress (jobs done of total), billed, paid and balance, the
last 20 confirmed daily reports with up to 4 photos each (signed links,
an hour each, readable only by that site's client), bills and payments.
Drafts, costs, suppliers and other sites are never shown.

## Routing

`Roles.supplier` and `Roles.client` are routed before the subscription gate
in `app.dart`, to `SupplierHomeScreen` and `ClientHomeScreen`. Their
company is not linked for sync, so the sync engine never runs for them.

## Tests

- `fieldos_mobile/test/portals_cloud_test.dart` (local Supabase stack):
  codes, join, invite, quote, award, dispatch, client data, photo access,
  outsiders refused.
- `fieldos_mobile/test/portal_screens_test.dart`: the screens with the
  server faked, and Telugu at 320 px.

## Fix found on the way

`is_company_owner_or_pm()` returned NULL for someone with no role, so any
guard written `if not is_company_owner_or_pm(..)` let outsiders through.
`20261110445000_owner_or_pm_never_null.sql` makes it always true or false.
This also closes the same hole in `subcontractor_access_code()`.
