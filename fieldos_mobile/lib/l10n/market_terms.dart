/// Wording that changes by country, on top of the language tables.
///
/// Every label in the app is written once, in Indian English ("GST",
/// "DPR", "RA bill"). For the other markets tr() first looks the label up
/// here, by market and then language, so the US app says "Sales tax" and
/// "Daily log" while the code keeps one key per label. A label missing
/// here falls through to the language table and then to the English key;
/// English text then gets the market's word swaps ([marketWordSwaps]:
/// "labour" -> "labor" in the US).
///
/// test/market_terms_test.dart fails when a label shown in a non-Indian
/// market still carries an India-only word (GST, lakh, TDS...).
library;

import 'package:fieldos_mobile/core/market.dart';

/// Per market, per language code ('en', 'es'...), English key -> label.
const Map<Market, Map<String, Map<String, String>>> marketTerms = {
  Market.us: {'en': _usEnglish, 'es': _usSpanish},
  Market.malaysia: {'en': _malaysiaEnglish},
  Market.uae: {'en': _uaeEnglish},
  Market.uk: {'en': _ukEnglish},
};

/// Whole-word swaps on English text, after the exact table: spelling and
/// trade words that appear in hundreds of labels. Case is kept for the
/// first letter ("Labour" -> "Labor").
const Map<Market, Map<String, String>> marketWordSwaps = {
  Market.malaysia: _malaysiaSwaps,
  Market.uae: _uaeSwaps,
  Market.uk: _ukSwaps,
  Market.us: {
    'labour': 'labor',
    'labourer': 'laborer',
    'labourers': 'laborers',
    'colour': 'color',
    'colours': 'colors',
    'metre': 'meter',
    'metres': 'meters',
    'cheque': 'check',
    'cheques': 'checks',
    'organise': 'organize',
    'organised': 'organized',
    'centre': 'center',
    'licence': 'license',
    'licences': 'licenses',
    'catalogue': 'catalog',
    'grey': 'gray',
    'programme': 'program',
    'dpr': 'daily log',
    'dprs': 'daily logs',
    'gst': 'sales tax',
    'retention': 'retainage',
    'variation': 'change order',
    'variations': 'change orders',
    'tender': 'bid',
    'tenders': 'bids',
  },
};

/// Malaysian English keeps British spelling; the trade words follow PAM
/// and JKR contracts (BQ, progress claim, delivery order).
const _malaysiaSwaps = {
  'gst': 'SST',
  'dpr': 'daily report',
  'dprs': 'daily reports',
  'boq': 'BQ',
  'challan': 'delivery order',
  'challans': 'delivery orders',
  'rupee': 'ringgit',
  'rupees': 'ringgit',
};

/// UAE English: British spelling, FIDIC and Dubai Municipality trade
/// words (interim payment application, delivery note, daily site report).
const _uaeSwaps = {
  'gst': 'VAT',
  'gstin': 'TRN',
  'dpr': 'daily site report',
  'dprs': 'daily site reports',
  'challan': 'delivery note',
  'challans': 'delivery notes',
  'rupee': 'dirham',
  'rupees': 'dirhams',
  'upi': 'instant transfer',
};

/// The UAE app in English, on top of [_uaeSwaps].
const _uaeEnglish = <String, String>{
  'Make the next RA bill': 'Make the next interim payment application',
  'Measure work done against the BOQ. Approved quantities go on the next RA bill.':
      'Measure work done against the BOQ. Approved quantities go on the next interim payment application.',
  'Note (e.g. RA bill 3)': 'Note (e.g. Interim payment 3)',
  'Running bill (RA)': 'Interim payment application',
  'Running bill': 'Interim payment application',
  'Every rupee on site': 'Every dirham on site',
  'Add ₹5,000 spent on cement': 'Add AED 500 spent on cement',
};

/// British English is the key language already; the trade words follow
/// JCT contracts (application for payment, delivery note, VAT number).
const _ukSwaps = {
  'gst': 'VAT',
  'gstin': 'VAT number',
  'dpr': 'daily report',
  'dprs': 'daily reports',
  'challan': 'delivery note',
  'challans': 'delivery notes',
  'rupee': 'pound',
  'rupees': 'pounds',
};

/// The UK app, on top of [_ukSwaps]. Crews are paid by the hour in the UK
/// (MarketConfig.payHourly), so the worker's rate field holds the hourly
/// rate and its labels must say so.
const _ukEnglish = <String, String>{
  'Daily wage': 'Hourly rate',
  'Daily wage (₹)': 'Hourly rate (₹)',
  '{amount}/day': '{amount}/hr',
  '{amount} a day': '{amount} an hour',
  'no daily wage set': 'no hourly rate set',
  "No daily wage set, so wages can't be worked out": "No hourly rate set, so wages can't be worked out",
  'Add workers with their trade and daily wage, then mark their days here.':
      'Add workers with their trade and hourly rate, then mark their days here.',
  'One worker per line: name, skill, phone, daily wage. Only the name is needed.':
      'One worker per line: name, skill, phone, hourly rate. Only the name is needed.',
  'A day counts as full at 7 hours on site and half at 3.5 hours, unless it was marked by hand on the day register. Tap a worker to pay wages or an advance.':
      'Pay is the hours on the clock at the hourly rate. A day marked by hand counts as 8 hours. UK law sets no overtime rate; hours past 48 in a week show as overtime. Tap a worker to pay wages or an advance.',
  'Make the next RA bill': 'Make the next application for payment',
  'Measure work done against the BOQ. Approved quantities go on the next RA bill.':
      'Measure work done against the BOQ. Approved quantities go on the next application for payment.',
  'Make running bills of measured work, or GST tax invoices, and send them as PDF. Previous and to-date quantities are worked out for you.':
      'Make applications for payment for measured work, or VAT invoices, and send them as PDF. Previous and to-date quantities are worked out for you.',
  'Note (e.g. RA bill 3)': 'Note (e.g. Application 3)',
  'Running bill (RA)': 'Application for payment',
  'Running bill': 'Application for payment',
  'Approve it in your UPI or bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.':
      'Approve it in your bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.',
  'Your payment is waiting for approval, for example in your UPI app. FieldOS opens by itself once {store} confirms it.':
      'Your payment is waiting for approval, for example in your bank app. FieldOS opens by itself once {store} confirms it.',
  'Add ₹5,000 spent on cement': 'Add £500 spent on cement',
};

/// The Malaysia app in Malaysian English, on top of [_malaysiaSwaps].
const _malaysiaEnglish = <String, String>{
  'Make the next RA bill': 'Make the next progress claim',
  'Measure work done against the BOQ. Approved quantities go on the next RA bill.':
      'Measure work done against the BQ. Approved quantities go on the next progress claim.',
  'Note (e.g. RA bill 3)': 'Note (e.g. Progress claim 3)',
  'Running bill (RA)': 'Progress claim',
  'Running bill': 'Progress claim',
  'Retention %': 'Retention sum %',
  'Less retention': 'Less retention sum',
  'One supplier per line: name, phone, GSTIN, what you owe them today. Only the name is needed. Write "advance" after an amount they hold of yours.':
      'One supplier per line: name, phone, SST no., what you owe them today. Only the name is needed. Write "advance" after an amount they hold of yours.',
  'Approve it in your UPI or bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.':
      'Approve it in your DuitNow or bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.',
  'Your payment is waiting for approval, for example in your UPI app. FieldOS opens by itself once {store} confirms it.':
      'Your payment is waiting for approval, for example in your bank app. FieldOS opens by itself once {store} confirms it.',
  'Every rupee on site': 'Every ringgit on site',
  'Add ₹5,000 spent on cement': 'Add RM500 spent on cement',
};

/// The US app in American English. Labels hidden in the US build (RERA,
/// PF/ESI salaries, UPI, Tally) need no entry; the test knows which.
const _usEnglish = <String, String>{
  // Crews are paid by the hour in the US (MarketConfig.payHourly): the
  // worker's rate field holds the hourly rate.
  'Daily wage': 'Hourly rate',
  'Daily wage (₹)': r'Hourly rate ($)',
  '{amount}/day': '{amount}/hr',
  // A forgotten clock-out pays nothing until it is fixed (wage_sheet.dart).
  '1 missing punch-out (half day)': '1 missing clock-out (not paid until fixed)',
  '{n} missing punch-outs (half days)': '{n} missing clock-outs (not paid until fixed)',
  'A day counts as full at 7 hours on site and half at 3.5 hours, unless it was marked by hand on the day register. Tap a worker to pay wages or an advance.':
      'Pay is the hours on the clock at the hourly rate, with time and a half past 40 hours in a work week (Monday to Sunday). A day marked by hand counts as 8 hours. Tap a worker to pay wages or an advance.',
  'DPR': 'Daily log',
  'GST': 'Sales tax',
  'GST %': 'Sales tax %',
  'No GST': 'No sales tax',
  'Before GST': 'Before tax',
  'GST on the bill': 'Sales tax on the bill',
  'Amount includes GST': 'Amount includes sales tax',
  'Amount before GST (₹)': r'Amount before tax ($)',
  'GST in it (₹, optional)': r'Sales tax in it ($, optional)',
  'Invoice total with GST (₹)': r'Invoice total with tax ($)',
  'Rate a {unit}, before GST (₹)': r'Rate per {unit}, before tax ($)',
  'Rate a {unit} (₹)': r'Rate per {unit} ($)',
  'Rate a unit (₹)': r'Rate per unit ($)',
  'Rate (₹ per unit)': r'Rate ($ per unit)',
  '{rate} a unit + GST {gst}% · landed {perUnit} a unit': '{rate} per unit + tax {gst}% · landed {perUnit} per unit',
  'Every expense as a payment voucher and every client payment as a receipt, with GST split out.':
      'Every expense as a payment voucher and every client payment as a receipt, with sales tax split out.',
  'Make running bills of measured work, or GST tax invoices, and send them as PDF. Previous and to-date quantities are worked out for you.':
      'Make pay applications for work done, or invoices, and send them as PDF. Previous and to-date quantities are worked out for you.',
  'Make the next RA bill': 'Make the next pay application',
  'Measure work done against the BOQ. Approved quantities go on the next RA bill.':
      'Track quantities installed against the schedule of values. Approved quantities go on the next pay application.',
  'Measurement book': 'Quantities installed',
  'Money received, money spent and the balance, by category. Client bills and GST invoices are made here too.':
      'Money received, money spent and the balance, by category. Pay applications and invoices are made here too.',
  'Note (e.g. RA bill 3)': 'Note (e.g. Pay app 3)',
  'Every rupee on site': 'Every dollar on the job',
  'Enter amounts in rupees, or leave blank.': 'Enter amounts in dollars, or leave blank.',
  'Enter the limit in rupees, or leave it empty for no limit.': 'Enter the limit in dollars, or leave it empty for no limit.',
  'Add ₹5,000 spent on cement': r'Add $500 spent on concrete',
  'Just say it: "Add ₹5,000 for cement", "Who came today?"': r'Just say it: "Add $500 for concrete", "Who showed up today?"',
  'Deliveries with a challan photo': 'Deliveries with a delivery ticket photo',
  'One supplier per line: name, phone, GSTIN, what you owe them today. Only the name is needed. Write "advance" after an amount they hold of yours.':
      'One supplier per line: name, phone, tax ID, what you owe them today. Only the name is needed. Write "advance" after an amount they hold of yours.',
  'Approve it in your UPI or bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.':
      'Approve it in your bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.',
  'Your payment is waiting for approval, for example in your UPI app. FieldOS opens by itself once {store} confirms it.':
      'Your payment is waiting for approval, for example in your bank app. FieldOS opens by itself once {store} confirms it.',
  'Retention %': 'Retainage %',
  'Less retention': 'Less retainage',
  'Held back by the client': 'Held back by the owner until the job is done',
  'Client name': 'Owner / client name',
  'Running bill (RA)': 'Pay application',
  'Running bill': 'Pay application',
  'Work measured this bill': 'Work done this period',
  // Estimates and the unit converter in US customary units.
  'Raw unit (e.g. cft, m)': 'Raw unit (e.g. cu ft, ft)',
  'Billing unit (e.g. cft, sqm)': 'Billing unit (e.g. cu yd, sq ft)',
  'Nos': 'Count',
  'Nos: {n}': 'Count: {n}',
  'This is a one-time download of about 30 MB. After that, {language} reports translate to English on this phone, with no internet and no cost.':
      'This is a one-time download of about 30 MB. After that, {language} logs translate to English on this phone, with no internet and no cost.',
};

/// The US app in Spanish, where the Spanish table (written for daily
/// wages and UPI) says the wrong thing for the US: pay is by the hour.
const _usSpanish = <String, String>{
  'Daily wage': 'Pago por hora',
  'Daily wage (₹)': r'Pago por hora ($)',
  '{amount}/day': '{amount}/hora',
  '1 missing punch-out (half day)': '1 salida sin registrar (sin pago hasta corregirla)',
  '{n} missing punch-outs (half days)': '{n} salidas sin registrar (sin pago hasta corregirlas)',
  'A day counts as full at 7 hours on site and half at 3.5 hours, unless it was marked by hand on the day register. Tap a worker to pay wages or an advance.':
      'El pago son las horas registradas por la tarifa por hora, con tiempo y medio después de 40 horas en la semana de trabajo (de lunes a domingo). Un día marcado a mano cuenta como 8 horas. Toca a un trabajador para pagarle o darle un adelanto.',
  'Approve it in your UPI or bank app. FieldOS opens by itself once {store} confirms the payment, usually within a few minutes.':
      'Apruébalo en la app de tu banco. FieldOS se abre solo cuando {store} confirme el pago, casi siempre en pocos minutos.',
  'Your payment is waiting for approval, for example in your UPI app. FieldOS opens by itself once {store} confirms it.':
      'Tu pago está esperando aprobación, por ejemplo en la app de tu banco. FieldOS se abre solo cuando {store} lo confirme.',
};

/// [text] with this market's whole-word swaps applied, keeping the first
/// letter's case. India and markets without swaps get [text] back.
String applyWordSwaps(Market m, String text) {
  final swaps = marketWordSwaps[m];
  if (swaps == null) return text;
  return text.replaceAllMapped(_word, (match) {
    final w = match[0]!;
    if (w.startsWith('{')) return w; // a placeholder: {gst} stays {gst}
    final to = swaps[w.toLowerCase()];
    if (to == null) return w;
    if (w == w.toUpperCase() && w.length > 1) {
      // "DPR" and "GST" are acronyms: "Daily log", "Sales tax".
      return to[0].toUpperCase() + to.substring(1);
    }
    return w[0] == w[0].toUpperCase() ? to[0].toUpperCase() + to.substring(1) : to;
  });
}

final _word = RegExp(r"\{\w+\}|[A-Za-z]+");
