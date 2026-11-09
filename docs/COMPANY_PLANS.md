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
with a message to mark a finished site Completed or ask the company owner. The
server does not refuse such a site (an offline phone would be stuck with a site
it could never send); `company_plan_usage` shows any company over its limit.

## Pieces

- `supabase/migrations/20261110000000_company_plans.sql`: table (no app access),
  `my_company_plans()` for phones, `grant_company_plan` / `end_company_plan` /
  `company_plan_covers` / `company_plan_usage` for the service role only.
  Test: `supabase/tests/company_plans_test.sql`.
- `fieldos_mobile/lib/services/company_plan.dart`, used by the subscription gate,
  the paywall, My subscription, new-site checks and the assistant.
- `supabase/functions/ai-assistant`: a company plan also unlocks Ask FieldOS.
- Website: `website/builders.html` ("For builders", no prices, "Book a site
  audit" form via Netlify Forms) and `website/builders-thanks.html`.
