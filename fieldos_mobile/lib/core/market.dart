/// Which country this copy of FieldOS is built for: India, the United
/// States, Malaysia, the UAE or the United Kingdom.
///
/// Each market is a separate app in the stores (its own app id, listing,
/// prices and legal text) built from this one codebase with
/// `--dart-define=FIELDOS_MARKET=us` (and so on). The same define picks the
/// Android application id (android/app/build.gradle.kts) and the iPhone
/// bundle id (tool/ios/build_ipa.sh), so the Dart side and the store side
/// can never disagree. Leaving it out builds the Indian app exactly as it
/// was before markets existed: same app id, rupees, GST, Indian languages.
///
/// Everything country-specific that is a plain value lives here: money,
/// dates, units, the name of the sales tax, overtime rules, phone codes and
/// which languages the app offers. Wording that differs ("GST" vs "Sales
/// tax", "DPR" vs "Daily log") goes through tr()'s per-market English
/// table instead (lib/l10n/market_terms.dart).
library;

enum Market {
  india('in', 'IN', 'India'),
  us('us', 'US', 'United States'),
  malaysia('my', 'MY', 'Malaysia'),
  uae('ae', 'AE', 'United Arab Emirates'),
  uk('uk', 'GB', 'United Kingdom');

  const Market(this.id, this.countryCode, this.countryName);

  /// The FIELDOS_MARKET value.
  final String id;

  /// ISO 3166 country code, for locales and speech ('en-US').
  final String countryCode;
  final String countryName;

  static Market? fromId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Android application id and iPhone bundle id. India keeps the original
  /// id so the app already in the stores keeps updating.
  String get appId => this == india ? 'com.mldynamic.fieldos' : 'com.mldynamic.fieldos.$id';

  MarketConfig get config => switch (this) {
        india => _india,
        us => _us,
        malaysia => _malaysia,
        uae => _uae,
        uk => _uk,
      };
}

enum UnitSystem { metric, imperial }

/// Day-month-year ("6 Nov 2026") or month-day-year ("Nov 6, 2026").
enum DateOrder { dmy, mdy }

/// How tax shows on a bill or invoice.
class TaxRegime {
  const TaxRegime({
    required this.name,
    required this.defaultRate,
    required this.registrationLabel,
    this.splitsInsideState = false,
    required this.rateChoices,
    this.withholdingLabel,
    this.reverseChargeNote,
  });

  /// The rates offered as one-tap choices on a bill, 0 (none) first.
  final List<double> rateChoices;

  /// "GST", "Sales tax", "SST", "VAT".
  final String name;

  /// The usual rate on construction work, in percent; every bill can change it.
  final double defaultRate;

  /// What the tax registration number is called: "GSTIN", "TRN".
  final String registrationLabel;

  /// India only: inside one state the tax splits half CGST, half SGST;
  /// across states it is all IGST. Everywhere else it is one line.
  final bool splitsInsideState;

  /// Tax the client keeps back and pays to the government for the
  /// contractor: TDS in India, CIS in the UK. Null where there is none, and
  /// then the app never asks for it.
  final String? withholdingLabel;

  /// The line a reverse-charge invoice must carry, where the law has one
  /// (UK construction services since March 2021). Null elsewhere.
  final String? reverseChargeNote;
}

/// When paid hours become overtime, and at what rate. Thresholds of null
/// mean the law sets none (overtime is then whatever the contract says).
class OvertimeRule {
  const OvertimeRule({
    this.dailyHours,
    this.weeklyHours,
    this.multiplier = 1.5,
    this.note = '',
  });

  final double? dailyHours;
  final double? weeklyHours;

  /// Pay for an overtime hour, as a multiple of the normal hourly rate.
  final double multiplier;

  /// One line for the wage sheet: which law, in plain words.
  final String note;
}

class MarketConfig {
  const MarketConfig({
    required this.currencyCode,
    required this.currencySymbol,
    required this.symbolSpace,
    required this.majorUnitWords,
    required this.minorUnitWords,
    required this.pdfCurrency,
    required this.indianGrouping,
    required this.dateOrder,
    required this.clock24h,
    required this.units,
    required this.tax,
    required this.overtime,
    required this.phonePrefix,
    required this.languageCodes,
    required this.postcodeLabel,
    required this.regionLabel,
    required this.progressBillName,
    required this.progressBillTitle,
    required this.invoiceTitle,
    this.wordsAnd = false,
    this.currencyWordsFirst = true,
    this.payHourly = false,
  });

  /// ISO 4217: 'INR', 'USD', 'MYR', 'AED', 'GBP'.
  final String currencyCode;

  /// As written before an amount on screen: '₹', '$', 'RM', 'AED', '£'.
  final String currencySymbol;

  /// Whether a space separates the symbol from the figure ("AED 1,250").
  final bool symbolSpace;

  /// "Rupees", "US Dollars", "Ringgit Malaysia", "UAE Dirhams", "Pounds".
  final String majorUnitWords;

  /// "Paise", "Cents", "Sen", "Fils", "Pence".
  final String minorUnitWords;

  /// What a PDF prints for the symbol. The PDF's built-in fonts have no ₹
  /// or Arabic glyphs, so those are spelled out.
  final String pdfCurrency;

  /// 12,34,567 (lakh/crore) instead of 1,234,567.
  final bool indianGrouping;
  final DateOrder dateOrder;
  final bool clock24h;
  final UnitSystem units;
  final TaxRegime tax;
  final OvertimeRule overtime;

  /// '+91', '+1', '+60', '+971', '+44'.
  final String phonePrefix;

  /// The app languages this market offers, English first. The codes match
  /// AppLanguage.code; a code the app has no table for yet is skipped.
  final List<String> languageCodes;

  /// "PIN code", "ZIP code", "Postcode"; empty where addresses have none.
  final String postcodeLabel;

  /// "State", "Emirate", "County".
  final String regionLabel;

  /// The running (progress) bill: "Running bill (RA)" in India, "Pay
  /// application" in the US, "Application for payment" in the UK.
  final String progressBillName;

  /// Its heading on the PDF.
  final String progressBillTitle;

  /// The invoice's heading on the PDF: "TAX INVOICE", or "INVOICE" in the
  /// US, where there is no tax-invoice format in law.
  final String invoiceTitle;

  /// British-style "One Hundred and Five" in amounts in words.
  final bool wordsAnd;

  /// Crews are paid by the hour (US, UK): a worker's rate is per hour, and
  /// the wage sheet pays hours worked plus the overtime premium. Elsewhere
  /// the rate is per day and a day counts as full or half.
  final bool payHourly;

  /// "Rupees One Hundred Only" (India, Malaysia, UAE cheques) rather than
  /// "One Hundred Dollars" (US, UK).
  final bool currencyWordsFirst;
}

const _india = MarketConfig(
  currencyCode: 'INR',
  currencySymbol: '₹',
  symbolSpace: false,
  majorUnitWords: 'Rupees',
  minorUnitWords: 'Paise',
  pdfCurrency: 'Rs. ',
  indianGrouping: true,
  dateOrder: DateOrder.dmy,
  clock24h: false,
  units: UnitSystem.metric,
  tax: TaxRegime(
    name: 'GST',
    defaultRate: 18,
    registrationLabel: 'GSTIN',
    splitsInsideState: true,
    withholdingLabel: 'TDS',
    rateChoices: [0, 5, 12, 18],
  ),
  // Factories Act / state rules: double the ordinary rate past 9 h a day
  // or 48 h a week. Most sites pay daily wages and agree overtime on site.
  overtime: OvertimeRule(dailyHours: 9, weeklyHours: 48, multiplier: 2, note: 'Overtime at twice the daily rate past 9 hours a day or 48 a week'),
  phonePrefix: '+91',
  languageCodes: ['en', 'hi', 'te', 'ta', 'kn', 'mr'],
  postcodeLabel: 'PIN code',
  regionLabel: 'State',
  progressBillName: 'Running bill (RA)',
  progressBillTitle: 'RUNNING ACCOUNT BILL',
  invoiceTitle: 'TAX INVOICE',
);

const _us = MarketConfig(
  currencyCode: 'USD',
  currencySymbol: r'$',
  symbolSpace: false,
  majorUnitWords: 'Dollars',
  minorUnitWords: 'Cents',
  pdfCurrency: r'$',
  indianGrouping: false,
  dateOrder: DateOrder.mdy,
  clock24h: false,
  units: UnitSystem.imperial,
  // No federal VAT; state and local sales tax, often 0 on lump-sum
  // construction contracts, so the default is 0 and each bill can set it.
  tax: TaxRegime(name: 'Sales tax', defaultRate: 0, registrationLabel: 'Tax ID (EIN)', rateChoices: [0, 6, 7, 8.25]),
  // FLSA: time and a half past 40 hours in a work week. California adds
  // daily overtime past 8 hours; the wage sheet notes it.
  overtime: OvertimeRule(weeklyHours: 40, multiplier: 1.5, note: 'Time and a half past 40 hours a week (FLSA). Some states, like California, also pay daily overtime.'),
  phonePrefix: '+1',
  languageCodes: ['en', 'es'],
  postcodeLabel: 'ZIP code',
  regionLabel: 'State',
  payHourly: true,
  progressBillName: 'Pay application',
  progressBillTitle: 'APPLICATION FOR PAYMENT',
  invoiceTitle: 'INVOICE',
  currencyWordsFirst: false,
);

const _malaysia = MarketConfig(
  currencyCode: 'MYR',
  currencySymbol: 'RM',
  symbolSpace: false,
  majorUnitWords: 'Ringgit Malaysia',
  minorUnitWords: 'Sen',
  pdfCurrency: 'RM',
  indianGrouping: false,
  dateOrder: DateOrder.dmy,
  clock24h: false,
  units: UnitSystem.metric,
  // Service tax on construction services since 1 Jul 2025, at 6% for
  // registered providers above the threshold (8% is the general rate for
  // other services). Unregistered firms pick None.
  tax: TaxRegime(name: 'SST', defaultRate: 6, registrationLabel: 'SST registration no.', rateChoices: [0, 6, 8]),
  // Employment Act 1955 (2022 amendment): 45 hours a week, 8 a day, at
  // 1.5x on a normal day.
  overtime: OvertimeRule(dailyHours: 8, weeklyHours: 45, multiplier: 1.5, note: 'Overtime at 1.5x past 8 hours a day or 45 a week (Employment Act 1955)'),
  phonePrefix: '+60',
  languageCodes: ['en', 'ms', 'zh', 'ta'],
  postcodeLabel: 'Postcode',
  regionLabel: 'State',
  progressBillName: 'Progress claim',
  progressBillTitle: 'PROGRESS CLAIM',
  // Malaysia has no "tax invoice" since GST ended; SST bills are invoices.
  invoiceTitle: 'INVOICE',
);

const _uae = MarketConfig(
  currencyCode: 'AED',
  currencySymbol: 'AED',
  symbolSpace: true,
  majorUnitWords: 'UAE Dirhams',
  minorUnitWords: 'Fils',
  pdfCurrency: 'AED ',
  indianGrouping: false,
  dateOrder: DateOrder.dmy,
  clock24h: false,
  units: UnitSystem.metric,
  tax: TaxRegime(name: 'VAT', defaultRate: 5, registrationLabel: 'TRN', rateChoices: [0, 5]),
  // Federal Decree-Law 33/2021: 8 hours a day, 48 a week; overtime at
  // least 25% more (50% between 10 pm and 4 am).
  overtime: OvertimeRule(dailyHours: 8, weeklyHours: 48, multiplier: 1.25, note: 'Overtime at 25% extra past 8 hours a day (50% from 10 pm to 4 am), UAE Labour Law'),
  phonePrefix: '+971',
  languageCodes: ['en', 'ar', 'hi', 'ur', 'ml'],
  postcodeLabel: '',
  regionLabel: 'Emirate',
  progressBillName: 'Interim payment application',
  progressBillTitle: 'INTERIM PAYMENT APPLICATION',
  invoiceTitle: 'TAX INVOICE',
);

const _uk = MarketConfig(
  currencyCode: 'GBP',
  currencySymbol: '£',
  symbolSpace: false,
  majorUnitWords: 'Pounds',
  minorUnitWords: 'Pence',
  pdfCurrency: '£',
  indianGrouping: false,
  dateOrder: DateOrder.dmy,
  clock24h: true,
  units: UnitSystem.metric,
  tax: TaxRegime(
    name: 'VAT',
    defaultRate: 20,
    registrationLabel: 'VAT number',
    withholdingLabel: 'CIS',
    rateChoices: [0, 5, 20],
    reverseChargeNote: 'Reverse charge: customer to account to HMRC for the VAT',
  ),
  // Working Time Regulations cap the average week at 48 hours (workers
  // can opt out) but set no overtime premium.
  overtime: OvertimeRule(weeklyHours: 48, multiplier: 1, note: 'No legal overtime rate; the 48-hour average week can be opted out of (Working Time Regulations)'),
  phonePrefix: '+44',
  languageCodes: ['en', 'pl', 'ro'],
  postcodeLabel: 'Postcode',
  regionLabel: 'County',
  payHourly: true,
  progressBillName: 'Application for payment',
  progressBillTitle: 'APPLICATION FOR PAYMENT',
  invoiceTitle: 'VAT INVOICE',
  wordsAnd: true,
  currencyWordsFirst: false,
);

Market _market = Market.fromId(const String.fromEnvironment('FIELDOS_MARKET', defaultValue: 'in')) ??
    (throw StateError('Unknown FIELDOS_MARKET; use in, us, my, ae or uk'));

/// The market this build is for.
Market get currentMarket => _market;

/// Its settings: shorthand for `currentMarket.config`.
MarketConfig get market => _market.config;

/// India-only parts of the app: GSTIN and CGST/SGST/IGST, TDS, UPI
/// payment QR codes, RERA reports, PF/ESI/professional-tax payroll and
/// Tally/Zoho exports. Hidden in every other market's app.
bool get isIndia => _market == Market.india;

/// What the one-line tax is called on screens and PDFs: IGST in India
/// (where CGST + SGST is the other case), the tax's own name elsewhere.
String get igstLabel => isIndia ? 'IGST' : market.tax.name;

/// Tests switch market with this; the app never does (one build, one market).
void debugSetMarket(Market m) => _market = m;
