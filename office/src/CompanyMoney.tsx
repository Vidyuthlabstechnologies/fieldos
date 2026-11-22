import { useCallback, useEffect, useMemo, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadMoney, type Site } from './data';
import { money } from './market';
import { isoDay, moneySummary, type SiteMoney } from './money';
import { moneySheets } from './moneyExport';
import { siteHref } from './route';
import { t } from './strings';
import { downloadXlsx, fileName } from './xlsx';

type Load = { state: 'loading' } | { state: 'error' } | { state: 'ready'; m: SiteMoney };

/** Every site's cash position at a glance. Shown only to the company's owner
 * and project managers, who the server lets read every site's money in. */
export function CompanyMoney({ db, companyName, sites }: { db: SupabaseClient; companyName: string; sites: Site[] }) {
  const [load, setLoad] = useState<Load>({ state: 'loading' });
  const ids = useMemo(() => sites.map((s) => s.id), [sites]);
  const reload = useCallback(() => {
    setLoad({ state: 'loading' });
    loadMoney(db, ids, true).then(
      (m) => setLoad({ state: 'ready', m }),
      () => setLoad({ state: 'error' }),
    );
  }, [db, ids]);
  useEffect(reload, [reload]);

  if (sites.length === 0) return null;
  return (
    <section className="grid-gap" aria-label={t.moneyAcrossSites}>
      <div className="heading">
        <h2>{t.moneyAcrossSites}</h2>
        <span className="spacer" />
        {load.state === 'ready' && (
          <button
            type="button"
            className="secondary"
            data-testid="company-export"
            onClick={() => downloadXlsx(fileName(companyName, t.money, isoDay(new Date())), moneySheets(load.m, sites))}
          >
            {t.exportAllExcel}
          </button>
        )}
      </div>
      {load.state === 'loading' && <p>{t.loading}</p>}
      {load.state === 'error' && (
        <p role="alert">
          {t.loadFailed}{' '}
          <button type="button" className="secondary" onClick={reload}>
            {t.tryAgain}
          </button>
        </p>
      )}
      {load.state === 'ready' && <MoneyBySite m={load.m} sites={sites} />}
    </section>
  );
}

function MoneyBySite({ m, sites }: { m: SiteMoney; sites: Site[] }) {
  const rows = sites.map((s) => {
    const one: SiteMoney = {
      expenses: m.expenses.filter((e) => e.project_id === s.id),
      invoices: m.invoices.filter((x) => x.project_id === s.id),
      in: m.in && {
        payments: m.in.payments.filter((p) => p.project_id === s.id),
        bills: m.in.bills.filter((b) => b.project_id === s.id),
        allocations: m.in.allocations,
      },
    };
    return { site: s, sum: moneySummary(one) };
  });
  const total = moneySummary(m);
  return (
    <table className="sites" data-testid="company-money">
      <thead>
        <tr>
          <th scope="col">{t.sites}</th>
          <th scope="col" className="num">{t.received}</th>
          <th scope="col" className="num">{t.spent}</th>
          <th scope="col" className="num">{t.balance}</th>
          <th scope="col" className="num">{t.dueFromClient}</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(({ site, sum }) => (
          <tr key={site.id} data-testid={`money-site-${site.id}`}>
            <td>
              <a href={siteHref(site.id, 'money')}>{site.name}</a>
            </td>
            <td className="num">{money(sum.received ?? 0)}</td>
            <td className="num">{money(sum.spent)}</td>
            <td className={`num${(sum.balance ?? 0) < 0 ? ' neg' : ''}`}>{money(sum.balance ?? 0)}</td>
            <td className="num">{money(sum.dueFromClient ?? 0)}</td>
          </tr>
        ))}
      </tbody>
      {rows.length > 1 && (
        <tfoot>
          <tr data-testid="money-all-sites">
            <th scope="row">{t.allSites}</th>
            <td className="num"><strong>{money(total.received ?? 0)}</strong></td>
            <td className="num"><strong>{money(total.spent)}</strong></td>
            <td className={`num${(total.balance ?? 0) < 0 ? ' neg' : ''}`}><strong>{money(total.balance ?? 0)}</strong></td>
            <td className="num"><strong>{money(total.dueFromClient ?? 0)}</strong></td>
          </tr>
        </tfoot>
      )}
    </table>
  );
}
