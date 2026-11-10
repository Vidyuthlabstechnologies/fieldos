# Report library

Home menu > **Reports**: 55 ready reports over what the company already
records. Pick the sites (all, or some) and the period (this or last week,
month or financial year, or since the start), see the table on the phone,
and share it as a **PDF** (the company's logo, address, GSTIN, colour and
footer line) or an **Excel** sheet with a total row. Everything is worked out
on the phone, offline.

Registers (tasks, tools, workers, equipment, stock) show how things stand
today whatever period is picked.

Who sees what:

- Money received, client bills and site profit: owners and managers, as on
  the money screens (`canSeeMoneyIn`).
- Store stock value, salaries and sales: owners and project managers
  (`Roles.canApprove`); their data is not even loaded for anyone else.
- Site lists follow `projectsProvider`, so a members-only site someone is
  not on never appears. The sample site is left out once there is a real
  one.

## Progress

- **Daily reports**: Each day's report: people on site, weather and work done.
- **People on site by day**: How many people each site had each day, from the daily reports.
- **Task status**: Every task with its progress, dates and whether it is late. (as of today)
- **Late tasks**: Open tasks past their due date, most late first. (as of today)
- **Tasks finished**: Tasks marked done in the period.
- **Issues register**: Issues raised in the period, with how long each took to fix.
- **Open issues by age**: Issues not yet fixed, oldest first. (as of today)
- **Inspections**: Quality and safety inspections with their results.
- **Documents register**: Drawings and documents on each site, latest version. (as of today)
- **Approvals waiting**: Requests still waiting for a decision, oldest first. (as of today)

## Labour

- **Attendance punches**: Each punch in and out, hours, and whether it was at the site.
- **Punches away from site**: Punches made outside the site boundary, to check.
- **Days worked by worker**: Days marked on the wage sheet for each worker.
- **Wages earned**: Days marked times the daily wage, for each worker.
- **Workers list**: Everyone on the wage sheet, with role, phone and wage. (as of today)

## Material and purchase

- **Material received**: Every delivery (GRN) with supplier and amount.
- **Received by material**: Quantity and amount of each material received, with the average rate.
- **Material used**: Material used on site, day by day.
- **Site stock**: What each site received, got from stores, used, sent on and has left. (as of today)
- **Purchase requests**: Material asked for, and whether it was ordered.
- **Purchase orders**: Every PO with supplier, amount, delivery date and status.
- **Late deliveries**: POs past their delivery date and not yet delivered. (as of today)
- **Purchases by supplier**: Deliveries and orders from each supplier in the period.
- **Supplier invoices**: Invoices entered against POs, with GST.
- **Savings from quotes**: Requests with several supplier quotes: who won and what it saved.

## Stores and tools

- **Store stock and value**: What each store holds and what it is worth at the average rate. (owners and PMs, as of today)
- **Transfers**: Material sent between stores and sites, and what arrived.
- **Arrived short**: Transfers where less arrived than was sent.
- **Tools register**: Every tool, where it is and who has it. (as of today)
- **Tools overdue**: Tools not back by their due date. (as of today)
- **Tools to recover**: What is owed for tools returned damaged or lost. (as of today)

## Money

- **Expenses**: Every payment made, with voucher number, mode and GST.
- **Spending by head**: Total spent under each head (material, labour, transport...).
- **Spending by site**: Total spent on each site.
- **Paid to each party**: Total paid to each person or firm.
- **Cash and bank**: What went out in cash, by bank, UPI or cheque.
- **GST on purchases**: GST inside each payment that carries it, for your accountant.
- **Money received**: Payments received from clients. (owners and managers)
- **Client bills**: Running bills and tax invoices raised, and whether paid. (owners and managers)
- **Site profit**: Billed, received and spent on each site, and what is left. (owners and managers)

## Subcontractors

- **Work orders**: Each work order: agreed, billed and still to bill. (as of today)
- **Subcontractor totals**: Agreed and billed for each subcontractor across sites. (as of today)
- **Variations**: Extra and changed work, its cost and the decision.

## Equipment

- **Equipment register**: Machines on each site, owned or hired, and their rates. (as of today)
- **Equipment hours and cost**: Hours run and money spent on each machine.
- **Hired equipment due back**: Hired machines still on site, by return date, so rent does not run on. (as of today)

## Staff salaries

- **Salary register**: Each payslip in the period: earned, deductions and net. (owners and PMs)
- **PF and ESI to deposit**: Both shares of PF and ESI, and professional tax, month by month. (owners and PMs)
- **Advances still owed**: Salary advances not yet recovered, by person. (owners and PMs, as of today)
- **Staff cost by site**: Salary cost to the company for each site it is charged to. (owners and PMs)

## Sales

- **Sales pipeline**: Open enquiries by stage, with their value. (owners and PMs, as of today)
- **Follow-ups due**: Open enquiries to call today or already late. (owners and PMs, as of today)
- **Won and lost**: Enquiries closed in the period, with the reason for each loss. (owners and PMs)
- **Where enquiries come from**: Enquiries and wins from each source, to see what is working. (owners and PMs)
- **Quotations sent**: Quotations made for enquiries, and their status. (owners and PMs)

## My figures on the dashboard

The top of the Dashboard shows **My figures**: tiles each person picks and
orders for themselves (Choose: tick, drag, Save; kept on the phone per
person and company). There are 17 to choose from, such as spent, received
and billed this month, material received, people-days, wages earned, late
tasks, open issues, late deliveries, approvals waiting, tools overdue,
punches away from site, arrived short, stock in stores, salaries this month,
follow-ups due and open enquiries. Each is worked out from the matching
library report over the sites the person can see, a tile with a problem in
it turns red, and tapping it opens that report. A figure the person may not
see (money received, salaries, sales, store value) is never offered.
Default: spent, received, late tasks, open issues, late deliveries,
approvals waiting.

## Your look on every PDF

Settings > company: the logo (already there), **your line at the foot of
PDFs** (phone, website, registration; up to 120 characters), **your colour**
(ten choices) for the company name and headings, and whether "Made with
FieldOS" is printed. The footer line goes on bills, vouchers, quotations,
payslips, daily reports, client updates, week-close and commercial packs and
the report library. The colour goes on the company name of bills, vouchers,
quotations and payslips, the header band of daily reports and client
updates, and the headings and table heads of library reports.

## Code

- `lib/features/reports/report_library.dart`: the reports (`reportLibrary`),
  `ReportInput` and `loadReportInput`.
- `lib/features/reports/report_output.dart`: PDF and Excel.
- `lib/features/reports/reports_library_screen.dart`: the screens and
  `reportRange`.
- `lib/features/company/branding.dart`: footer text and colour.
- `lib/features/dashboard/my_dashboard.dart`: My figures (`kpiLibrary`).

## Tests

- `test/report_library_test.dart`: every report builds on full and empty
  data, totals, site and period filters, wage and stock figures, salaries,
  who sees what, financial years, PDF and Excel, branding.
- `test/reports_library_screen_test.dart`: search, sites and period on a
  phone; a site engineer's list; Telugu on a 320 px phone.
- `test/my_dashboard_test.dart`: defaults, choice and order per person,
  forbidden figures dropped, a tile turned off on a phone, Telugu at 320 px.
- `test/l10n_indirect_labels_test.dart`: every report title, description,
  column and group has hi, te, ta, kn and mr labels.
