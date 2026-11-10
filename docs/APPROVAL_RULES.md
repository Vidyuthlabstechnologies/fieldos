# Approval rules: project manager, then owner, by amount

This is part of item 5 of the weekly-close plan (schema v30). The owner sets the rules in
Settings > **Approval rules**. Each of these three kinds of item can have
two amounts:

- purchase requests (the request's estimate);
- expenses;
- purchase orders (the PO's total).

The two amounts are:

- **Project manager approves above (₹)**
- **Owner also approves above (₹)**

A blank box means no approval at that level. A rule covers items recorded
after it was made, so setting one never holds up last month's records.

Rules: `fieldos_mobile/lib/features/approvals/approval_chain.dart`.
Storage: `ApprovalChainDao`.

## How an item moves

An item needs every level whose amount it crosses, lowest first. Each
signature is one insert-only step.

- A **project manager** signs the project manager's level. That means a
  company PM, or a site PM within their site approval limit (see
  `docs/SITE_TEAMS.md`).
- The **owner** signs as owner, which covers the project manager's
  level too.
- One **rejection** at any level stops the item. A rejection needs a
  note. A rejected request is marked rejected, and a rejected PO is
  cancelled.

Where each kind waits:

| Item | Where it waits | What it blocks |
|---|---|---|
| Purchase request | Procure > RFQ shows who it is waiting for and an **Approve** button | **Make PO** |
| Purchase order | Procure > PO shows the status and **Approve** | **Send to supplier** (receiving is still allowed: material arrives anyway) |
| Expense | Weekly close: approving it signs your level. When it still needs the owner, it stays waiting and says so | The weekly-close approval |

Approvals > **Waiting for your approval** lists everything across your
sites that you can sign now, largest first.

## What the server enforces

Migration `supabase/migrations/20261110900000_approval_rules.sql` adds:

- `site_approval_rules`. Company members read it, and only the owner
  adds or changes rules. A rule keeps its company, kind and level.
- `site_approval_steps`. It is insert-only, and the site team reads it.
  The owner's level is signed only by the company owner. The project
  manager's level is signed by anyone `can_approve_on_site` allows for
  the amount. The amount is the record's own: a trigger sets it before
  the check, so a phone can't send a smaller one.
- `approval_chain_complete(...)`, which is used by two triggers:
  - `site_close_reviews` can't approve an expense whose chain is
    incomplete;
  - `purchase_orders` can't be raised from a requisition whose chain is
    incomplete.
- `log_sync_change` now falls back to `company_id` for a row with no
  project, so company-wide rules reach phones through the change log.

## Production

Apply `20261110900000_approval_rules.sql` after
`20261110310000_billing_reconciliation.sql`. If a later migration
redefines `log_sync_change`, it must keep the `company_id` fallback in its
`else` branch.

## Tests

- `test/approval_rules_test.dart` covers:
  - levels, chains and who signs;
  - the weekly close holding a big expense for the owner;
  - a rejected expense staying unapproved.
- `test/approval_rules_cloud_test.dart` runs on three phones against
  local Supabase. It checks that:
  - the rules sync, including a later change;
  - an engineer can't sign;
  - a site PM can't sign the owner's level, or above their limit;
  - the weekly close and a PO from a request are refused until the chain
    is complete;
  - the amounts on the steps are the records' own.
- `test/schema_v30_upgrade_test.dart` covers the upgrade.
