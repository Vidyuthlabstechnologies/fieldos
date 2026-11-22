import { expect, test } from '@playwright/test';
import { buildSchedule, dayNo, forecastFinish, scheduleLinks, todayNo, type Constraint, type Task } from '../src/schedule';

// The phone's test/schedule_rules_test.dart, case for case with the same
// expected dates, so the office and the site draw the same chart.
const now = new Date(2026, 10, 10, 9);
const d = (n: number) => `2026-11-${String(n).padStart(2, '0')}`;
const day = (n: number) => dayNo(d(n));
const t = (id: string, o: { start?: number; due?: number; status?: string; progress?: number } = {}): Task => ({
  id, title: `Task ${id}`, status: o.status ?? 'todo', progress: o.progress ?? 0, priority: 'normal',
  start_date: o.start == null ? null : d(o.start), due_date: o.due == null ? null : d(o.due),
});
const link = (from: string, to: string, cleared = false): Constraint => ({
  id: `c-${from}-${to}`, task_id: to, kind: 'predecessor', link_id: from, cleared_at: cleared ? '2026-11-02T00:00:00Z' : null,
});

test('a late task pushes the ones linked after it, keeping their length', () => {
  const s = buildSchedule([t('a', { start: 5, due: 9 }), t('b', { start: 10, due: 12 }), t('c', { start: 13, due: 14 }), t('x', { start: 10, due: 30 })], [link('a', 'b'), link('b', 'c')], now);
  const r = (id: string) => s.byId.get(id)!;
  expect(r('a').finish).toBe(day(10));
  expect(r('b').start).toBe(day(11));
  expect(r('b').finish).toBe(day(13));
  expect(r('b').pushedBy).toBe('a');
  expect(r('c').start).toBe(day(14));
  expect(r('c').finish).toBe(day(15));
  expect(s.plannedFinish).toBe(day(30));
  expect(s.daysLate).toBe(0);
  expect(r('x').critical).toBe(true);
  expect(r('c').spareDays).toBe(15);
  expect(r('a').critical).toBe(false);
});

test('the chain that sets the finish is the critical path', () => {
  const s = buildSchedule([t('a', { start: 10, due: 12 }), t('b', { start: 13, due: 20 }), t('side', { start: 10, due: 11 }), t('done', { start: 1, due: 3, status: 'done' })], [link('a', 'b')], now);
  expect(s.rows.filter((r) => r.critical).map((r) => r.task.id)).toEqual(['a', 'b']);
  expect(s.byId.get('side')!.spareDays).toBe(9);
  expect(s.byId.get('done')!.critical).toBe(false);
  expect(s.byId.get('done')!.finish).toBe(day(3));
});

test('a slow pace moves the finish, and the site is late by the slip', () => {
  const s = buildSchedule([t('a', { start: 6, due: 15, progress: 25 })], [], now);
  expect(s.byId.get('a')!.finish).toBe(day(25));
  expect(s.daysLate).toBe(10);
});

test('a finished earlier task does not hold anything back', () => {
  const s = buildSchedule([t('a', { start: 1, due: 12, status: 'done' }), t('b', { start: 10, due: 11 })], [link('a', 'b')], now);
  expect(s.byId.get('b')!.start).toBe(day(10));
  expect(s.byId.get('b')!.pushedBy).toBeNull();
});

test('undated tasks are listed apart; removed and broken links are ignored', () => {
  const s = buildSchedule([t('a', { start: 10, due: 11 }), t('b', { due: 12 }), t('n')], [link('a', 'b', true), link('gone', 'b'), link('b', 'b')], now);
  expect(s.unscheduled.map((x) => x.id)).toEqual(['n']);
  expect(s.links).toEqual([]);
  expect(s.byId.get('b')!.start).toBe(day(12));
});

test('loops arriving from sync do not hang the chart', () => {
  expect(scheduleLinks([t('a', { start: 10 }), t('b', { start: 12 })], [link('a', 'b'), link('a', 'b')])).toHaveLength(1);
  const s = buildSchedule([t('a', { start: 10, due: 11 }), t('b', { start: 12, due: 13 })], [link('a', 'b'), link('b', 'a')], now);
  expect(s.rows).toHaveLength(2);
});

test('pace forecast counts today as a working day; days ignore the clock', () => {
  expect(forecastFinish(t('a', { start: 10, progress: 50 }), todayNo(now))).toBe(day(11));
  expect(forecastFinish(t('a', { start: 11, progress: 50 }), todayNo(now))).toBeNull();
  expect(todayNo(new Date(2026, 10, 10, 23, 59))).toBe(day(10));
  expect(todayNo(new Date(2026, 10, 10, 0, 1))).toBe(day(10));
});
