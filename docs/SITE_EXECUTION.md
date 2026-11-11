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
