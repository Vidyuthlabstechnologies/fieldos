// The Excel file of one site's money, or of every site the person picked.
// It holds exactly what the page shows this person: no money received or
// client bills unless the server gave them those (same rule as the phone's
// data_export.dart, showMoneyIn).

import { market as defaultMarket, type Market } from './market';
import { billPaid, dayOf, gstSplit, moneySummary, voucherLabel, type SiteMoney } from './money';
import { label, t } from './strings';
import type { Cell, Sheet } from './xlsx';

export const modeLabel = (mode: string | null, m: Market = defaultMarket) =>
  mode == null ? '' : mode === 'upi' ? m.instantPayment : label(t.modes, mode);

export const billKindLabel = (kind: string, m: Market = defaultMarket) =>
  kind === 'ra' ? m.progressBill : kind === 'tax_invoice' ? m.invoice : kind;

const amountHead = (m: Market) => `${t.colAmount} (${m.currency})`;

/** [sites] names each site by id; with more than one, every row says its site. */
export function moneySheets(money: SiteMoney, sites: { id: string; name: string }[], m: Market = defaultMarket): Sheet[] {
  const many = sites.length > 1;
  const siteName = new Map(sites.map((s) => [s.id, s.name]));
  const lead = (projectId: string): Cell[] => (many ? [siteName.get(projectId) ?? ''] : []);
  const siteHead = many ? [t.colSite] : [];
  const off = siteHead.length;
  const cancelled = (v: boolean) => (v ? t.yes : '');

  const taxHead = m.splitsInsideState
    ? [`${m.tax} ${t.colTaxRate}`, t.colTaxable, 'CGST', 'SGST', 'IGST']
    : [`${m.tax} ${t.colTaxRate}`, t.colTaxable, m.tax];
  const spent: Sheet = {
    name: t.spent,
    money: (m.splitsInsideState ? [6, 8, 9, 10, 11] : [6, 8, 9]).map((i) => off + i),
    rows: [
      [...siteHead, t.colVoucher, t.colDate, t.colCategory, t.colPaidTo, t.colMode, t.colNote, amountHead(m), ...taxHead, t.cancelled, t.colReason],
      ...[...money.expenses]
        .sort((a, b) => dayOf(a.incurred_on).localeCompare(dayOf(b.incurred_on)) || (a.voucher_no ?? 0) - (b.voucher_no ?? 0))
        .map((e) => {
          const g = gstSplit(e.amount, e.gst_pct ?? 0, e.gst_inter_state || !m.splitsInsideState);
          const tax = e.gst_pct ? (m.splitsInsideState ? [e.gst_pct, g.taxable, g.cgst, g.sgst, g.igst] : [e.gst_pct, g.taxable, g.igst]) : [];
          const pad = m.splitsInsideState ? 5 : 3;
          return [
            ...lead(e.project_id),
            voucherLabel(e.voucher_no),
            dayOf(e.incurred_on),
            e.category,
            e.paid_to ?? '',
            modeLabel(e.mode, m),
            e.note ?? '',
            e.amount,
            ...(tax.length ? tax : Array<Cell>(pad).fill('')),
            cancelled(e.voided),
            e.void_reason ?? '',
          ];
        }),
    ],
  };

  const invoices: Sheet = {
    name: t.supplierInvoices,
    money: [off + 3, off + 4],
    rows: [
      [...siteHead, t.colInvoiceNo, t.colDate, t.colSupplier, amountHead(m), `${m.tax} ${t.colTaxIn}`, t.colNote, t.cancelled],
      ...[...money.invoices]
        .sort((a, b) => a.invoice_date.localeCompare(b.invoice_date))
        .map((x) => [...lead(x.project_id), x.invoice_number, x.invoice_date, x.supplier_name, x.amount, x.gst_amount, x.note ?? '', cancelled(x.voided)]),
    ],
  };

  const sheets: Sheet[] = [];
  const summaries = sites.map((s) => {
    const one: SiteMoney = {
      expenses: money.expenses.filter((e) => e.project_id === s.id),
      invoices: money.invoices.filter((x) => x.project_id === s.id),
      in: money.in && {
        payments: money.in.payments.filter((p) => p.project_id === s.id),
        bills: money.in.bills.filter((b) => b.project_id === s.id),
        allocations: money.in.allocations.filter((a) => money.in!.bills.some((b) => b.id === a.bill_id && b.project_id === s.id)),
      },
    };
    return [s.name, moneySummary(one)] as const;
  });
  const withIn = money.in != null;
  sheets.push({
    name: t.money,
    money: withIn ? [1, 2, 3, 4, 5, 6] : [1, 2],
    rows: [
      [t.colSite, t.spent, t.supplierInvoices, ...(withIn ? [t.received, t.balance, t.billed, t.dueFromClient] : [])],
      ...summaries.map(([name, s]) => [
        name,
        s.spent,
        s.supplierInvoices,
        ...(withIn ? [s.received, s.balance, s.billed, s.dueFromClient] : []),
      ]),
    ],
  });
  sheets.push(spent);

  if (money.in) {
    const allocations = money.in.allocations;
    sheets.push({
      name: t.received,
      money: [off + 4],
      rows: [
        [...siteHead, t.colDate, t.colReceivedFrom, t.colMode, t.colNote, amountHead(m), t.cancelled, t.colReason],
        ...[...money.in.payments]
          .sort((a, b) => a.received_on.localeCompare(b.received_on))
          .map((p) => [...lead(p.project_id), dayOf(p.received_on), p.from_party, modeLabel(p.mode, m), p.note ?? '', p.amount, cancelled(p.voided), p.void_reason ?? '']),
      ],
    });
    sheets.push({
      name: t.clientBills,
      money: [off + 4, off + 5, off + 6, off + 7],
      rows: [
        [...siteHead, t.colBillNo, t.colKind, t.colDate, t.colClient, t.colGross, t.colNet, t.colPaid, t.colAmountDue, t.status],
        ...[...money.in.bills]
          .sort((a, b) => a.bill_date.localeCompare(b.bill_date))
          .map((b) => {
            const p = billPaid(b, allocations);
            return [...lead(b.project_id), b.bill_number, billKindLabel(b.kind, m), b.bill_date, b.client_name, b.gross, b.net_payable, p.paid, p.due, label(t.billStatus, b.status)];
          }),
      ],
    });
  }
  sheets.push(invoices);
  return sheets;
}
