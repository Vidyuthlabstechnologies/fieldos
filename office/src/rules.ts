// The site register rules, the same as the phone app's
// (fieldos_mobile/lib/features/execution/execution_rules.dart). Keep the two
// in step: a number or an "overdue" here must match what the site sees.

export type Rfi = {
  id: string;
  question: string;
  asked_of: string | null;
  due_on: string | null;
  answer: string | null;
  answered_at: string | null;
  status: string;
  created_at: string;
};

export type Submittal = {
  id: string;
  title: string;
  kind: string;
  spec_section: string | null;
  from_party: string | null;
  reviewer: string | null;
  required_by: string | null;
  round: number;
  status: string;
  decision_note: string | null;
  decided_at: string | null;
  created_at: string;
};

export type Defect = {
  id: string;
  location: string | null;
  description: string;
  severity: string;
  due_on: string | null;
  status: string;
  reopen_count: number;
  created_at: string;
};

export type Drawing = {
  id: string;
  number: string;
  title: string;
  discipline: string;
  created_at: string;
};

export type Revision = {
  id: string;
  drawing_id: string;
  rev: string;
  status: string;
  note: string | null;
  decided_at: string | null;
  created_at: string;
};

export type Registers = {
  rfis: Rfi[];
  submittals: Submittal[];
  defects: Defect[];
  drawings: Drawing[];
  revisions: Revision[];
};

/** Days a defect may stay open before it counts as ageing. */
export const defectAgeingDays = 7;

/** "2026-11-15" as a local day at midnight, or null. */
export function parseDay(d: string | null | undefined): Date | null {
  if (!d) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(d);
  if (!m) return null;
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
}

function startOfDay(now: Date): Date {
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

function before(d: string | null, now: Date): boolean {
  const day = parseDay(d);
  return day !== null && day < startOfDay(now);
}

/** Oldest first, the order the numbers count in. */
export function byRaised<T extends { id: string; created_at: string }>(list: T[]): T[] {
  return [...list].sort((a, b) => a.created_at.localeCompare(b.created_at) || a.id.localeCompare(b.id));
}

/** "RFI-3", "SUB-3": by the order raised. */
export function numbered<T extends { id: string; created_at: string }>(list: T[], prefix: string): Map<string, string> {
  return new Map(byRaised(list).map((x, i) => [x.id, `${prefix}-${i + 1}`]));
}

export function rfiOverdue(r: Rfi, now: Date): boolean {
  return r.status === 'open' && before(r.due_on, now);
}

/** Waiting for review past the day it was needed. */
export function submittalOverdue(s: Submittal, now: Date): boolean {
  return s.status === 'submitted' && before(s.required_by, now);
}

/** Approved, or approved as noted: work may go ahead. */
export function submittalCleared(s: Submittal): boolean {
  return s.status === 'approved' || s.status === 'approved_as_noted';
}

export function defectOverdue(d: Defect, now: Date): boolean {
  return d.status !== 'closed' && before(d.due_on, now);
}

export function defectAgeing(d: Defect, now: Date): boolean {
  return d.status !== 'closed' && (now.getTime() - new Date(d.created_at).getTime()) / 86_400_000 >= defectAgeingDays;
}

/** The revision the site builds to: the approved one decided last. */
export function currentRevision(revisions: Revision[], drawingId: string): Revision | null {
  let best: Revision | null = null;
  for (const r of revisions) {
    if (r.drawing_id !== drawingId || r.status !== 'approved') continue;
    const at = r.decided_at ?? r.created_at;
    if (!best || new Date(at) > new Date(best.decided_at ?? best.created_at)) best = r;
  }
  return best;
}

export type Summary = {
  rfisOpen: number;
  rfisOverdue: number;
  submittalsWaiting: number;
  submittalsOverdue: number;
  submittalsToRevise: number;
  defectsOpen: number;
  defectsCritical: number;
  defectsOverdue: number;
  drawings: number;
  revisionsPending: number;
};

export function summary(r: Registers, now: Date): Summary {
  const openDefects = r.defects.filter((d) => d.status !== 'closed');
  return {
    rfisOpen: r.rfis.filter((x) => x.status === 'open').length,
    rfisOverdue: r.rfis.filter((x) => rfiOverdue(x, now)).length,
    submittalsWaiting: r.submittals.filter((x) => x.status === 'submitted').length,
    submittalsOverdue: r.submittals.filter((x) => submittalOverdue(x, now)).length,
    submittalsToRevise: r.submittals.filter((x) => x.status === 'revise_resubmit' || x.status === 'rejected').length,
    defectsOpen: openDefects.length,
    defectsCritical: openDefects.filter((d) => d.severity === 'critical').length,
    defectsOverdue: openDefects.filter((d) => defectOverdue(d, now)).length,
    drawings: r.drawings.length,
    revisionsPending: r.revisions.filter((x) => x.status === 'pending').length,
  };
}
