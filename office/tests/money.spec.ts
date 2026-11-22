import { expect, test } from '@playwright/test';
import {
  billPaid,
  byCategory,
  filterExpenses,
  gstSplit,
  moneySummary,
  NO_FILTER,
  periodRange,
  totalSpent,
  type ClientBill,
  type Expense,
  type SiteMoney,
} from '../src/money';
import { moneySheets } from '../src/moneyExport';
import { marketFor } from '../src/market';
import { fileName, sheetNames, xlsxBytes } from '../src/xlsx';
import { sheets, unzip } from './xlsxread';

// These mirror the phone's money_book.dart tests where the rules overlap.
const now = new Date(2026, 10, 18, 10, 0); // Wed 18 Nov 2026, local

const exp = (o: Partial<Expense>): Expense => ({
  id: crypto.randomUUID(), project_id: 'p1', category: 'Material', amount: 100, incurred_on: '2026-11-18', note: null,
  paid_to: null, mode: 'cash', gst_pct: null, gst_inter_state: false, voucher_no: 1, voided: false, void_reason: null,
  created_at: '2026-11-18T05:00:00Z', ...o,
});
const bill = (o: Partial<ClientBill>): ClientBill => ({
  id: 'b1', project_id: 'p1', kind: 'ra', bill_number: 'RA-1', bill_date: '2026-11-01', client_name: 'Sunrise',
  gross: 100000, net_payable: 90000, retention_pct: 5, status: 'issued', created_at: '2026-11-01T00:00:00Z', ...o,
});

test('periods are whole local days, weeks start on Monday', () => {
  expect(periodRange({ ...NO_FILTER, period: 'this_week' }, now)).toEqual(['2026-11-16', '2026-11-23']);
  expect(periodRange({ ...NO_FILTER, period: 'this_month' }, now)).toEqual(['2026-11-01', '2026-12-01']);
  expect(periodRange({ ...NO_FILTER, period: 'last_month' }, now)).toEqual(['2026-10-01', '2026-11-01']);
  expect(periodRange({ ...NO_FILTER, period: 'custom', from: '2026-11-02', to: '2026-11-05' }, now)).toEqual(['2026-11-02', '2026-11-06']);
  expect(periodRange({ ...NO_FILTER, period: 'last_month' }, new Date(2026, 0, 10))).toEqual(['2025-12-01', '2026-01-01']);
  expect(periodRange(NO_FILTER, now)).toBeNull();
});

test('filters narrow and order the list; cancelled entries show but never add up', () => {
  const xs = [
    exp({ amount: 500, incurred_on: '2026-11-17', category: 'Labour', paid_to: 'Ramesh', voucher_no: 2 }),
    exp({ amount: 250.5, incurred_on: '2026-11-18', voucher_no: 3 }),
    exp({ amount: 999, incurred_on: '2026-11-18', voided: true, voucher_no: 4 }),
    exp({ amount: 70, incurred_on: '2026-10-30', voucher_no: 1 }),
  ];
  expect(totalSpent(xs)).toBe(820.5);
  const week = filterExpenses(xs, { ...NO_FILTER, period: 'this_week' }, now);
  expect(week.map((e) => e.voucher_no)).toEqual([3, 4, 2]);
  expect(week.map((e) => e.incurred_on)).toEqual(['2026-11-18', '2026-11-18', '2026-11-17']);
  expect(totalSpent(week)).toBe(750.5);
  expect(filterExpenses(xs, { ...NO_FILTER, showCancelled: false }, now)).toHaveLength(3);
  expect(filterExpenses(xs, { ...NO_FILTER, query: 'rames' }, now).map((e) => e.voucher_no)).toEqual([2]);
  expect(filterExpenses(xs, { ...NO_FILTER, query: 'v-3' }, now).map((e) => e.voucher_no)).toEqual([3]);
  expect(filterExpenses(xs, { ...NO_FILTER, category: 'Labour' }, now)).toHaveLength(1);
});

test('spend by category, biggest first', () => {
  const s = byCategory([exp({ amount: 300 }), exp({ amount: 100, category: 'Labour' }), exp({ amount: 600, category: 'Labour' }), exp({ amount: 5, voided: true })]);
  expect(s.map((x) => [x.category, x.amount, x.count])).toEqual([['Labour', 700, 2], ['Material', 300, 1]]);
  expect(s[0].share).toBeCloseTo(0.7);
});

test('GST split adds back to the total, as on the phone', () => {
  expect(gstSplit(1180, 18, false)).toEqual({ taxable: 1000, cgst: 90, sgst: 90, igst: 0 });
  expect(gstSplit(1180, 18, true)).toEqual({ taxable: 1000, cgst: 0, sgst: 0, igst: 180 });
  const odd = gstSplit(105.33, 5, false);
  expect(Math.round((odd.taxable + odd.cgst + odd.sgst) * 100)).toBe(10533);
  expect(gstSplit(500, 0, false)).toEqual({ taxable: 500, cgst: 0, sgst: 0, igst: 0 });
});

test('a bill owes its net amount less what was matched to it', () => {
  const al = [
    { id: 'a1', bill_id: 'b1', payment_id: 'x', kind: 'bill', amount: 50000 },
    { id: 'a2', bill_id: 'b1', payment_id: 'y', kind: 'retention', amount: 2000 },
    { id: 'a3', bill_id: 'b2', payment_id: 'y', kind: 'bill', amount: 1 },
  ];
  expect(billPaid(bill({}), al)).toEqual({ paid: 50000, due: 40000 });
  expect(billPaid(bill({ status: 'paid' }), al)).toEqual({ paid: 50000, due: 0 });
});

const site: SiteMoney = {
  expenses: [exp({ amount: 1180, gst_pct: 18, note: '=HYPERLINK("http://x")', paid_to: 'A & B <Traders>' }), exp({ amount: 50, voided: true, void_reason: 'typo' })],
  invoices: [],
  in: {
    payments: [{ id: 'p', project_id: 'p1', amount: 100000, received_on: '2026-11-10T06:00:00Z', from_party: 'Sunrise', mode: 'upi', note: null, voided: false, void_reason: null, created_at: '' }],
    bills: [bill({})],
    allocations: [{ id: 'a', bill_id: 'b1', payment_id: 'p', kind: 'bill', amount: 90000 }],
  },
};

test('the summary: balance is received less spent, due is what bills still owe', () => {
  expect(moneySummary(site)).toEqual({ spent: 1180, supplierInvoices: 0, received: 100000, balance: 98820, billed: 90000, dueFromClient: 0 });
  expect(moneySummary({ ...site, in: null })).toMatchObject({ spent: 1180, received: null, balance: null });
});

test('the Excel file opens, keeps numbers as numbers and text as plain text', () => {
  const book = sheets(unzip(xlsxBytes(moneySheets(site, [{ id: 'p1', name: 'Tower A' }], marketFor('in')))));
  expect([...book.keys()]).toEqual(['Money', 'Spent', 'Received', 'Client bills', 'Supplier invoices']);
  const spent = book.get('Spent')!;
  expect(spent[0]).toContain('Amount (INR)');
  expect(spent[0]).toContain('CGST');
  const gst = spent.find((r) => r.includes(1180))!;
  expect(gst).toEqual(expect.arrayContaining([1180, 18, 1000, 90]));
  expect(gst).toContain('=HYPERLINK("http://x")'); // a string cell, never a formula
  expect(gst).toContain('A & B <Traders>');
  expect(spent.find((r) => r.includes(50))).toContain('Yes');
  expect(book.get('Received')![1]).toContain('UPI');
  expect(book.get('Client bills')![1]).toEqual(['RA-1', 'Running bill (RA)', '2026-11-01', 'Sunrise', 100000, 90000, 90000, 0, 'Issued']);
  expect(book.get('Money')![1]).toEqual(['Tower A', 1180, 0, 100000, 98820, 90000, 0]);
});

test('without money in, the file has no received, bills or balance', () => {
  const book = sheets(unzip(xlsxBytes(moneySheets({ ...site, in: null }, [{ id: 'p1', name: 'Tower A' }], marketFor('in')))));
  expect([...book.keys()]).toEqual(['Money', 'Spent', 'Supplier invoices']);
  expect(book.get('Money')![0]).toEqual(['Site', 'Spent', 'Supplier invoices']);
});

test('other markets name their own tax and currency, in one tax column', () => {
  const book = sheets(unzip(xlsxBytes(moneySheets(site, [{ id: 'p1', name: 'Tower A' }], marketFor('uk')))));
  const head = book.get('Spent')![0];
  expect(head).toContain('Amount (GBP)');
  expect(head).toContain('VAT');
  expect(head).not.toContain('CGST');
  expect(book.get('Client bills')![1][1]).toBe('Application for payment');
});

test('sheet and file names are safe', () => {
  expect(sheetNames(['A/B', 'a/b', 'x'.repeat(40)])).toEqual(['A B', 'a b 2', 'x'.repeat(31)]);
  // Excel calls the file damaged for these.
  expect(sheetNames(["'Ravi's Villa'", 'History', "''"])).toEqual(["Ravi's Villa", 'History 2', 'Sheet']);
  expect(fileName('Tower: A/B', 'Money', '2026-11-21')).toBe('Tower A B Money 2026-11-21.xlsx');
});
