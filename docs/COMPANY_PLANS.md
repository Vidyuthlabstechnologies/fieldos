# Company plans (builder firms)

FieldOS has two ways to pay:

| | Who | How it is paid | Where it is switched on |
|---|---|---|---|
| Store plan | Small contractors, one person at a time | ₹999/month or ₹10,999/year per person, Google Play / App Store via RevenueCat | The store |
| Company plan | Builder firms | Yearly, on a GST invoice from ML Dynamic Solutions, by bank transfer | The FieldOS team, in Supabase, after the invoice is paid |

Company plans: **Pilot** (60 days, 1 site), **Site Pro** (up to 3 active sites),
**Business** (up to 10), **Enterprise** (agreed limit, or none). Every plan covers
every person in the company. Prices are in the sales plan, never in the app or on
the website.

## Store rules (do not break these)

- The Android and iOS apps never show a company plan's price, and never link or
  point to a way to buy one (no website link, no "contact sales" button). The
  paywall only says "Your company has a FieldOS plan? Sign in to my company".
  Tests in `fieldos_mobile/test/paywall_screen_test.dart` check the card.
- This is allowed as an enterprise service sold to organisations for their staff
  (Apple 3.1.3(c)); people only get in to something already paid for elsewhere.
- The ₹999 store plan stays on sale in the app, unchanged.

## Switching a plan on (after the invoice is paid)

In the Supabase SQL editor (it runs as the service role), usually by the owner's
email, which works before or after their company is on the cloud:

```sql
select grant_company_plan(
  p_plan        => 'site_pro',            -- pilot | site_pro | business | enterprise
  p_ends_on     => '2027-11-30',          -- last day covered (India time)
  p_owner_email => 'owner@firm.example',  -- the email they sign in to Team & sync with
  p_invoice_ref => 'MLD/26-27/014'
);
```

- Site limit defaults by plan (pilot 1, site_pro 3, business 10, enterprise none).
  Pass `p_site_limit => 25` for an Enterprise deal with a limit, or more sites on
  any plan. `p_starts_on` defaults to today; set it for a renewal paid early.
- Or pass `p_company_id` instead of the email (find it in `company_plan_usage` or
  `companies`).
- A renewal or upgrade is a new row; when several cover today, the biggest site
  limit and latest end date win.
- To end a plan early: `select end_company_plan('<plan id>');`
- To see every plan, its company, active sites and people:
  `select * from company_plan_usage;` A company over its site limit shows there.

The owner's email must be confirmed (Google and Apple sign-ins always are).

## What the customer does

1. **Owner**: installs FieldOS, signs in, and on the paywall taps **Sign in to my
   company**, then signs in to Team & sync with the email on the invoice. FieldOS
   opens. They create their company and put it on the cloud in Team & sync; the
   plan attaches to it by itself.
2. **Everyone else**: installs FieldOS, taps **Sign in to my company** on the
   paywall, signs in and joins with the company's join code. No store payment.

My subscription shows the plan, its end date and "N of M active sites in use".

## Active sites and the limit

An active site is any project not marked Completed (planning, active and on hold
all count, so pausing sites can't stretch the limit). The app refuses a new
site, reopening a completed one, or the assistant creating one past the limit,
with a message to mark a finished site Completed or ask the company owner. That
is the quick check, from the sites this phone knows.

The server enforces the limit too, across **all** of the company's sites
(`supabase/migrations/20261114130000_site_limit_enforced.sql`, trigger
`projects_site_limit`): when a company plan with a site limit covers today, a new
active project, or one moving into active (reopened, or moved to the company), is
refused once the company already has that many active sites. The error is
SQLSTATE `P0001` with a message starting `site_limit_reached` (for example
`site_limit_reached: limit 3, active 3`). Never refused: changes to a site that
was already active (so a company over its limit, say after moving to a smaller
plan, can still edit, pause and finish its sites), completing a site, and a
replayed insert or upsert of a site already on the server. No plan, or an
unlimited one, means no limit.

A phone that made a site offline and sends it past the limit (a second phone
took the last place) gets that error from sync. The sync engine treats it as a
permanent refusal, not a network problem: the change is parked at once (not
retried five times) and Team & sync shows the site-limit message. Once a site is
marked Completed or the plan grows, **Retry failed** sends it. The site stays on
that phone meanwhile. `company_plan_usage` still shows any company over its limit.

## Offline

A phone on a company plan stays fully usable offline for up to **7 days after
the last time the server answered** (`my_company_plans`), and never past the
plan's last day. After that it opens **read-only** until it reaches the server
again: every screen can be viewed, nothing can be changed, and a banner on every
screen says "Offline for over 7 days. Connect to the internet to keep making
changes. You can still view everything." (or that the plan has ended). The app
checks again on resume and every minute while read-only; the first good answer
restores normal rules (a plan: full use; no plan: the paywall).

- Read-only is enforced in one place, the database (`lib/data/write_guard.dart`,
  a drift `QueryInterceptor`): every insert, update and delete is refused with
  `ReadOnlyModeException`, which `friendlyError` turns into the banner's words.
  Still allowed: the settings table (sync cursor, plan answer, cloud session) and
  everything the sync engine does (pulls, sending changes saved earlier, its
  outbox bookkeeping, live updates), so the phone can catch up.
- The 7 days are measured against the phone's clock from the time of the last
  good answer. A clock set back before that answer, or before the latest time the
  phone has seen since (more than 10 minutes, to allow network time corrections),
  counts as expired: read-only. A clock set forward only ends the 7 days early.
- A phone that remembered a plan from before this rule (no answer time kept) gets
  7 days from its first check after the update.
- The per-person store subscription is unchanged (3 days offline past its paid-up
  date, then the paywall).

## Pieces

- `supabase/migrations/20261111130000_company_plans.sql`: table (no app access),
  `my_company_plans()` for phones, `grant_company_plan` / `end_company_plan` /
  `company_plan_covers` / `company_plan_usage` for the service role only.
  `supabase/migrations/20261114130000_site_limit_enforced.sql`: the server's
  site limit. Test: `supabase/tests/company_plans_test.sql`.
- `fieldos_mobile/lib/data/write_guard.dart`: read-only mode. Tests:
  `test/read_only_mode_test.dart`, `test/company_plan_test.dart`,
  `test/site_limit_cloud_test.dart` (local Supabase stack).
- `fieldos_mobile/lib/services/company_plan.dart`, used by the subscription gate,
  the paywall, My subscription, new-site checks and the assistant.
- `supabase/functions/ai-assistant`: a company plan also unlocks Ask FieldOS.
- Website: `website/builders.html` ("For builders", no prices, "Book a site
  audit" form via Netlify Forms) and `website/builders-thanks.html`.
