// The country this build is for, like the phone's FIELDOS_MARKET define:
// one build per market (VITE_FIELDOS_MARKET=in|us|my|ae|uk, India by
// default). Money, the tax's name and the instant-payment word come from
// here; never write ₹, GST or UPI into a page. Mirrors lib/core/market.dart.

export type MarketId = 'in' | 'us' | 'my' | 'ae' | 'uk';

export type Market = {
  id: MarketId;
  currency: string;
  locale: string; // number grouping: India groups in lakhs and crores
  tax: string;
  /** India splits GST into CGST + SGST inside a state; elsewhere one line. */
  splitsInsideState: boolean;
  instantPayment: string;
  progressBill: string;
  invoice: string;
};

const MARKETS: Record<MarketId, Market> = {
  in: { id: 'in', currency: 'INR', locale: 'en-IN', tax: 'GST', splitsInsideState: true, instantPayment: 'UPI', progressBill: 'Running bill (RA)', invoice: 'Tax invoice' },
  us: { id: 'us', currency: 'USD', locale: 'en-US', tax: 'Sales tax', splitsInsideState: false, instantPayment: 'Payment app (Zelle, Venmo)', progressBill: 'Pay application', invoice: 'Invoice' },
  my: { id: 'my', currency: 'MYR', locale: 'en-MY', tax: 'SST', splitsInsideState: false, instantPayment: 'DuitNow', progressBill: 'Progress claim', invoice: 'Invoice' },
  ae: { id: 'ae', currency: 'AED', locale: 'en-AE', tax: 'VAT', splitsInsideState: false, instantPayment: 'Instant transfer (Aani)', progressBill: 'Interim payment application', invoice: 'Tax invoice' },
  uk: { id: 'uk', currency: 'GBP', locale: 'en-GB', tax: 'VAT', splitsInsideState: false, instantPayment: 'Faster Payment', progressBill: 'Application for payment', invoice: 'VAT invoice' },
};

export function marketFor(id: string | undefined): Market {
  return MARKETS[(id ?? '').toLowerCase() as MarketId] ?? MARKETS.in;
}

export const market = marketFor(import.meta.env?.VITE_FIELDOS_MARKET as string | undefined);

const fmtCache = new Map<string, Intl.NumberFormat>();

/** An amount in the market's currency: "₹1,25,000.50" in India. */
export function money(v: number, m: Market = market): string {
  const key = m.id;
  let f = fmtCache.get(key);
  if (!f) {
    f = new Intl.NumberFormat(m.locale, { style: 'currency', currency: m.currency, minimumFractionDigits: 2, maximumFractionDigits: 2 });
    fmtCache.set(key, f);
  }
  return f.format(v);
}
