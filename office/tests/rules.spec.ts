import { expect, test } from '@playwright/test';
import {
  currentRevision,
  defectAgeing,
  defectOverdue,
  numbered,
  parseDay,
  rfiOverdue,
  submittalCleared,
  submittalOverdue,
  summary,
  type Defect,
  type Revision,
  type Rfi,
  type Submittal,
} from '../src/rules';

// These rules mirror the phone app's execution_rules.dart, so the office and
// the site agree on numbers and on what is overdue.
const now = new Date(2026, 10, 15, 10, 0); // 15 Nov 2026, 10:00 local

const rfi = (o: Partial<Rfi>): Rfi => ({
  id: 'r', question: 'q', asked_of: null, due_on: null, answer: null, answered_at: null, status: 'open',
  created_at: '2026-11-01T00:00:00Z', ...o,
});
const sub = (o: Partial<Submittal>): Submittal => ({
  id: 's', title: 't', kind: 'product_data', spec_section: null, from_party: null, reviewer: null, required_by: null,
  round: 1, status: 'submitted', decision_note: null, decided_at: null, created_at: '2026-11-01T00:00:00Z', ...o,
});
const defect = (o: Partial<Defect>): Defect => ({
  id: 'd', location: null, description: 'x', severity: 'minor', due_on: null, status: 'open', reopen_count: 0,
  created_at: '2026-11-14T00:00:00Z', ...o,
});
const rev = (o: Partial<Revision>): Revision => ({
  id: 'v', drawing_id: 'D', rev: 'A', status: 'approved', note: null, decided_at: null,
  created_at: '2026-11-01T00:00:00Z', ...o,
});

test('days parse as local days, bad ones as nothing', () => {
  expect(parseDay('2026-11-15')?.getDate()).toBe(15);
  expect(parseDay('2026-11-15T23:00:00Z')?.getMonth()).toBe(10);
  expect(parseDay('')).toBeNull();
  expect(parseDay('soon')).toBeNull();
});

test('numbers count by the order raised, whatever order rows arrive in', () => {
  const list = [
    rfi({ id: 'b', created_at: '2026-11-03T00:00:00Z' }),
    rfi({ id: 'a', created_at: '2026-11-02T00:00:00Z' }),
    rfi({ id: 'c', created_at: '2026-11-03T00:00:00Z' }),
  ];
  const no = numbered(list, 'RFI');
  expect([no.get('a'), no.get('b'), no.get('c')]).toEqual(['RFI-1', 'RFI-2', 'RFI-3']);
});

test('an RFI is overdue only while open and past its day', () => {
  expect(rfiOverdue(rfi({ due_on: '2026-11-14' }), now)).toBe(true);
  expect(rfiOverdue(rfi({ due_on: '2026-11-15' }), now)).toBe(false); // due today is not late
  expect(rfiOverdue(rfi({ due_on: '2026-11-14', status: 'answered' }), now)).toBe(false);
  expect(rfiOverdue(rfi({ due_on: null }), now)).toBe(false);
});

test('a submittal is overdue only while waiting for review', () => {
  expect(submittalOverdue(sub({ required_by: '2026-11-10' }), now)).toBe(true);
  expect(submittalOverdue(sub({ required_by: '2026-11-10', status: 'revise_resubmit' }), now)).toBe(false);
  expect(submittalCleared(sub({ status: 'approved_as_noted' }))).toBe(true);
  expect(submittalCleared(sub({ status: 'rejected' }))).toBe(false);
});

test('defects: overdue and ageing stop once closed', () => {
  expect(defectOverdue(defect({ due_on: '2026-11-01', status: 'fixed' }), now)).toBe(true);
  expect(defectOverdue(defect({ due_on: '2026-11-01', status: 'closed' }), now)).toBe(false);
  expect(defectAgeing(defect({ created_at: '2026-11-07T00:00:00Z' }), now)).toBe(true);
  expect(defectAgeing(defect({ created_at: '2026-11-14T00:00:00Z' }), now)).toBe(false);
  expect(defectAgeing(defect({ created_at: '2026-11-01T00:00:00Z', status: 'closed' }), now)).toBe(false);
});

test('the current revision is the approved one decided last, never a pending one', () => {
  const revs = [
    rev({ id: 'A', rev: 'A', decided_at: '2026-11-02T00:00:00Z' }),
    rev({ id: 'B', rev: 'B', decided_at: '2026-11-05T00:00:00Z' }),
    rev({ id: 'C', rev: 'C', status: 'pending', created_at: '2026-11-09T00:00:00Z' }),
    rev({ id: 'X', drawing_id: 'other', decided_at: '2026-11-10T00:00:00Z' }),
  ];
  expect(currentRevision(revs, 'D')?.rev).toBe('B');
  expect(currentRevision([revs[2]], 'D')).toBeNull();
});

test('the site summary counts what needs attention', () => {
  const s = summary(
    {
      rfis: [rfi({ id: '1', due_on: '2026-11-01' }), rfi({ id: '2' }), rfi({ id: '3', status: 'closed' })],
      submittals: [sub({ id: '1', required_by: '2026-11-01' }), sub({ id: '2', status: 'revise_resubmit' })],
      defects: [defect({ id: '1', severity: 'critical' }), defect({ id: '2', status: 'closed', severity: 'critical' })],
      drawings: [{ id: 'D', number: 'A-101', title: 'Plan', discipline: 'architectural', created_at: '' }],
      revisions: [rev({ status: 'pending' })],
    },
    now,
  );
  expect(s).toEqual({
    rfisOpen: 2, rfisOverdue: 1, submittalsWaiting: 1, submittalsOverdue: 1, submittalsToRevise: 1,
    defectsOpen: 1, defectsCritical: 1, defectsOverdue: 0, drawings: 1, revisionsPending: 1,
  });
});
