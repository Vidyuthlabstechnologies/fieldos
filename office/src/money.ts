// The money rules, kept apart from the pages so they can be tested. They
// mirror the phone's money_book.dart: cancelled entries stay on the list but
// never add up, filters carry their own total, and a period is whole local
// days. Change both together.

export type Expense = {
  id: string;
  project_id: string;
  category: string;
  amount: number;
  incurred_on: string;
  note: string | null;
  paid_to: string | null;
  mode: string | null;
  gst_pct: number | null;
  gst_inter_state: boolean;
  voucher_no: number | null;
  voided: boolean;
  void_reason: string | null;
  created_at: string;
};

export type Payment = {
  id: string;
  project_id: string;
  amount: number;
  received_on: string;
  from_party: string;
  mode: string;
  note: string | null;
  voided: boolean;
  void_reason: string | null;
  created_at: string;
};

export type ClientBill = {
  id: string;
  project_id: string;
  kind: string;
  bill_number: string;
  bill_date: string;
  client_name: string;
  gross: number;
  net_payable: number;
  retention_pct: number;
  status: string;
  created_at: string;
};

export type Allocation = { id: string; bill_id: string; payment_id: string; kind: string; amount: number };

export type SupplierInvoice = {
  id: string;
  project_id: string;
  supplier_name: string;
  invoice_number: string;
  invoice_date: string;
  amount: number;
  gst_amount: number;
  note: string | null;
  voided: boolean;
  created_at: string;
};

/** What one site's money looks like to this person. The `in` part is there
 * only for the site's owner or project manager: the server gives nobody
 * else money received or client bills, and the page doesn't pretend. */
export type SiteMoney = {
  expenses: Expense[];
  invoices: SupplierInvoice[];
  in: { payments: Payment[]; bills: ClientBill[]; allocations: Allocation[] } | null;
};

export type Period = 'all' | 'this_week' | 'this_month' | 'last_month' | 'custom';
export const PERIODS: Period[] = ['all', 'this_week', 'this_month', 'last_month', 'custom'];

export type MoneyFilter = {
  period: Period;
  from?: string; // yyyy-mm-dd, custom only
  to?: string;
  category: string | null;
  query: string;
  showCancelled: boolean;
};

export const NO_FILTER: MoneyFilter = { period: 'all', category: null, query: '', showCancelled: true };

const pad = (n: number) => String(n).padStart(2, '0');
export const isoDay = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

/** The days a filter covers as [first, after) yyyy-mm-dd, or null for all. */
export function periodRange(f: MoneyFilter, now: Date): [string, string] | null {
  const y = now.getFullYear();
  const m = now.getMonth();
  const today = new Date(y, m, now.getDate());
  switch (f.period) {
    case 'all':
      return null;
    case 'this_week': {
      // Weeks start on Monday, as on the phone.
      const monday = new Date(y, m, now.getDate() - ((today.getDay() + 6) % 7));
      return [isoDay(monday), isoDay(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 7))];
    }
    case 'this_month':
      return [isoDay(new Date(y, m, 1)), isoDay(new Date(y, m + 1, 1))];
    case 'last_month':
      return [isoDay(new Date(y, m - 1, 1)), isoDay(new Date(y, m, 1))];
    case 'custom': {
      const from = f.from || '2000-01-01';
      const to = f.to || isoDay(today);
      const [ty, tm, td] = to.split('-').map(Number);
      return [from, isoDay(new Date(ty, tm - 1, td + 1))];
    }
  }
}

/** yyyy-mm-dd of a stored day or timestamp, in local time for timestamps. */
export function dayOf(v: string): string {
  if (/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? v.slice(0, 10) : isoDay(d);
}

const inRange = (day: string, r: [string, string] | null) => !r || (day >= r[0] && day < r[1]);
const has = (q: string, xs: (string | null | undefined)[]) => xs.some((s) => s && s.toLowerCase().includes(q));

export const voucherLabel = (n: number | null) => (n == null ? '' : `V-${n}`);

/** The expenses that pass, newest first. */
export function filterExpenses(all: Expense[], f: MoneyFilter, now: Date): Expense[] {
  const r = periodRange(f, now);
  const q = f.query.trim().toLowerCase();
  return all
    .filter(
      (e) =>
        (f.showCancelled || !e.voided) &&
        (f.category == null || e.category === f.category) &&
        inRange(dayOf(e.incurred_on), r) &&
        (!q || has(q, [e.category, e.note, e.paid_to, voucherLabel(e.voucher_no), Math.round(e.amount).toString()])),
    )
    .sort((a, b) => dayOf(b.incurred_on).localeCompare(dayOf(a.incurred_on)) || b.created_at.localeCompare(a.created_at));
}

export function filterPayments(all: Payment[], f: MoneyFilter, now: Date): Payment[] {
  const r = periodRange(f, now);
  const q = f.query.trim().toLowerCase();
  return all
    .filter(
      (p) =>
        (f.showCancelled || !p.voided) &&
        inRange(dayOf(p.received_on), r) &&
        (!q || has(q, [p.from_party, p.note, Math.round(p.amount).toString()])),
    )
    .sort((a, b) => b.received_on.localeCompare(a.received_on));
}

/** Cancelled entries never add up. Rounded to paise so sums don't drift. */
export const round2 = (v: number) => Math.round((v + (v < 0 ? -1e-9 : 1e-9)) * 100) / 100;
export const totalSpent = (xs: Expense[]) => round2(xs.reduce((s, e) => s + (e.voided ? 0 : Number(e.amount)), 0));
export const totalReceived = (xs: Payment[]) => round2(xs.reduce((s, p) => s + (p.voided ? 0 : Number(p.amount)), 0));

export type Share = { category: string; amount: number; share: number; count: number };

/** Spend by category, biggest first; shares add to 1. */
export function byCategory(xs: Expense[]): Share[] {
  const m = new Map<string, { amount: number; count: number }>();
  for (const e of xs) {
    if (e.voided) continue;
    const c = m.get(e.category) ?? { amount: 0, count: 0 };
    c.amount += Number(e.amount);
    c.count += 1;
    m.set(e.category, c);
  }
  const total = [...m.values()].reduce((s, c) => s + c.amount, 0);
  return [...m.entries()]
    .map(([category, c]) => ({ category, amount: round2(c.amount), count: c.count, share: total > 0 ? c.amount / total : 0 }))
    .sort((a, b) => b.amount - a.amount || a.category.localeCompare(b.category));
}

/** GST inside a total, as the phone splits it: CGST and SGST half each, or
 * all IGST for a supplier in another state. Parts add back to the total. */
export function gstSplit(total: number, ratePct: number, interState: boolean) {
  if (!ratePct || ratePct <= 0) return { taxable: total, cgst: 0, sgst: 0, igst: 0 };
  const taxable = round2((total * 100) / (100 + ratePct));
  const tax = round2(total - taxable);
  if (interState) return { taxable, cgst: 0, sgst: 0, igst: tax };
  const cgst = round2(tax / 2);
  return { taxable, cgst, sgst: round2(tax - cgst), igst: 0 };
}

/** What has been paid against a bill, and what is still owed on it. */
export function billPaid(bill: ClientBill, allocations: Allocation[]): { paid: number; due: number } {
  const paid = round2(allocations.filter((a) => a.bill_id === bill.id && a.kind === 'bill').reduce((s, a) => s + Number(a.amount), 0));
  // A bill marked paid by hand (before payments were matched to bills) owes nothing.
  const due = bill.status === 'paid' ? 0 : Math.max(0, round2(Number(bill.net_payable) - paid));
  return { paid, due };
}

export type Summary = {
  spent: number;
  supplierInvoices: number;
  received: number | null;
  balance: number | null;
  billed: number | null;
  dueFromClient: number | null;
};

export function moneySummary(m: SiteMoney): Summary {
  const spent = totalSpent(m.expenses);
  const supplierInvoices = round2(m.invoices.reduce((s, x) => s + (x.voided ? 0 : Number(x.amount)), 0));
  if (!m.in) return { spent, supplierInvoices, received: null, balance: null, billed: null, dueFromClient: null };
  const received = totalReceived(m.in.payments);
  const billed = round2(m.in.bills.reduce((s, b) => s + Number(b.net_payable), 0));
  const dueFromClient = round2(m.in.bills.reduce((s, b) => s + billPaid(b, m.in!.allocations).due, 0));
  return { spent, supplierInvoices, received, balance: round2(received - spent), billed, dueFromClient };
}

/** Categories to offer in the filter: those used on the site, by name. */
export const categoriesUsed = (xs: Expense[]) => [...new Set(xs.map((e) => e.category))].sort((a, b) => a.localeCompare(b));
