import type { SupabaseClient } from '@supabase/supabase-js';
import type { Defect, Drawing, Registers, Revision, Rfi, Submittal } from './rules';
import type { Allocation, ClientBill, Expense, Payment, SiteMoney, SupplierInvoice } from './money';

export type Company = { id: string; name: string; role: string };
export type Site = {
  id: string;
  name: string;
  client_name: string | null;
  status: string;
  start_date: string | null;
  end_date: string | null;
};

// The companies this person belongs to, by name.
export async function loadCompanies(db: SupabaseClient, userId: string): Promise<Company[]> {
  const { data, error } = await db
    .from('company_members')
    .select('company_id, role, companies(name)')
    .eq('user_id', userId);
  if (error) throw error;
  type Row = { company_id: string; role: string; companies: { name: string } | { name: string }[] | null };
  return ((data ?? []) as Row[])
    .map((r) => {
      const c = Array.isArray(r.companies) ? r.companies[0] : r.companies;
      return { id: r.company_id, name: c?.name ?? 'Company', role: r.role };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

// The sites of one company this person may see (the server decides which).
export async function loadSites(db: SupabaseClient, companyId: string): Promise<Site[]> {
  const { data, error } = await db
    .from('projects')
    .select('id, name, client_name, status, start_date, end_date')
    .eq('company_id', companyId)
    .order('name');
  if (error) throw error;
  return sortSites((data ?? []) as Site[]);
}

const STATUS_ORDER: Record<string, number> = { active: 0, planning: 1, on_hold: 2, completed: 3 };

// Running sites first, then planned, on hold, completed; by name within each.
export function sortSites(sites: Site[]): Site[] {
  return [...sites].sort(
    (a, b) => (STATUS_ORDER[a.status] ?? 9) - (STATUS_ORDER[b.status] ?? 9) || a.name.localeCompare(b.name),
  );
}

export function matchesSearch(s: Site, q: string): boolean {
  const needle = q.trim().toLowerCase();
  if (!needle) return true;
  return s.name.toLowerCase().includes(needle) || (s.client_name ?? '').toLowerCase().includes(needle);
}

// Remembers the last company picked, per browser.
const LAST = 'fieldos-office-company';
export function lastCompany(): string | null {
  try {
    return localStorage.getItem(LAST);
  } catch {
    return null;
  }
}
export function rememberCompany(id: string): void {
  try {
    localStorage.setItem(LAST, id);
  } catch {
    /* private window: not remembered */
  }
}

// Everything the site's registers show, read at once.
export async function loadRegisters(db: SupabaseClient, projectId: string): Promise<Registers> {
  const read = async <T,>(table: string, cols: string): Promise<T[]> => {
    const { data, error } = await db.from(table).select(cols).eq('project_id', projectId).order('created_at').limit(5000);
    if (error) throw error;
    return (data ?? []) as T[];
  };
  const [rfis, submittals, defects, drawings, revisions] = await Promise.all([
    read<Rfi>('site_rfis', 'id, question, asked_of, due_on, answer, answered_at, status, created_at'),
    read<Submittal>(
      'site_submittals',
      'id, title, kind, spec_section, from_party, reviewer, required_by, round, status, decision_note, decided_at, created_at',
    ),
    read<Defect>('site_defects', 'id, location, description, severity, due_on, status, reopen_count, created_at'),
    read<Drawing>('site_drawings', 'id, number, title, discipline, created_at'),
    read<Revision>('site_drawing_revisions', 'id, drawing_id, rev, status, note, decided_at, created_at'),
  ]);
  return { rfis, submittals, defects, drawings, revisions };
}

export async function loadSite(db: SupabaseClient, projectId: string): Promise<Site | null> {
  const { data, error } = await db
    .from('projects')
    .select('id, name, client_name, status, start_date, end_date')
    .eq('id', projectId)
    .maybeSingle();
  if (error) throw error;
  return (data as Site | null) ?? null;
}

// Every row of a query, a page at a time: the server hands out at most
// 1000 rows per request, and a busy site has more expenses than that.
async function readAll<T>(page: (from: number, to: number) => PromiseLike<{ data: unknown; error: unknown }>): Promise<T[]> {
  const size = 1000;
  const out: T[] = [];
  for (let from = 0; ; from += size) {
    const { data, error } = await page(from, from + size - 1);
    if (error) throw error;
    const rows = (data ?? []) as T[];
    out.push(...rows);
    if (rows.length < size) return out;
  }
}

const EXPENSE_COLS =
  'id, project_id, category, amount, incurred_on, note, paid_to, mode, gst_pct, gst_inter_state, voucher_no, voided, void_reason, created_at';
const PAYMENT_COLS = 'id, project_id, amount, received_on, from_party, mode, note, voided, void_reason, created_at';
const BILL_COLS = 'id, project_id, kind, bill_number, bill_date, client_name, gross, net_payable, retention_pct, status, created_at';
const INVOICE_COLS = 'id, project_id, invoice_number, invoice_date, amount, gst_amount, note, voided, created_at, vendors(name)';

const nums = <T extends Record<string, unknown>>(r: T, keys: string[]): T => {
  const o: Record<string, unknown> = { ...r };
  for (const k of keys) if (o[k] != null) o[k] = Number(o[k]);
  return o as T;
};

type InvoiceRow = Omit<SupplierInvoice, 'supplier_name'> & { vendors: { name: string } | { name: string }[] | null };
const invoice = (r: InvoiceRow): SupplierInvoice => {
  const v = Array.isArray(r.vendors) ? r.vendors[0] : r.vendors;
  const { vendors: _v, ...rest } = r;
  void _v;
  return nums({ ...rest, supplier_name: v?.name ?? '' }, ['amount', 'gst_amount']);
};

/** Does the server let this person see the site's money in (received,
 * client bills)? The same check its row security makes. */
export async function seesMoneyIn(db: SupabaseClient, projectId: string): Promise<boolean> {
  const { data, error } = await db.rpc('is_project_owner_or_pm', { p_project_id: projectId });
  if (error) throw error;
  return data === true;
}

// Money for some sites, read in groups so the address stays short.
async function forSites<T>(ids: string[], read: (group: string[]) => Promise<T[]>): Promise<T[]> {
  const out: T[] = [];
  for (let i = 0; i < ids.length; i += 50) out.push(...(await read(ids.slice(i, i + 50))));
  return out;
}

export async function loadMoney(db: SupabaseClient, projectIds: string[], withIn: boolean): Promise<SiteMoney> {
  const expenses = forSites(projectIds, (g) =>
    readAll<Expense>((a, b) => db.from('site_expenses').select(EXPENSE_COLS).in('project_id', g).order('id').range(a, b)),
  );
  const invoices = forSites(projectIds, (g) =>
    readAll<InvoiceRow>((a, b) => db.from('site_supplier_invoices').select(INVOICE_COLS).in('project_id', g).order('id').range(a, b)),
  );
  const moneyIn = withIn
    ? Promise.all([
        forSites(projectIds, (g) =>
          readAll<Payment>((a, b) => db.from('site_payments_received').select(PAYMENT_COLS).in('project_id', g).order('id').range(a, b)),
        ),
        forSites(projectIds, (g) =>
          readAll<ClientBill>((a, b) => db.from('site_client_bills').select(BILL_COLS).in('project_id', g).order('id').range(a, b)),
        ),
        forSites(projectIds, (g) =>
          readAll<Allocation>((a, b) =>
            db.from('site_bill_allocations').select('id, bill_id, payment_id, kind, amount').in('project_id', g).order('id').range(a, b),
          ),
        ),
      ])
    : Promise.resolve(null);
  const [e, inv, mi] = await Promise.all([expenses, invoices, moneyIn]);
  return {
    expenses: e.map((x) => nums(x, ['amount', 'gst_pct'])),
    invoices: inv.map(invoice),
    in: mi && {
      payments: mi[0].map((x) => nums(x, ['amount'])),
      bills: mi[1].map((x) => nums(x, ['gross', 'net_payable', 'retention_pct'])),
      allocations: mi[2].map((x) => nums(x, ['amount'])),
    },
  };
}

/** Company owners and project managers see every site's money in. */
export const managesCompany = (role: string) => role === 'owner' || role === 'project_manager';
