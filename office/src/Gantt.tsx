import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadSchedule, type Site } from './data';
import { day } from './format';
import { buildSchedule, isoOf, todayNo, type Row, type Schedule } from './schedule';
import { label, t } from './strings';

type Load = { state: 'loading' } | { state: 'error' } | { state: 'ready'; s: Schedule; total: number };
type Zoom = 'day' | 'week' | 'month';
const DAY_PX: Record<Zoom, number> = { day: 28, week: 12, month: 4 };
const ROW = 34;
const HEAD = 40;

/** The site's schedule as a Gantt chart, read only: the phone's chart,
 * on a big screen. Tasks are added and linked on the phone. */
export function GanttTab({ db, site }: { db: SupabaseClient; site: Site }) {
  const [load, setLoad] = useState<Load>({ state: 'loading' });
  const [zoom, setZoom] = useState<Zoom>('day');
  const reload = useCallback(() => {
    setLoad({ state: 'loading' });
    loadSchedule(db, site.id).then(
      ({ tasks, constraints }) => setLoad({ state: 'ready', s: buildSchedule(tasks, constraints, new Date()), total: tasks.length }),
      () => setLoad({ state: 'error' }),
    );
  }, [db, site.id]);
  useEffect(reload, [reload]);

  if (load.state === 'loading') return <p>{t.loading}</p>;
  if (load.state === 'error')
    return (
      <p role="alert">
        {t.loadFailed}{' '}
        <button type="button" className="secondary" onClick={reload}>
          {t.tryAgain}
        </button>
      </p>
    );
  const { s, total } = load;
  if (total === 0) return <p data-testid="schedule-empty">{t.noTasks}</p>;

  return (
    <>
      {s.rows.length > 0 ? (
        <>
          <div className="figures" data-testid="schedule-summary">
            <Fig label={t.plannedFinish} value={s.plannedFinish != null ? day(isoOf(s.plannedFinish)) : ''} testId="planned-finish" />
            <Fig label={t.headingFor} value={s.projectedFinish != null ? day(isoOf(s.projectedFinish)) : ''} testId="heading-for" />
            <Fig label={t.daysLateLabel} value={s.daysLate > 0 ? String(s.daysLate) : t.onTime} testId="days-late" warn={s.daysLate > 0} />
            <Fig label={t.criticalTasks} value={String(s.rows.filter((r) => r.critical).length)} testId="critical-count" />
          </div>
          <div className="filters">
            <label>
              <span className="small muted">{t.zoom}</span>
              <select value={zoom} onChange={(e) => setZoom(e.target.value as Zoom)} data-testid="gantt-zoom">
                {(['day', 'week', 'month'] as Zoom[]).map((z) => (
                  <option key={z} value={z}>
                    {label(t.zooms, z)}
                  </option>
                ))}
              </select>
            </label>
            <Legend />
          </div>
          <Chart s={s} dayPx={DAY_PX[zoom]} />
          <TaskTable s={s} />
        </>
      ) : (
        <p data-testid="schedule-undated-only">{t.noDatedTasks}</p>
      )}
      {s.unscheduled.length > 0 && (
        <section aria-label={t.undated} className="grid-gap">
          <h2>{t.undated}</h2>
          <ul className="plain" data-testid="undated">
            {s.unscheduled.map((x) => (
              <li key={x.id}>
                {x.title} <span className="muted small">· {label(t.taskStatus, x.status)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  );
}

function Fig({ label: words, value, testId, warn }: { label: string; value: string; testId: string; warn?: boolean }) {
  return (
    <div className="figure" data-testid={testId}>
      <span className="muted small">{words}</span>
      <strong className={warn ? 'neg' : undefined}>{value}</strong>
    </div>
  );
}

function Legend() {
  return (
    <ul className="legend" aria-label={t.legend}>
      <li><span className="swatch planned" />{t.legendPlanned}</li>
      <li><span className="swatch heading" />{t.legendHeading}</li>
      <li><span className="swatch critical" />{t.legendCritical}</li>
      <li><span className="swatch done" />{t.legendDone}</li>
      <li><span className="swatch today" />{t.legendToday}</li>
    </ul>
  );
}

const monthFmt = new Intl.DateTimeFormat(undefined, { month: 'short', year: 'numeric', timeZone: 'UTC' });
const dayOfMonth = (n: number) => new Date(n * 86_400_000).getUTCDate();
const weekday = (n: number) => (new Date(n * 86_400_000).getUTCDay() + 6) % 7; // Monday 0

function Chart({ s, dayPx }: { s: Schedule; dayPx: number }) {
  const today = todayNo(new Date());
  // A few days either side, and always today, as on the phone.
  const first = Math.min(s.first!, today) - 3;
  const last = Math.max(s.last!, today) + 3;
  const days = last - first + 1;
  const width = days * dayPx;
  const height = HEAD + s.rows.length * ROW;
  const x = (n: number) => (n - first) * dayPx;
  const rowOf = useMemo(() => new Map(s.rows.map((r, i) => [r.task.id, i])), [s]);
  const y = (i: number) => HEAD + i * ROW;
  // Open on today, with a little of the past showing.
  const scroller = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = scroller.current;
    if (el) el.scrollLeft = Math.max(0, x(today) - el.clientWidth / 3);
  }, [dayPx]); // eslint-disable-line react-hooks/exhaustive-deps

  const ticks: { n: number; month: boolean }[] = [];
  for (let n = first; n <= last; n++) {
    const dom = dayOfMonth(n);
    if (dom === 1 || n === first) ticks.push({ n, month: true });
    else if (dayPx >= 20 || (dayPx >= 10 && weekday(n) === 0)) ticks.push({ n, month: false });
  }

  return (
    <div className="gantt" data-testid="gantt">
      <div className="gantt-names" style={{ paddingBlockStart: HEAD }}>
        {s.rows.map((r) => (
          <div key={r.task.id} className={`gantt-name${r.critical ? ' crit' : ''}`} style={{ blockSize: ROW }} title={r.task.title}>
            {r.task.title}
          </div>
        ))}
      </div>
      <div className="gantt-scroll" dir="ltr" ref={scroller} data-testid="gantt-scroll">
        <svg width={width} height={height} role="img" aria-label={t.schedule}>
          {ticks.map(({ n, month }) => (
            <g key={n}>
              <line x1={x(n)} x2={x(n)} y1={month ? 0 : 22} y2={height} className={month ? 'g-month' : 'g-grid'} />
              {month && (
                <text x={x(n) + 4} y={14} className="g-label">
                  {monthFmt.format(new Date(n * 86_400_000))}
                </text>
              )}
              {!month && dayPx >= 10 && (
                <text x={x(n) + dayPx / 2} y={34} className="g-label small" textAnchor="middle">
                  {dayOfMonth(n)}
                </text>
              )}
            </g>
          ))}
          {s.rows.map((r, i) => (
            <Bar key={r.task.id} r={r} x={x} y={y(i)} dayPx={dayPx} />
          ))}
          {s.links.map((l) => {
            const a = s.byId.get(l.from);
            const b = s.byId.get(l.to);
            if (!a || !b) return null;
            const x1 = x(a.finish + 1);
            const y1 = y(rowOf.get(l.from)!) + ROW / 2;
            const x2 = x(b.start);
            const y2 = y(rowOf.get(l.to)!) + ROW / 2;
            const mid = x1 + Math.min(6, Math.max(0, (x2 - x1) / 2));
            return (
              <path
                key={l.id}
                d={`M${x1},${y1} H${mid} V${y2} H${x2 - 1}`}
                className={a.critical && b.critical ? 'g-link crit' : 'g-link'}
                markerEnd="url(#arrow)"
                data-testid={`link-${l.from}-${l.to}`}
              />
            );
          })}
          <defs>
            <marker id="arrow" viewBox="0 0 6 6" refX="5" refY="3" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
              <path d="M0,0 L6,3 L0,6 z" className="g-arrow" />
            </marker>
          </defs>
          <line x1={x(today) + dayPx / 2} x2={x(today) + dayPx / 2} y1={HEAD - 6} y2={height} className="g-today" data-testid="today-line" />
        </svg>
      </div>
    </div>
  );
}

function Bar({ r, x, y, dayPx }: { r: Row; x: (n: number) => number; y: number; dayPx: number }) {
  const pad = 7;
  const h = ROW - pad * 2;
  const kind = r.done ? 'done' : r.critical ? 'critical' : 'heading';
  const moved = r.start !== r.plannedStart || r.finish !== r.plannedFinish;
  const tip = [
    r.task.title,
    `${day(isoOf(r.start))} – ${day(isoOf(r.finish))}`,
    `${t.colProgress}: ${r.task.progress}%`,
    r.done ? t.legendDone : r.critical ? t.legendCritical : `${t.colSpare}: ${r.spareDays}`,
  ].join('\n');
  return (
    <g data-testid={`bar-${r.task.id}`} data-kind={kind} data-start={isoOf(r.start)} data-finish={isoOf(r.finish)}>
      <title>{tip}</title>
      {moved && (
        <rect x={x(r.plannedStart)} y={y + pad - 3} width={(r.plannedFinish - r.plannedStart + 1) * dayPx} height={h + 6} rx={4} className="g-planned" />
      )}
      <rect x={x(r.start)} y={y + pad} width={Math.max(2, (r.finish - r.start + 1) * dayPx)} height={h} rx={4} className={`g-bar ${kind}`} />
      {!r.done && r.task.progress > 0 && (
        <rect
          x={x(r.start)}
          y={y + pad + h - 4}
          width={Math.max(1, ((r.finish - r.start + 1) * dayPx * Math.min(100, r.task.progress)) / 100)}
          height={4}
          rx={2}
          className="g-progress"
        />
      )}
    </g>
  );
}

function TaskTable({ s }: { s: Schedule }) {
  return (
    <table className="sites register" data-testid="schedule-table">
      <thead>
        <tr>
          <th scope="col">{t.colTask}</th>
          <th scope="col">{t.status}</th>
          <th scope="col">{t.colStart}</th>
          <th scope="col">{t.colFinish}</th>
          <th scope="col" className="num">{t.colProgress}</th>
          <th scope="col" className="num">{t.colSpare}</th>
          <th scope="col">{t.pushedByLabel}</th>
        </tr>
      </thead>
      <tbody>
        {s.rows.map((r) => (
          <tr key={r.task.id} data-testid={`task-${r.task.id}`} className={r.done ? 'done-row' : undefined}>
            <td>
              {r.task.title} {r.critical && <span className="flag">{t.critical}</span>}
            </td>
            <td>{label(t.taskStatus, r.task.status)}</td>
            <td>
              {day(isoOf(r.start))}
              {r.start !== r.plannedStart && <span className="muted small"> ({day(isoOf(r.plannedStart))})</span>}
            </td>
            <td>
              {day(isoOf(r.finish))}
              {r.finish !== r.plannedFinish && <span className="muted small"> ({day(isoOf(r.plannedFinish))})</span>}
            </td>
            <td className="num">{r.task.progress}%</td>
            <td className="num">{r.done ? '' : r.spareDays}</td>
            <td>{r.pushedBy ? s.byId.get(r.pushedBy)?.task.title ?? '' : ''}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
