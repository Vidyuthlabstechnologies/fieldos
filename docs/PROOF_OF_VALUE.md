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
