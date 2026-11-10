# Proof of value: cash book, pilot scorecard, RERA pack, material check, entry history

These features turn a pilot into numbers from the customer's own site. The
plan behind them is the memo "Roles and what builders will pay for", and
the build checklist is issue #134.

## Cash book (Drift v36, `20261111100000_site_cash_book.sql`)

Site > More > **Cash book**.

- **Give cash**, **Take back** and **Count** are for the company's owners
  and managers, the site's project manager and the site's **accounts**
  person (`is_site_cash_keeper` on the server, `keepsSiteCash` on the phone).
- What the holder spent is not typed again. It is their own **cash**
  expenses on the site in the money book (`recorded_by` = the holder, mode
  cash or empty, not cancelled), from the day they were first given cash.
- A **count** records the cash found in their hand. Below the book is
  **short** (unexplained cash), above it is **extra**. The book then carries
  on from what was found, so one shortfall is never counted twice.
- Cash expenses with no bill photo or file are flagged **No bill attached**.
- The holder sees only their own book (row-level security). Entries are
  never edited: a mistake is cancelled with a reason and stays in the book,
  struck through. A cancelled entry can't come back.

Code: `lib/features/money/cash_book.dart` (the arithmetic) and
`cash_book_screen.dart`. Tests: `test/cash_book_test.dart` and
`supabase/tests/cash_book_test.sql`.

## Pilot scorecard (no schema change)

Site > More > **Pilot scorecard** (owners and managers). Pick the day the
pilot started; it is kept on the phone (`pilot_start:<projectId>`).

Three columns: **Week 1 (baseline)**, **Days 8 to 30**, **Days 31 to 60**,
each cut off at today. Each measure says whether it got better or worse
against week 1. Share PDF makes a one-page A4 in the company's look.

| Measure | From |
|---|---|
| Days with a daily report | a daily report or a sent day close, of the days due (Sundays and days marked closed left out) |
| Daily reports sent the same day | the report written on the day it covers |
| Cash short at counts | cash book counts below the book |
| Cash spent with no bill | the holders' cash expenses with no bill attached |
| Expenses with a bill attached | by rupees, every mode |
| Deliveries with a challan photo | receipts with a slip (opening stock left out) |
| Labour marked inside the site fence | punches with a GPS fix |
| Budget overruns flagged | `budget_overrun` approvals raised |
| Days from bill to payment | payments put against a bill, by the payment date |
| Office time saved (estimate) | the time-saved card's fixed minutes per record |

Everything but office time is a count of what was recorded, so the owner
can check any figure against the site's own entries. Code:
`lib/features/reports/pilot_scorecard.dart`; tests:
`test/pilot_scorecard_test.dart`.

## RERA quarterly progress pack (Drift v37, `20261111110000_floor_progress.sql`)

Site menu: **RERA quarterly report**. Every registered project in Telangana
uploads a quarterly progress report to TS-RERA within 15 days of the
quarter's end. The pack builds the progress part from what the site
already records.

- **Floors.** "Add a block" adds Ground and floors 1 to N. Tap a floor to
  set its stage (excavation to complete); the stage suggests a % that can
  be changed. Each update is a new row (`site_floor_progress`, insert-only,
  schema v37), so last quarter's figures print again exactly as they were.
- **The PDF** (pick the quarter, then "Make the progress PDF"): each floor
  at the start and end of the quarter, block and overall %; the quarter's
  confirmed daily reports; up to 12 site photos spread over the quarter;
  and a checklist of what to attach before uploading (Forms 1, 2, 3 and the
  booking register). It says plainly that the architect certifies the
  stage of completion.
- **Reminders.** Owners of sites with a RERA number saved get a reminder on
  the 1st after a quarter ends and on the 10th (5 days before it is due).
- **Who can do what.** Anyone recording on the site can update floors, as
  themselves; a site viewer only reads (enforced by the server policy). The
  owner or project manager saves the RERA number.

The pack is the progress section only. It does not file anything with
RERA and does not replace the architect's, engineer's or CA's forms.
