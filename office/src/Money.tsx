import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { loadMoney, seesMoneyIn, type Site } from './data';
import { day } from './format';
import { money } from './market';
import {
  billPaid,
  byCategory,
  categoriesUsed,
  dayOf,
  filterExpenses,
  filterPayments,
  isoDay,
  moneySummary,
  NO_FILTER,
  periodRange,
  PERIODS,
  totalReceived,
  totalSpent,
  voucherLabel,
  type MoneyFilter,
  type Period,
  type SiteMoney,
} from './money';
import { billKindLabel, modeLabel, moneySheets } from './moneyExport';
import { label, t } from './strings';
import { downloadXlsx, fileName } from './xlsx';

type Load = { state: 'loading' } | { state: 'error' } | { state: 'ready'; m: SiteMoney };
type Part = 'spent' | 'received' | 'bills' | 'invoices';

/** One site's money, as much of it as this person may see. */
export function MoneyTab({ db, site }: { db: SupabaseClient; site: Site }) {
  const [load, setLoad] = useState<Load>({ state: 'loading' });
  const [part, setPart] = useState<Part>('spent');
  const [filter, setFilter] = useState<MoneyFilter>(NO_FILTER);
  const now = useMemo(() => new Date(), [load]);

  const reload = useCallback(() => {
    setLoad({ state: 'loading' });
    seesMoneyIn(db, site.id)
      .then((withIn) => loadMoney(db, [site.id], withIn))
      .then(
        (m) => setLoad({ state: 'ready', m }),
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

  const m = load.m;
  const shown = narrowed(m, filter, now);
  const s = moneySummary(m);
  const parts: [Part, string][] = [
    ['spent', t.spent],
    ...(m.in ? ([['received', t.received], ['bills', t.clientBills]] as [Part, string][]) : []),
    ['invoices', t.supplierInvoices],
  ];
  const at = parts.some(([p]) => p === part) ? part : 'spent';

  return (
    <>
      <div className="figures" data-testid="money-figures">
        {m.in && <Figure label={t.received} value={s.received!} testId="fig-received" />}
        <Figure label={t.spent} value={s.spent} testId="fig-spent" />
        {m.in && <Figure label={t.balance} value={s.balance!} testId="fig-balance" warn={s.balance! < 0} />}
        {m.in && <Figure label={t.dueFromClient} value={s.dueFromClient!} testId="fig-due" />}
        <Figure label={t.supplierInvoices} value={s.supplierInvoices} testId="fig-invoices" />
      </div>
      {!m.in && (
        <p className="muted small" data-testid="money-in-hidden">
          {t.moneyInHidden}
        </p>
      )}
      <nav className="tabs sub" aria-label={t.money}>
        {parts.map(([p, words]) => (
          <button
            key={p}
            type="button"
            className="tab"
            aria-pressed={p === at}
            onClick={() => setPart(p)}
            data-testid={`money-${p}`}
          >
            {words}
          </button>
        ))}
        <span className="spacer" />
        <button
          type="button"
          className="secondary"
          data-testid="money-export"
          onClick={() => downloadXlsx(fileName(site.name, t.money, isoDay(now)), moneySheets(shown, [site]))}
        >
          {t.exportExcel}
        </button>
      </nav>
      <Filters m={m} filter={filter} setFilter={setFilter} part={at} />
      {at === 'spent' && <SpentTable m={m} shown={shown} />}
      {at === 'received' && m.in && <ReceivedTable m={m} shown={shown} />}
      {at === 'bills' && m.in && <BillsTable m={m} shown={shown} />}
      {at === 'invoices' && <InvoicesTable m={m} shown={shown} />}
    </>
  );
}

/** What the filters leave of the site's money; the Excel file holds the same. */
export function narrowed(m: SiteMoney, f: MoneyFilter, now: Date): SiteMoney {
  const r = periodRange(f, now);
  const inR = (d: string) => !r || (d >= r[0] && d < r[1]);
  const bills = m.in ? m.in.bills.filter((b) => inR(b.bill_date)) : [];
  return {
    expenses: filterExpenses(m.expenses, f, now),
    invoices: m.invoices.filter((x) => inR(x.invoice_date) && (f.showCancelled || !x.voided)),
    in: m.in && {
      payments: filterPayments(m.in.payments, f, now),
      bills,
      // Payments matched to a bill count against it whenever they came in.
      allocations: m.in.allocations.filter((a) => bills.some((b) => b.id === a.bill_id)),
    },
  };
}

function Figure({ label: words, value, testId, warn }: { label: string; value: number; testId: string; warn?: boolean }) {
  return (
    <div className="figure" data-testid={testId}>
      <span className="muted small">{words}</span>
      <strong className={warn ? 'neg' : undefined}>{money(value)}</strong>
    </div>
  );
}

function Filters(props: { m: SiteMoney; filter: MoneyFilter; setFilter: (f: MoneyFilter) => void; part: Part }) {
  const { m, filter, setFilter, part } = props;
  const set = (o: Partial<MoneyFilter>) => setFilter({ ...filter, ...o });
  return (
    <div className="filters">
      <label>
        <span className="small muted">{t.period}</span>
        <select value={filter.period} onChange={(e) => set({ period: e.target.value as Period })} data-testid="money-period">
          {PERIODS.map((p) => (
            <option key={p} value={p}>
              {label(t.periods, p)}
            </option>
          ))}
        </select>
      </label>
      {filter.period === 'custom' && (
        <>
          <label>
            <span className="small muted">{t.fromDay}</span>
            <input type="date" value={filter.from ?? ''} onChange={(e) => set({ from: e.target.value })} data-testid="money-from" />
          </label>
          <label>
            <span className="small muted">{t.toDay}</span>
            <input type="date" value={filter.to ?? ''} onChange={(e) => set({ to: e.target.value })} data-testid="money-to" />
          </label>
        </>
      )}
      {part === 'spent' && (
        <label>
          <span className="small muted">{t.colCategory}</span>
          <select
            value={filter.category ?? ''}
            onChange={(e) => set({ category: e.target.value || null })}
            data-testid="money-category"
          >
            <option value="">{t.allCategories}</option>
            {categoriesUsed(m.expenses).map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
      )}
      {(part === 'spent' || part === 'received') && (
        <label className="grow">
          <span className="small muted">{t.searchMoney}</span>
          <input type="search" value={filter.query} onChange={(e) => set({ query: e.target.value })} data-testid="money-search" />
        </label>
      )}
      <label className="check">
        <input
          type="checkbox"
          checked={filter.showCancelled}
          onChange={(e) => set({ showCancelled: e.target.checked })}
          data-testid="money-show-cancelled"
        />
        {t.showCancelled}
      </label>
    </div>
  );
}

function Table({ head, children, testId, foot }: { head: string[]; children: ReactNode; testId: string; foot?: ReactNode }) {
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
      {foot}
    </table>
  );
}

function Total({ span, value, count, testId }: { span: number; value: number; count: number; testId: string }) {
  return (
    <tfoot>
      <tr>
        <th scope="row" colSpan={span}>
          {t.filteredTotal} · {count} {t.entries}
        </th>
        <td className="num" data-testid={testId}>
          <strong>{money(value)}</strong>
        </td>
        <td />
      </tr>
    </tfoot>
  );
}

const Void = ({ on, reason }: { on: boolean; reason: string | null }) =>
  on ? (
    <span className="flag" title={reason ?? undefined}>
      {t.cancelled}
    </span>
  ) : null;

function SpentTable({ m, shown }: { m: SiteMoney; shown: SiteMoney }) {
  if (m.expenses.length === 0) return <p data-testid="spent-empty">{t.noExpenses}</p>;
  if (shown.expenses.length === 0) return <p data-testid="spent-none">{t.noMoneyMatch}</p>;
  const shares = byCategory(shown.expenses);
  return (
    <>
      <section className="shares" aria-label={t.byCategory} data-testid="by-category">
        {shares.map((x) => (
          <div key={x.category} className="share">
            <span>{x.category}</span>
            <span className="meter" aria-hidden="true">
              <span style={{ width: `${Math.max(2, Math.round(x.share * 100))}%` }} />
            </span>
            <span className="num">
              {money(x.amount)} <span className="muted small">{Math.round(x.share * 100)}%</span>
            </span>
          </div>
        ))}
      </section>
      <Table
        testId="spent"
        head={[t.colVoucher, t.colDate, t.colCategory, t.colPaidTo, t.colMode, t.colNote, t.colAmount, '']}
        foot={<Total span={6} value={totalSpent(shown.expenses)} count={shown.expenses.filter((e) => !e.voided).length} testId="spent-total" />}
      >
        {shown.expenses.map((e) => (
          <tr key={e.id} className={e.voided ? 'voided' : undefined} data-testid={`expense-${e.id}`}>
            <td>{voucherLabel(e.voucher_no)}</td>
            <td>{day(dayOf(e.incurred_on))}</td>
            <td>{e.category}</td>
            <td>{e.paid_to ?? ''}</td>
            <td>{modeLabel(e.mode)}</td>
            <td>{e.note ?? ''}</td>
            <td className="num">{money(e.amount)}</td>
            <td>
              <Void on={e.voided} reason={e.void_reason} />
            </td>
          </tr>
        ))}
      </Table>
    </>
  );
}

function ReceivedTable({ m, shown }: { m: SiteMoney; shown: SiteMoney }) {
  if (m.in!.payments.length === 0) return <p data-testid="received-empty">{t.noPayments}</p>;
  const rows = shown.in!.payments;
  if (rows.length === 0) return <p>{t.noMoneyMatch}</p>;
  return (
    <Table
      testId="received"
      head={[t.colDate, t.colReceivedFrom, t.colMode, t.colNote, t.colAmount, '']}
      foot={<Total span={4} value={totalReceived(rows)} count={rows.filter((p) => !p.voided).length} testId="received-total" />}
    >
      {rows.map((p) => (
        <tr key={p.id} className={p.voided ? 'voided' : undefined} data-testid={`payment-${p.id}`}>
          <td>{day(dayOf(p.received_on))}</td>
          <td>{p.from_party}</td>
          <td>{modeLabel(p.mode)}</td>
          <td>{p.note ?? ''}</td>
          <td className="num">{money(p.amount)}</td>
          <td>
            <Void on={p.voided} reason={p.void_reason} />
          </td>
        </tr>
      ))}
    </Table>
  );
}

function BillsTable({ m, shown }: { m: SiteMoney; shown: SiteMoney }) {
  if (m.in!.bills.length === 0) return <p data-testid="bills-empty">{t.noBills}</p>;
  const rows = [...shown.in!.bills].sort((a, b) => b.bill_date.localeCompare(a.bill_date));
  if (rows.length === 0) return <p>{t.noMoneyMatch}</p>;
  return (
    <Table testId="bills" head={[t.colBillNo, t.colKind, t.colDate, t.colClient, t.colGross, t.colNet, t.colPaid, t.colAmountDue, t.status]}>
      {rows.map((b) => {
        const p = billPaid(b, m.in!.allocations);
        return (
          <tr key={b.id} data-testid={`bill-${b.id}`}>
            <td>{b.bill_number}</td>
            <td>{billKindLabel(b.kind)}</td>
            <td>{day(b.bill_date)}</td>
            <td>{b.client_name}</td>
            <td className="num">{money(b.gross)}</td>
            <td className="num">{money(b.net_payable)}</td>
            <td className="num">{money(p.paid)}</td>
            <td className="num">{p.due > 0 ? <strong>{money(p.due)}</strong> : money(0)}</td>
            <td>{label(t.billStatus, b.status)}</td>
          </tr>
        );
      })}
    </Table>
  );
}

function InvoicesTable({ m, shown }: { m: SiteMoney; shown: SiteMoney }) {
  if (m.invoices.length === 0) return <p data-testid="invoices-empty">{t.noInvoices}</p>;
  const rows = [...shown.invoices].sort((a, b) => b.invoice_date.localeCompare(a.invoice_date));
  if (rows.length === 0) return <p>{t.noMoneyMatch}</p>;
  return (
    <Table testId="invoices" head={[t.colInvoiceNo, t.colDate, t.colSupplier, t.colNote, t.colAmount, '']}>
      {rows.map((x) => (
        <tr key={x.id} className={x.voided ? 'voided' : undefined} data-testid={`invoice-${x.id}`}>
          <td>{x.invoice_number}</td>
          <td>{day(x.invoice_date)}</td>
          <td>{x.supplier_name}</td>
          <td>{x.note ?? ''}</td>
          <td className="num">{money(x.amount)}</td>
          <td>
            <Void on={x.voided} reason={null} />
          </td>
        </tr>
      ))}
    </Table>
  );
}
