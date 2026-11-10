# Daily site close

If a supervisor forgets to update FieldOS, the manager sees **report
missing**, never **zero activity**. An empty attendance register could mean
nobody worked, or nobody sent it; those are very different when wages are
due.

Code: `fieldos_mobile/lib/features/daily/`. Server:
`supabase/migrations/20261110200000_daily_site_close.sql` (app schema v31; built as v19, moved after master's v30).
Policy test: `supabase/tests/daily_close_test.sql`.

## What each person sees

| Who | Where | What |
|---|---|---|
| Supervisor | Home card "Today's report · site", or the site's menu > Today's report | The **Today** checklist: attendance, deliveries, expenses and work done, pulled from what is already recorded. Quiet days: **No deliveries**, **No expenses**, or **Site closed today** (one switch covers everything). **Send today's report** records the day and opens the share sheet with the WhatsApp report, written from the records (nothing typed twice). A one-line "work done" can be typed right there. |
| Supervisor, offline | Today | **Saved on this phone · waiting to sync** until the phone reconnects. |
| Manager / owner | Home card "Daily reports", or Home menu > Daily reports | Every running site: **Submitted at 6:32 pm**, **Site closed**, **Due by 7:00 pm**, **Report not received · last synced Today, 2:10 pm**, or **Report missing** (next morning), plus yesterday's. "Last synced" is the server's own clock for the supervisor's phone (`member_sync_status`), so the manager can tell "forgot" from "saved offline, no signal". Changes still waiting on that phone are counted. |
| Manager | Commercial exceptions inbox | A day still missing at **9 am the next morning** becomes an exception (kind "Daily report missing"), with **Record a follow-up** and **Assign a backup supervisor**. 3 or more misses in 14 days is marked **Repeat** and due today: escalation goes to the manager, not more reminders to everyone. It clears itself when the report is sent. |
| Manager | Today (tune icon) | **Daily report setup**: cutoff time (default 7 pm), site supervisor, backup supervisor with an end date. |

## Rules

- **One reminder**, at the site's cutoff, to the one person expected to send
  it (the backup while covering, else the supervisor; if nobody is named,
  everyone who records on the site). It lists what is missing and opens
  Today. Once a company uses the daily close, the general 6:30 pm "today's
  site report" nudge stops.
- **Backdated entries**: Today can close any of the last 60 days (calendar
  icon). Records keep both dates; Today lists "Added later: work date 10 Nov ·
  entered 11 Nov, 8:05 am by Ravi". A submission made after the day is
  **Submitted late**.
- **Corrections**: **Reopen to correct**, then send again; both stay on
  record. If anything recorded for the day changes after it was sent, Today
  and the board say **Changed after it was sent**. If the week was already
  closed, the weekly close brings the changed item back by itself ("Changed
  after approval"), and Today says the manager will review it.
- **Miss reasons (two-week pilot)**: whenever a report came in late or is
  missing, Today asks once: **Forgot**, **Poor signal**, **Too much work to
  enter**, or **Something else** (with a note). Each needs a different fix:
  a better reminder, offline sending, or less typing.
- **Partial verification** in the weekly close: money for days with no
  submitted daily report is held. The item shows "₹1,600 needs checking: no
  daily report for 10 Nov". Approving it offers **Release ₹X** (the verified
  part goes ahead, recorded against the approver) or **Approve all, with
  this reason** (an override recorded with the approver and reason, and the
  approval note starts "Override:"). "Approve the n with no exceptions" skips
  held items.
- Sites that never used the daily close are not held against anyone: no
  exceptions, misses or held wages before a site's first submission (or
  before its setup was first saved).

## Server

- `site_day_events`: insert-only (no update or delete grant). Kinds:
  submitted, reopened, miss_reason (anyone on the site, as themselves);
  follow_up, partial, override (owner or PM only). The phone's time is kept
  (a report sent offline at 6 pm reads 6 pm); `synced_at` is the server's.
- `site_close_settings`: one row per site; owner or PM only; the supervisor
  and backup must be company members.
- `member_sync_status` + `report_sync_status(company, pending)`: each phone
  stamps its own row after every sync; members read their company's rows.
  Not in the change log (it changes every few minutes).

Production: apply the migration after #118, #121 and #123 (see the issue
assigned to bahumanya). Until it is deployed the app keeps working: the
phones skip what the server doesn't have yet.

## Two-week pilot on one site

1. Owner/PM: open the site > Today's report > tune icon. Set the cutoff
   (e.g. 7 pm) and the supervisor. Tracking starts that day.
2. Supervisor: each evening, open the reminder, fill what's missing or tap
   the "nothing" chips, **Send today's report**, and paste into the site's
   WhatsApp group from the share sheet.
3. Manager: check **Daily reports** each evening and the exceptions inbox
   each morning.
4. After two weeks, count `miss_reason` rows by reason:
   `select reason, count(*) from site_day_events where project_id = '<site>' and kind = 'miss_reason' group by reason;`
   and misses vs. on-time submissions on the board.
