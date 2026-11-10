# Leads and quotes (CRM)

The work before a site exists. Home menu > **Leads and quotes** (owners and
project managers only; the server hides leads from everyone else too).

## What it does

- **Leads**: who asked, phone, work, location, where they came from, their
  budget, notes, and the person following it up. Stages: New, Contacted,
  Site visit, Quoted, Negotiation, then Won or Lost.
- **Follow-ups**: every open lead has a next follow-up day. The list opens
  on "To follow up": late first, then today, then leads with no next step.
  A 9:30 am phone reminder names the leads to call that day (late ones are
  folded into today's).
- **History**: calls, visits, meetings, WhatsApp chats and notes, plus every
  stage change, newest first. Never edited.
- **Quotes**: items with unit, quantity and rate, a flat discount before GST,
  GST (CGST + SGST, or IGST for another state), validity and terms. Numbers
  run per company by month (`Q-2611-007`). **Send PDF** shares the quotation
  on WhatsApp with the company logo and GSTIN, and marks a draft as sent.
  An accepted quote is kept as agreed; a new price is a new version.
- **Won**: makes the site with the client's name, puts the accepted quote's
  items on it as budget lines (`Q-01`, `Q-02`, ...; before GST), and links the
  lead to the site. Converting twice gives the same site.
- **Lost**: needs a reason (quick picks: price too high, went with another
  contractor, project on hold, no response). The pipeline card shows the
  most common reason this month, the open value, value won this month and
  the win rate.

## Data

| Phone (Drift v21) | Server | Notes |
|---|---|---|
| `crm_leads` | `crm_leads` | company-wide; `project_id` once won |
| `crm_activities` | `crm_activities` | insert only |
| `crm_quotes` | `crm_quotes` | `lines` is a JSON array like client bills |

Migration: `supabase/migrations/20261110400000_crm.sql`. Row level security:
owner or project manager of the company for every read and write. The
server stamps `created_by` / `by_user` with the signed-in user, keeps an
accepted quote's price, refuses a lost lead without a reason or deleting a
won lead, checks a quote or history line belongs to its lead's company, and
adds a suffix when two phones offline pick the same quote number. Change
log lines come from `log_crm_sync_change()` (company-level, no project).

## Tests

- `test/crm_test.dart`: totals, numbering, the full enquiry-to-site flow,
  lost reasons and win rate, working order, reminders, mapping, PDF.
- `test/crm_screens_test.dart`: add a lead, log a call, quote editor totals,
  Telugu on a 320 px phone.
- `test/schema_v21_upgrade_test.dart`: upgrade from v16.
- `test/crm_cloud_test.dart`: owner, PM and site engineer phones against the
  local Supabase stack.
