# Schedule (Gantt chart)

Each site: menu > **Schedule (Gantt chart)**. Every task with a start or
due date is a bar; tasks with neither are counted under the chart.

- **Links.** Tap a task > *Add earlier work it waits for* > pick the task
  that must finish first (finish-to-start). A link is stored as a task
  constraint of kind `predecessor` whose `link_id` is the other task, so it
  syncs and shows in the two-week lookahead like any other constraint, and
  clears itself when that task is done. *Remove link* clears it by hand.
  A link that would make a loop is refused on the phone; loops arriving
  from sync are ignored by the chart.
- **Where it is heading.** An open task starts no earlier than the day
  after every unfinished earlier task's projected finish, keeps its planned
  length, and never finishes before its pace forecast (progress since the
  start date) or before today. Done tasks stay where they were planned.
  The thin grey line under a bar is its planned dates when it moved.
- **Critical path** (red): open tasks with no spare days between their
  projected finish and the latest finish that does not move the site's
  last day. The summary shows the planned finish, where the site is heading
  and how many days late.

Rules: `fieldos_mobile/lib/features/schedule/schedule_rules.dart` (pure,
tested in `test/schedule_rules_test.dart`); screen: `gantt_screen.dart`.
No new tables or migrations: the server already accepts `predecessor`
constraints with any `link_id`.

Not yet: start-to-start or lag links, a saved baseline, and Microsoft
Project / Primavera import.
