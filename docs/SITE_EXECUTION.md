# Site execution (FOS-205 to FOS-209)

What has to be true before work starts, what the site builds to, how quality
is closed out, and when a unit can be handed over. Every rule the phone
applies, the server applies again, so nobody can skip a step by going round
the app.

## Where it is

- Each site: menu > **Lookahead, drawings, quality and handover** (tabs:
  two-week lookahead, drawings, RFIs, quality, handover).
- Home > menu > **Site execution across sites**: the portfolio report, with
  **Company standards** (rule icon) and **Share as CSV**.

Code: `fieldos_mobile/lib/features/execution/` (rules in
`execution_rules.dart`, loading in `execution_data.dart`, screens in
`execution_screens.dart` and `execution_portfolio_screen.dart`); phone
records in `lib/data/site_execution_dao.dart`; sync mapping in
`lib/sync/site_execution_sync.dart`. Phone schema v40. Server:
`supabase/migrations/20261112100000_site_execution.sql`.

## FOS-205: two-week lookahead with constraints

- The lookahead lists every task not done whose start (or due) date falls
  in the next 14 days, late ones included, earliest first.
- A task is **ready** only when nothing it waits for is still open. A
  constraint is material, drawing, RFI answer, hold point, labour,
  equipment, permit, earlier work or other, with an optional need-by date.
- Constraints entered by hand are cleared by hand, with a note (for example
  the GRN number). Raising an RFI or a hold point for a task adds a linked
  constraint that clears itself when the RFI is answered or the hold point
  is released; a constraint linked to a drawing clears when it has an
  approved revision.
- A constraint past its need-by date shows red and counts in the report.

## FOS-206: drawing register and RFIs

- A drawing has a number (unique on the site, any case), title and
  discipline. Revisions are uploaded as a photo or PDF and start
  **waiting for approval**.
- Only the owner or a project manager approves or rejects a revision. The
  site sees only the **latest approved** revision; older approved ones are
  marked superseded and stay in the register. A revision's file, drawing
  and number can never be changed on the server.
- An RFI has the question, who it is asked of, an optional answer-by date,
  task, drawing and photos. It is answered, then closed. Overdue RFIs count
  in the report.

## FOS-207: hold points and defects

- A hold point stops a task until it is inspected. Only the owner or a
  project manager releases it (or records it as not released), with a note
  and photos.
- A defect has a description, severity, place, optional unit and fix-by
  date, and photos. It is marked **fixed** only with a photo of the fix, and
  is **checked by someone other than the fixer**: accepted (closed) or
  reopened, which counts the reopen. The server refuses a close by the
  fixer.
- Defects open seven days or more count as ageing.

## FOS-208: handover by unit, floor and zone

- Units are flats, villas or zones with an optional block and floor, shown
  grouped on the handover board.
- A unit can be handed over only when every defect in it is closed, every
  hold point in it released and every checklist line done. The phone shows
  what is left; the server refuses the handover otherwise, and refuses any
  checklist change afterwards. Only the owner or a project manager hands
  over.

## FOS-209: standards and portfolio reporting

- **Company standards**: the standard hold points and the handover
  checklist. Set by the owner or a project manager, read by every member. A
  new unit can start from the checklist; the standard hold points can be
  added at any place on a site in one step.
- **Portfolio**: the same counts for every site (tasks in the next two
  weeks and blocked, constraints past need-by, open and overdue RFIs,
  drawings to approve, hold points not released, open and ageing defects,
  units, ready and handed over). Sites that need attention come first.
  Share as CSV.

## Server rules (site_execution_guard)

- Who-did-it columns (`raised_by`, `answered_by`, `decided_by`,
  `fixed_by`, `closed_by`, `handed_over_by`, `done_by`, ...) must be the
  signed-in user.
- Approving a revision, releasing a hold point and handing over need
  `is_project_owner_or_pm`; company standards need
  `is_company_owner_or_pm`.
- Who raised, added or uploaded a record never changes, and a decision's
  who-column (fixer, checker, approver, answerer, ticker, hander-over)
  changes only with the decision itself. So a fixer cannot rename the fixer
  and then close their own defect.
- Photos are evidence: added as the signed-in user, never edited after.
- Records cannot move to another site.
- Everything else is open to anyone with access to the site
  (`has_project_access`).

## Demo script

1. Owner: Home > Site execution across sites > Company standards. Add
   the handover line "Keys and manuals".
2. Engineer: on a site with a task starting in the next two weeks, open the
   lookahead and raise an RFI for it ("Beam B12 depth: 450 or 600?"). Add a
   hold point "Reinforcement check before pour" for the same task. The task
   shows "Waiting on 2".
3. Engineer: Drawings > Add drawing S-12, upload R0. It shows "Not for
   construction".
4. Project manager (own phone): record the RFI answer, approve R0, release
   the hold point. The task turns "Ready to start".
5. Engineer: Handover > Add unit "Flat 304" with the company checklist;
   Quality > Raise a defect in it with a photo; mark it fixed with a photo.
6. Project manager: the unit cannot be handed over yet. Accept the fix, tick
   the checklist, hand over to the buyer.
7. Owner: the portfolio shows the site, and Share as CSV sends the report.

`fieldos_mobile/test/site_execution_cycle_test.dart` runs the two-phone
version of this against a local Supabase stack, and checks that the server
refuses each step the phone would refuse.

## Pins and markup on drawings

The drawing register's pin icon opens the site's current (approved)
revision on screen: pinch to zoom, **Pin** to tap a spot and raise a
defect or an RFI there, or leave a note, and **Draw** to mark it up with a
finger (red or blue) and save the markup with a line of text. PDFs show a
page at a time, rendered once by the phone's own PDF engine (`printing`
package) and kept as a PNG beside the app's files.

- A pin's place is a fraction of the page (0..1), so it lands in the same
  spot on every screen and zoom. Pins of earlier revisions still show on
  the current one.
- A defect pin is coloured by its defect (open red, fixed amber, closed
  green); an RFI pin by its RFI (open amber, answered/closed green).
- Pins are never deleted, only removed: by whoever placed them, the owner
  or a project manager. The server checks the same and refuses any other
  change to a pin.

Code: `fieldos_mobile/lib/features/execution/drawing_sheet_screen.dart`,
DAO `addPin` / `removePin`; phone table `drawing_pins` (schema v42);
server `supabase/migrations/20261114220000_drawing_pins.sql`
(`site_drawing_pins`, synced by the site-execution mapper).

## Submittals

The Submittals tab (last tab, so older tab indices stay put) is the register
of shop drawings, product data, samples, mock-ups and method statements sent
to the architect or consultant. Each one is numbered `SUB-n` in the order
raised, shows who it is from and who reviews it, and is marked late when it
is still waiting past its "needed by" day.

- Raising one with a task adds a material constraint to that task ("Approval
  of ..."), linked to the submittal. The lookahead shows the task as waiting
  until the submittal is approved or approved as noted.
- Only the owner or a project manager records the review: approved, approved
  as noted, revise and resubmit, or rejected. Anything other than a plain
  approval needs the reviewer's words.
- Revise and resubmit or rejected can be sent again: the round goes up, the
  last review moves to the history (`round|status|decided by|yyyy-mm-dd|note`),
  and it waits for a new review.

Server rules (`site_submittals_guard`, migration `20261114230000_submittals`):
raised as yourself, starting submitted at round 1 with no history; site and
raiser never change; a review only by a manager, as themselves, once per
round; a resubmit only from revise/rejected, one round up, the decision
cleared and the history grown; the history is append-only.

Tests: `test/submittals_test.dart` (rules and the tab on a small phone in
Hindi) and `test/submittals_cycle_test.dart` (two phones against the local
stack).

## Pre-construction (2026-11-25)

Site menu > **Approvals and drawings (pre-construction)**. Three tabs:

- **Approvals**: GHMC, HMDA, municipality, Fire NOC, pollution, electricity,
  water, RERA, airport and other clearances. Each has a status (not
  started, preparing, applied, query raised, resubmitted, approved,
  rejected), whose court the ball is in (us, consultant, authority,
  client), dates, an optional end date for NOCs, and a history that only
  grows. Open approvals untouched for 7 days show as stuck; the longest
  wait is named as the bottleneck. A closed approval is never reopened.
- **Drawing log**: each drawing's revisions in order (Rev 1, Rev 2, GFC).
  A drawing is Good for Construction once its revision labelled GFC is
  approved.
- **Liaison time and cost** (owner and project managers only, enforced in
  RLS): who went to which office, how long, what it cost.

The project's phase (pre-project, execution, post-project) follows its
stage: planning, running or on hold, handed over. Server:
`supabase/migrations/20261125100000_pre_construction.sql`. Phone schema v45.

## Stage checklists and on-site verification (2026-11-25)

- **Stages**: Footings, Plinth beam, Columns (8 steps), First and Second slab, Dressing
  (at least one day). Tasks tab, "Add stage checklist": each step becomes a task titled
  "Columns: Casting". See `activity_templates.dart`.
- **No 100% without being there**: those tasks carry `verify_required`. "Verify on site"
  records the phone's position (`site_task_checks`, insert-only) and is refused when the
  phone is outside the site's radius (150 m when the site sets none). Owners and project
  managers are exempt. Server: `tasks_verify_guard` (migration 20261125120000). A daily
  report that takes such a task to 100% keeps it at 99% until it is verified.
- **Client view**: each stage shows as a milestone (steps done of total), migration
  20261125140000. Labour-only contracts: record the client's steel and cement as stock
  with "Supplied by the client" (counts in the stock, costs nothing).

## Money visibility (2026-11-25)

- Four expense heads: Material, Equipment, Labour, Others; tea, food and the like are
  informal spend inside Others and shown separately (`expense_heads.dart`).
- Server (migration 20261125130000): a site's owner, project managers and accounts read
  every expense; everyone else only the entries they recorded. Wage rates can be set only
  by those roles. Money received was already owners and project managers only.
- Known gap: `workers.daily_wage` is still readable by every site member at the API level
  (phones pull whole rows). The phone hides wages from other roles; the column privilege
  follows once builds older than 1.8 are retired.
- Value engineering (project menu, money roles only): work value done against spend,
  spend per day, spend-ahead alert, delay days and their cost (`value_engineering.dart`).
