import { useCallback, useEffect, useMemo, useState } from 'react';
import type { Session, SupabaseClient } from '@supabase/supabase-js';
import {
  lastCompany,
  loadCompanies,
  loadSites,
  matchesSearch,
  rememberCompany,
  type Company,
  type Site,
} from './data';
import { roleLabel, statusLabel, t } from './strings';

type Load<T> = { state: 'loading' } | { state: 'error' } | { state: 'ready'; value: T };

export function Sites({ db, session }: { db: SupabaseClient; session: Session }) {
  const [companies, setCompanies] = useState<Load<Company[]>>({ state: 'loading' });
  const [companyId, setCompanyId] = useState<string | null>(null);
  const [sites, setSites] = useState<Load<Site[]>>({ state: 'loading' });
  const [query, setQuery] = useState('');

  const fetchCompanies = useCallback(() => {
    setCompanies({ state: 'loading' });
    loadCompanies(db, session.user.id).then(
      (list) => {
        setCompanies({ state: 'ready', value: list });
        const last = lastCompany();
        setCompanyId(list.find((c) => c.id === last)?.id ?? list[0]?.id ?? null);
      },
      () => setCompanies({ state: 'error' }),
    );
  }, [db, session.user.id]);

  useEffect(fetchCompanies, [fetchCompanies]);

  const fetchSites = useCallback(() => {
    if (!companyId) return;
    setSites({ state: 'loading' });
    loadSites(db, companyId).then(
      (list) => setSites({ state: 'ready', value: list }),
      () => setSites({ state: 'error' }),
    );
  }, [db, companyId]);

  useEffect(fetchSites, [fetchSites]);

  const shown = useMemo(
    () => (sites.state === 'ready' ? sites.value.filter((s) => matchesSearch(s, query)) : []),
    [sites, query],
  );

  const company = companies.state === 'ready' ? companies.value.find((c) => c.id === companyId) : undefined;

  return (
    <>
      <header className="bar">
        <strong>{t.appName}</strong>
        {companies.state === 'ready' && companies.value.length > 1 && (
          <label className="picker">
            <span className="sr-only">{t.company}</span>
            <select
              value={companyId ?? ''}
              onChange={(e) => {
                setCompanyId(e.target.value);
                rememberCompany(e.target.value);
              }}
              data-testid="company-picker"
            >
              {companies.value.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </label>
        )}
        <span className="spacer" />
        <span className="muted small" data-testid="who">
          {session.user.email}
        </span>
        <button type="button" className="secondary" onClick={() => db.auth.signOut()} data-testid="sign-out">
          {t.signOut}
        </button>
      </header>
      <main className="page">
        {companies.state === 'loading' && <p>{t.loading}</p>}
        {companies.state === 'error' && <Retry onRetry={fetchCompanies} />}
        {companies.state === 'ready' && companies.value.length === 0 && <p data-testid="no-company">{t.noCompany}</p>}
        {company && (
          <>
            <div className="heading">
              <h1 data-testid="company-name">{company.name}</h1>
              <span className="chip">{roleLabel(company.role)}</span>
            </div>
            <div className="heading">
              <h2>{t.sites}</h2>
              <input
                type="search"
                placeholder={t.searchSites}
                aria-label={t.searchSites}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                data-testid="site-search"
              />
            </div>
            {sites.state === 'loading' && <p>{t.loading}</p>}
            {sites.state === 'error' && <Retry onRetry={fetchSites} />}
            {sites.state === 'ready' && sites.value.length === 0 && <p data-testid="no-sites">{t.noSites}</p>}
            {sites.state === 'ready' && sites.value.length > 0 && shown.length === 0 && <p>{t.noMatch}</p>}
            {shown.length > 0 && (
              <table className="sites" data-testid="sites">
                <thead>
                  <tr>
                    <th scope="col">{t.sites}</th>
                    <th scope="col">{t.client}</th>
                    <th scope="col">{t.dates}</th>
                    <th scope="col">{t.status}</th>
                  </tr>
                </thead>
                <tbody>
                  {shown.map((s) => (
                    <tr key={s.id} data-testid={`site-${s.id}`}>
                      <td>{s.name}</td>
                      <td>{s.client_name ?? ''}</td>
                      <td>{dates(s)}</td>
                      <td>
                        <span className={`status status-${s.status}`}>{statusLabel(s.status)}</span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </main>
    </>
  );
}

function Retry({ onRetry }: { onRetry: () => void }) {
  return (
    <p role="alert">
      {t.loadFailed}{' '}
      <button type="button" className="secondary" onClick={onRetry}>
        {t.tryAgain}
      </button>
    </p>
  );
}

const fmt = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
function day(d: string | null): string {
  return d ? fmt.format(new Date(d + 'T00:00:00')) : '';
}
function dates(s: Site): string {
  if (!s.start_date && !s.end_date) return '';
  return `${day(s.start_date)} – ${day(s.end_date)}`;
}
