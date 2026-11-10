# Stores, tools and staff salaries

Three things a growing builder runs outside any one site. Home menu >
**Stores and tools** and **Staff salaries** (owners and project managers;
the server enforces the same).

## Stores and transfers

- **Stores**: the yard or godown where material waits before it goes to
  sites. Add as many as you have.
- **Material in**: a load bought into a store, with supplier, quantity, unit
  and rate. A store's stock is valued at the weighted average of what was
  paid.
- **Send to site** (or to another store): the material leaves the store the
  moment it is sent and is **on the way** until the receiving end counts it.
  With no rate entered, it goes at the store's average rate. A store cannot
  send more than it holds.
- **Receive**: the site sees "On the way here" at the top of its Stock tab
  and counts what arrived. Less than was sent is kept as a shortage and
  listed under "Arrived short".
- **Send** from a site: leftover material goes on to another site or back
  to a store, the same way.
- **Correct count**: a loss or a gain at a store after a physical count,
  with a reason (short, more, damaged, theft, expired).
- **Call back**: a transfer still on the way can be cancelled by the sender
  or a manager; the material is back with the sender.

Site stock = GRN receipts + transfers received − material used − transfers
sent. The site's spending on the dashboard includes material it received
from stores (at the move's rate) and gives up what it sent on.

## Tools register

- Each tool gets a tag (`T-001`, `T-002`, ... unless you give one), a kind,
  its worth and the store it is kept at.
- **Hand over** to a person, for a site, with a due-back date (a week by
  default). Overdue tools sort to the top.
- **Take back**: fine, damaged (goes to "In repair", with an amount to
  recover) or lost (stays lost, its worth comes off the total, and the
  amount to recover defaults to its worth).
- "To recover" lists what is owed for damaged and lost tools.

## Staff salaries

For people on a monthly salary (engineers, supervisors, accounts, drivers),
not the daily-wage workers on the wage sheet.

- **Staff**: basic, HRA and other allowance a month, PF and ESI switches,
  professional tax state, UAN, joining date, and the site the salary is
  charged to.
- **Month**: "Make this month's salaries" makes a payslip for every active
  person, with the whole month paid and any advance recovered. Someone who
  joined in the month is paid from the day they joined.
- Open a payslip to change the days paid, the advance to recover or another
  deduction; the figures update as you type.
- The rules:
  - Pay for days paid: each part times days paid over days in the month.
  - PF: 12% employee and 12% company on the basic earned, up to ₹15,000.
  - ESI: when the full monthly salary is ₹21,000 or less, 0.75% employee and
    3.25% company on what was earned, rounded up to the rupee.
  - Professional tax (Telangana and Andhra Pradesh slabs): nil up to
    ₹15,000, ₹150 up to ₹20,000, ₹200 above. Other states: choose "No
    professional tax" for now.
  - Advance recovery never takes more than is owed or more than is left.
- **Payslip** PDF with the company logo and address, shared on WhatsApp.
- **Mark paid**: bank, UPI, cash or cheque. For staff charged to a site, the
  net pay goes into that site's money book as a "Staff salary" expense.
  A paid salary is kept as it was paid.
- The month card shows net to pay, PF and ESI to deposit (both shares),
  professional tax and the cost to the company.

## Data

| Phone (Drift v22) | Server | Notes |
|---|---|---|
| `stores` | `stores` | company-wide, archived not deleted |
| `stock_moves` | `stock_moves` | inward / transfer / adjust; never deleted |
| `tools` | `tools` | condition in_use / repair / retired |
| `tool_issues` | `tool_issues` | issued and lost come from these |
| `staff_members` | `staff_members` | owner / PM only |
| `staff_advances` | `staff_advances` | insert only |
| `payroll_lines` | `payroll_lines` | one per person per month |

Migration: `supabase/migrations/20261110410000_stores_tools_payroll.sql`.

Who can do what on the server:

- Owners and project managers do everything.
- A site's team reads moves into or out of its sites, sends from its site,
  and receives what comes to it. It cannot buy into a store, correct a count,
  call back someone else's transfer, or rewrite a move.
- Every member reads stores and the tools register. The site's team hands
  over and takes back tools for its site, and a damaged return marks the
  tool for repair on the server.
- Salaries are owner and project manager only.

The server stamps who sent, received, issued or made each row; checks that
every store, site, tool and person on a row belongs to its company; keeps
what was sent, from where, at what rate; and refuses changes to a paid
salary or a closed move or issue. A phone retrying the same close changes
nothing instead of failing its sync.

## Tests

- `test/warehouse_test.dart`: average rate, transfer in transit then
  received short, site stock and cost, store limit, call back, count
  corrections, tools issue / overdue / damaged / lost.
- `test/payroll_test.dart`: PF ceiling, ESI limit, PT slabs, days not
  worked, advance caps, month making, joiners, paying into the money book,
  PDF.
- `test/warehouse_screens_test.dart`: store to site end to end, tools, staff
  and month, Telugu on a 320 px phone.
- `test/schema_v22_upgrade_test.dart`: upgrade from v21.
- `test/warehouse_cloud_test.dart`: owner, PM and site engineer phones
  against the local Supabase stack.
