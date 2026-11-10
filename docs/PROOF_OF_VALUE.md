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
