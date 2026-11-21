import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import { loadRegisters, loadSite, type Site } from './data';
import { siteHref } from './route';
import {
  byRaised,
  currentRevision,
  defectAgeing,
  defectOverdue,
  numbered,
  rfiOverdue,
  submittalOverdue,
  summary,
  type Registers,
} from './rules';
import { day } from './format';
import { label, statusLabel, t } from './strings';
import { MoneyTab } from './Money';

type Load = { state: 'loading' } | { state: 'error' } | { state: 'ready'; site: Site | null; reg: Registers };

const TABS = ['rfis', 'submittals', 'defects', 'drawings', 'money'] as const;
type Tab = (typeof TABS)[number];

export function SitePage({ db, session, id, tab }: { db: SupabaseClient; session: Session; id: string; tab: string }) {
  const [load, setLoad] = useState<Load>({ state: 'loading' });
  const [showClosed, setShowClosed] = useState(false);
  const now = useMemo(() => new Date(), [load]);
  const current: Tab = (TABS as readonly string[]).includes(tab) ? (tab as Tab) : 'rfis';

  const reload = useCallback(() => {
    setLoad({ state: 'loading' });
    Promise.all([loadSite(db, id), loadRegisters(db, id)]).then(
      ([site, reg]) => setLoad({ state: 'ready', site, reg }),
      () => setLoad({ state: 'error' }),
    );
  }, [db, id]);
  useEffect(reload, [reload]);

  return (
    <>
      <header className="bar">
        <a href="#/" data-testid="all-sites">
          ← {t.allSites}
        </a>
        <span className="spacer" />
        <span className="muted small">{session.user.email}</span>
        <button type="button" className="secondary" onClick={() => db.auth.signOut()}>
          {t.signOut}
        </button>
      </header>
      <main className="page">
        {load.state === 'loading' && <p>{t.loading}</p>}
        {load.state === 'error' && (
          <p role="alert">
            {t.loadFailed}{' '}
            <button type="button" className="secondary" onClick={reload}>
              {t.tryAgain}
            </button>
          </p>
        )}
        {load.state === 'ready' && !load.site && <p data-testid="site-not-found">{t.siteNotFound}</p>}
        {load.state === 'ready' && load.site && (
          <SiteBody db={db} site={load.site} reg={load.reg} tab={current} now={now} showClosed={showClosed} setShowClosed={setShowClosed} />
        )}
      </main>
    </>
  );
}

function SiteBody(props: {
  db: SupabaseClient;
  site: Site;
  reg: Registers;
  tab: Tab;
  now: Date;
  showClosed: boolean;
  setShowClosed: (v: boolean) => void;
}) {
  const { db, site, reg, tab, now, showClosed, setShowClosed } = props;
  const s = summary(reg, now);
  const tiles: { tab: Tab; title: string; big: number; lines: [number, string, boolean?][] }[] = [
    { tab: 'rfis', title: t.rfis, big: s.rfisOpen, lines: [[s.rfisOpen, t.open], [s.rfisOverdue, t.overdue, true]] },
    {
      tab: 'submittals',
      title: t.submittals,
      big: s.submittalsWaiting,
      lines: [[s.submittalsWaiting, t.waiting], [s.submittalsOverdue, t.overdue, true], [s.submittalsToRevise, t.toRevise]],
    },
    {
      tab: 'defects',
      title: t.defects,
      big: s.defectsOpen,
      lines: [[s.defectsOpen, t.open], [s.defectsCritical, t.critical, true], [s.defectsOverdue, t.overdue, true]],
    },
    {
      tab: 'drawings',
      title: t.drawings,
      big: s.drawings,
      lines: [[s.drawings, t.onRegister], [s.revisionsPending, t.awaitingApproval]],
    },
  ];

  return (
    <>
      <div className="heading">
        <h1 data-testid="site-name">{site.name}</h1>
        <span className={`status status-${site.status}`}>{statusLabel(site.status)}</span>
        {site.client_name && <span className="muted">{site.client_name}</span>}
      </div>
      <div className="tiles">
        {tiles.map((x) => (
          <a key={x.tab} href={siteHref(site.id, x.tab)} className={`tile${x.tab === tab ? ' on' : ''}`} data-testid={`tile-${x.tab}`}>
            <span className="tile-title">{x.title}</span>
            <ul>
              {x.lines.map(([n, words, warn]) => (
                <li key={words} className={warn && n > 0 ? 'warn' : undefined}>
                  <strong>{n}</strong> {words}
                </li>
              ))}
            </ul>
          </a>
        ))}
      </div>
      <nav className="tabs" aria-label={site.name}>
        {TABS.map((x) => (
          <a key={x} href={siteHref(site.id, x)} aria-current={x === tab ? 'page' : undefined} data-testid={`tab-${x}`}>
            {t[x]}
          </a>
        ))}
        <span className="spacer" />
        {tab !== 'drawings' && tab !== 'money' && (
          <label className="check">
            <input type="checkbox" checked={showClosed} onChange={(e) => setShowClosed(e.target.checked)} data-testid="show-closed" />
            {t.showClosed}
          </label>
        )}
      </nav>
      {tab === 'rfis' && <RfiTable reg={reg} now={now} showClosed={showClosed} />}
      {tab === 'submittals' && <SubmittalTable reg={reg} now={now} showClosed={showClosed} />}
      {tab === 'defects' && <DefectTable reg={reg} now={now} showClosed={showClosed} />}
      {tab === 'drawings' && <DrawingTable reg={reg} />}
      {tab === 'money' && <MoneyTab db={db} site={site} />}
    </>
  );
}

function Table({ head, empty, children, testId }: { head: string[]; empty: string | null; children: ReactNode; testId: string }) {
  if (empty) return <p data-testid={`${testId}-empty`}>{empty}</p>;
  return (
    <table className="sites register" data-testid={testId}>
      <thead>
        <tr>
          {head.map((h) => (
            <th key={h} scope="col">
              {h}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>{children}</tbody>
    </table>
  );
}

function Flag({ on, children }: { on: boolean; children: ReactNode }) {
  return on ? <span className="flag">{children}</span> : null;
}

// Newest first on screen; the numbers still count from the first raised.
function newestFirst<T extends { id: string; created_at: string }>(list: T[]): T[] {
  return byRaised(list).reverse();
}

function RfiTable({ reg, now, showClosed }: { reg: Registers; now: Date; showClosed: boolean }) {
  const no = numbered(reg.rfis, 'RFI');
  const rows = newestFirst(reg.rfis).filter((r) => showClosed || r.status !== 'closed');
  return (
    <Table
      testId="rfis"
      head={[t.colNo, t.colQuestion, t.colAskedOf, t.colDue, t.status, t.colAnswer]}
      empty={reg.rfis.length === 0 ? t.noRfis : null}
    >
      {rows.map((r) => (
        <tr key={r.id} data-testid={`rfi-${r.id}`}>
          <td>{no.get(r.id)}</td>
          <td>{r.question}</td>
          <td>{r.asked_of ?? ''}</td>
          <td>
            {day(r.due_on)} <Flag on={rfiOverdue(r, now)}>{t.overdue}</Flag>
          </td>
          <td>{label(t.itemStatus, r.status)}</td>
          <td>{r.answer ?? ''}</td>
        </tr>
      ))}
    </Table>
  );
}

function SubmittalTable({ reg, now, showClosed }: { reg: Registers; now: Date; showClosed: boolean }) {
  const no = numbered(reg.submittals, 'SUB');
  const done = (s: string) => s === 'approved' || s === 'approved_as_noted';
  const rows = newestFirst(reg.submittals).filter((x) => showClosed || !done(x.status));
  return (
    <Table
      testId="submittals"
      head={[t.colNo, t.colTitle, t.colKind, t.colSpec, t.colFrom, t.colReviewer, t.colRequiredBy, t.colRound, t.status]}
      empty={reg.submittals.length === 0 ? t.noSubmittals : null}
    >
      {rows.map((x) => (
        <tr key={x.id} data-testid={`submittal-${x.id}`}>
          <td>{no.get(x.id)}</td>
          <td>{x.title}</td>
          <td>{label(t.kinds, x.kind)}</td>
          <td>{x.spec_section ?? ''}</td>
          <td>{x.from_party ?? ''}</td>
          <td>{x.reviewer ?? ''}</td>
          <td>
            {day(x.required_by)} <Flag on={submittalOverdue(x, now)}>{t.overdue}</Flag>
          </td>
          <td>{x.round}</td>
          <td>{label(t.itemStatus, x.status)}</td>
        </tr>
      ))}
    </Table>
  );
}

const SEVERITY_ORDER: Record<string, number> = { critical: 0, major: 1, minor: 2 };

function DefectTable({ reg, now, showClosed }: { reg: Registers; now: Date; showClosed: boolean }) {
  const rows = newestFirst(reg.defects)
    .filter((d) => showClosed || d.status !== 'closed')
    .sort((a, b) => (SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9));
  return (
    <Table
      testId="defects"
      head={[t.colDescription, t.colLocation, t.colSeverity, t.colDue, t.status, t.colRaised]}
      empty={reg.defects.length === 0 ? t.noDefects : null}
    >
      {rows.map((d) => (
        <tr key={d.id} data-testid={`defect-${d.id}`}>
          <td>
            {d.description} <Flag on={d.reopen_count > 0}>{t.reopened}</Flag>
          </td>
          <td>{d.location ?? ''}</td>
          <td className={`sev sev-${d.severity}`}>{label(t.severities, d.severity)}</td>
          <td>
            {day(d.due_on)} <Flag on={defectOverdue(d, now)}>{t.overdue}</Flag>
          </td>
          <td>{label(t.itemStatus, d.status)}</td>
          <td>
            {day(d.created_at)} <Flag on={defectAgeing(d, now)}>{t.ageing}</Flag>
          </td>
        </tr>
      ))}
    </Table>
  );
}

function DrawingTable({ reg }: { reg: Registers }) {
  const rows = [...reg.drawings].sort((a, b) => a.number.localeCompare(b.number, undefined, { numeric: true }));
  return (
    <Table
      testId="drawings"
      head={[t.colNumber, t.colTitle, t.colDiscipline, t.colCurrentRev, t.colPending]}
      empty={reg.drawings.length === 0 ? t.noDrawings : null}
    >
      {rows.map((d) => {
        const cur = currentRevision(reg.revisions, d.id);
        const pending = reg.revisions.filter((r) => r.drawing_id === d.id && r.status === 'pending').length;
        return (
          <tr key={d.id} data-testid={`drawing-${d.id}`}>
            <td>{d.number}</td>
            <td>{d.title}</td>
            <td>{label(t.disciplines, d.discipline)}</td>
            <td>{cur ? `${t.rev} ${cur.rev}` : <span className="muted">{t.noApprovedRev}</span>}</td>
            <td>{pending > 0 ? pending : ''}</td>
          </tr>
        );
      })}
    </Table>
  );
}
