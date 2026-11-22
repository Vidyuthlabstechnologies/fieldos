// The site schedule as a Gantt chart, ported from the phone's
// schedule_rules.dart (and forecastFinish from task_plan.dart): each dated
// task as a bar, "earlier work" links (finish-to-start) where a late task
// pushes the ones after it, and the critical path, the chain with no spare
// days. tests/schedule.spec.ts runs the phone's own test cases with the same
// expected dates; change both together.
//
// Days are whole calendar days, held as day numbers (days since 1970-01-01)
// so no time zone or daylight-saving hour can move a bar.

export type Task = {
  id: string;
  title: string;
  status: string;
  progress: number;
  priority: string;
  start_date: string | null;
  due_date: string | null;
  assignee_id?: string | null;
};

export type Constraint = {
  id: string;
  task_id: string;
  kind: string;
  link_id: string | null;
  cleared_at: string | null;
};

export type Link = { id: string; from: string; to: string };

const DAY = 86_400_000;

/** "2026-11-10" (or a timestamp's date part) as a day number. */
export function dayNo(d: string): number {
  const [y, m, dd] = d.slice(0, 10).split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, dd) / DAY);
}

/** A local Date's calendar day as a day number. */
export const todayNo = (now: Date) => Math.round(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / DAY);

/** A day number back to "2026-11-10". */
export function isoOf(n: number): string {
  return new Date(n * DAY).toISOString().slice(0, 10);
}

const isOpen = (t: Task) => t.status !== 'done';

/** When the task finishes at the pace logged so far: the days since its
 * start stretched to 100%. Null without a start date or progress, or done. */
export function forecastFinish(t: Task, today: number): number | null {
  if (!isOpen(t) || !t.start_date || t.progress <= 0) return null;
  const start = dayNo(t.start_date);
  if (today < start) return null;
  // Today counts as a working day, so 50% on day one forecasts two days.
  const elapsed = today - start + 1;
  return start + Math.ceil((elapsed * 100) / t.progress) - 1;
}

/** Links still in force: predecessor constraints pointing at another task
 * of the site, not removed by hand, one per pair. */
export function scheduleLinks(tasks: Task[], constraints: Constraint[]): Link[] {
  const ids = new Set(tasks.map((t) => t.id));
  const seen = new Set<string>();
  const out: Link[] = [];
  for (const c of constraints) {
    if (c.kind !== 'predecessor' || c.cleared_at != null || c.link_id == null || c.link_id === c.task_id) continue;
    if (!ids.has(c.link_id) || !ids.has(c.task_id)) continue;
    const key = `${c.link_id}>${c.task_id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ id: c.id, from: c.link_id, to: c.task_id });
  }
  return out;
}

export type Row = {
  task: Task;
  plannedStart: number;
  plannedFinish: number;
  /** Where it is heading: moved by unfinished earlier work, a slow pace, or
   * because it is still open past its due date. */
  start: number;
  finish: number;
  pushedBy: string | null;
  spareDays: number;
  critical: boolean;
  done: boolean;
};

export type Schedule = {
  rows: Row[];
  unscheduled: Task[];
  links: Link[];
  byId: Map<string, Row>;
  first: number | null;
  last: number | null;
  plannedFinish: number | null;
  projectedFinish: number | null;
  daysLate: number;
};

/** Lays the site's tasks out on the calendar as of [now]; see the phone's
 * buildSchedule for the reasoning, which this follows step by step. */
export function buildSchedule(tasks: Task[], constraints: Constraint[], now: Date): Schedule {
  const today = todayNo(now);
  const dated: Task[] = [];
  const unscheduled: Task[] = [];
  for (const t of tasks) (t.start_date == null && t.due_date == null ? unscheduled : dated).push(t);
  const links = scheduleLinks(dated, constraints);
  const preds = new Map<string, string[]>();
  const succs = new Map<string, string[]>();
  for (const l of links) {
    preds.set(l.to, [...(preds.get(l.to) ?? []), l.from]);
    succs.set(l.from, [...(succs.get(l.from) ?? []), l.to]);
  }

  // Kahn's order; whatever is left in a loop goes last, its loop links
  // ignored (the phone refuses new ones, but rows can arrive from sync).
  const indegree = new Map(dated.map((t) => [t.id, (preds.get(t.id) ?? []).length]));
  const queue = dated.filter((t) => indegree.get(t.id) === 0).map((t) => t.id);
  const order: string[] = [];
  while (queue.length) {
    const id = queue.shift()!;
    order.push(id);
    for (const s of succs.get(id) ?? []) {
      indegree.set(s, indegree.get(s)! - 1);
      if (indegree.get(s) === 0) queue.push(s);
    }
  }
  const placed = new Set(order);
  for (const t of dated) if (!placed.has(t.id)) order.push(t.id);

  const taskById = new Map(dated.map((t) => [t.id, t]));
  const out = new Map<string, Row>();
  for (const id of order) {
    const t = taskById.get(id)!;
    const ps = dayNo(t.start_date ?? t.due_date!);
    const pf = Math.max(ps, dayNo(t.due_date ?? t.start_date!));
    const base = { task: t, plannedStart: ps, plannedFinish: pf, spareDays: 0, critical: false };
    if (t.status === 'done') {
      out.set(id, { ...base, start: ps, finish: pf, pushedBy: null, done: true });
      continue;
    }
    let start = ps;
    let pushedBy: string | null = null;
    for (const p of preds.get(id) ?? []) {
      const before = out.get(p);
      // Not placed yet means a loop: that link is ignored.
      if (!before || before.done) continue;
      if (before.finish + 1 > start) {
        start = before.finish + 1;
        pushedBy = p;
      }
    }
    let finish = start + (pf - ps);
    const pace = forecastFinish(t, today);
    if (pace != null && pace > finish) finish = pace;
    if (finish < today) finish = today;
    out.set(id, { ...base, start, finish, pushedBy, done: false });
  }

  if (out.size) {
    const end = Math.max(...[...out.values()].map((r) => r.finish));
    const latestFinish = new Map<string, number>();
    for (const id of [...order].reverse()) {
      const r = out.get(id)!;
      let lf = end;
      for (const s of succs.get(id) ?? []) {
        const next = out.get(s)!;
        const lfs = latestFinish.get(s);
        if (lfs == null || next.done) continue;
        const before = lfs - (next.finish - next.start) - 1;
        if (before < lf) lf = before;
      }
      latestFinish.set(id, lf);
      if (!r.done) {
        r.spareDays = Math.max(0, lf - r.finish);
        r.critical = r.spareDays === 0;
      }
    }
  }

  const rows = [...out.values()].sort((a, b) => a.start - b.start || a.finish - b.finish);
  const min = (xs: number[]) => (xs.length ? Math.min(...xs) : null);
  const max = (xs: number[]) => (xs.length ? Math.max(...xs) : null);
  const plannedFinish = max(rows.map((r) => r.plannedFinish));
  const projectedFinish = max(rows.map((r) => r.finish));
  return {
    rows,
    unscheduled,
    links,
    byId: new Map(rows.map((r) => [r.task.id, r])),
    first: min(rows.map((r) => Math.min(r.plannedStart, r.start))),
    last: max(rows.map((r) => Math.max(r.plannedFinish, r.finish))),
    plannedFinish,
    projectedFinish,
    daysLate: plannedFinish != null && projectedFinish != null ? Math.max(0, projectedFinish - plannedFinish) : 0,
  };
}
