# Multi-site controls

For a company rolling FieldOS out across many sites: a team and roles for
each site, approval limits, sites only their team can see, new sites from a
template, suppliers pasted in with opening balances, and one screen for
every running site.

A company that uses none of this works as before. Every member still sees
every site, and the company role decides everything.

## Site team and roles

Each site > menu > **Site team**. The roster is `project_members` on the
server and `project_members` on the phone (schema v17).

| Site role | On this site |
|---|---|
| owner | everything |
| project_manager | runs the site; approves in the weekly close up to their limit |
| site_engineer | records the day: reports, labour, money, material |
| accounts | sees the money and sends packs to accounts |
| storekeeper | receives material and keeps the stock |
| viewer | sees the site, changes nothing |

Who can change the team:

- The company's owners and managers can change anything.
- The site's own project manager can add and change other people. They
  can't give anyone the owner role, change an owner's row, change their
  own row, or remove themselves.

The server enforces the same rules through the `project_members` policies
in `20261110210000_site_roles.sql`. The phone mirrors them in
`lib/auth/site_roles.dart` (`SiteAccessFor`, `TeamRules`).

People are picked from the company's accounts, so adding someone needs
Team & sync.

## Approval limits

A site project manager can have a limit in rupees. In the weekly close,
they approve an item up to that amount. Anything bigger is approved by the
company owner, or by a manager who has no limit. The "approve all clean
items" button skips items over the limit.

The server checks the limit too (`can_approve_on_site`). For expenses and
deliveries, it takes the amount from the record itself, not from what the
phone sends (trigger `site_close_reviews_true_amount`). Wages are worked
out on the phone, so their amount is taken as sent.

## Members-only sites

On the Site team screen, a company owner or manager can switch on **Only
this team sees the site**. The server then stops returning the site and its
records to anyone who is not on its team. The company's owners and
managers still see it.

A phone that had the site before it was hidden also stops showing it,
because `projectsProvider` filters through `visibleSiteIds`. The records
already on that phone stay in its database until the app is reinstalled.

The site viewer role is enforced on the phone. On the server, writes still
follow the company role.

## New site from a template

Home > New project > **Start from**: pick an existing site. You can copy
any of these:

- the task list, with titles and priority (progress, dates and assignees
  are not copied);
- active workers and their wages;
- estimate items and rates (measurements are not copied);
- the site team, approval limits and the members-only setting.

The geofence radius is always copied, but the location is not.

Nothing that happened on the old site comes across: no reports,
attendance, money, material or photos. All of it is written in one
transaction (`lib/features/project/site_template.dart`).

## Bulk import

- Workers: Workers > **Add many** (one per line: name, skill, phone, wage).
  This existed before this change.
- Suppliers with opening balances: Procure > Suppliers > **Paste a list**.
  Put one supplier per line: name, phone, GSTIN, and what you owe them
  today. Tabs from Excel, semicolons and commas all work. A comma-grouped
  amount such as "1,25,000" stays one amount.
  - An amount you owe the supplier can be written plain or marked "Cr", as
    Tally does.
  - Money the supplier holds of yours is marked "advance", "Dr" or a minus
    sign.
  - A name the company already has is skipped.
  - Code: `lib/features/procurement/supplier_import.dart`.

## All sites (portfolio)

Home > menu > **All sites**. It lists every running site, with the ones
that need someone first. For each site it shows:

- days this week without a daily report (Monday to yesterday, not
  Sundays);
- weekly close items waiting and sent back, whether this week is closed,
  and whether last week was left open;
- approvals waiting more than 2 days;
- wages due this week and what the site owes suppliers;
- what clients still have to pay and the retention they hold. Only owners
  and managers see these two lines.

Code: `lib/features/portfolio/`.

## Production

Apply migration `supabase/migrations/20261110210000_site_roles.sql` after
`20261110030000_weekly_close.sql` and the commercial-controls migration
(v16).

## Tests

- `test/site_teams_test.dart` covers roles and limits, team rules,
  members-only visibility, templates, supplier import and the portfolio.
- `test/site_roles_cloud_test.dart` runs three phones against local
  Supabase. It checks that:
  - a hidden site really is hidden;
  - a site PM's limit holds, even when the phone sends a false amount;
  - the roster rules hold.
