# Markets: one codebase, one app per country

FieldOS ships as a separate store app per country, all built from
`fieldos_mobile/`:

| Market | `FIELDOS_MARKET` | App / bundle id | Currency | Tax on bills | Units | Languages |
|---|---|---|---|---|---|---|
| India | `in` (default) | `com.mldynamic.fieldos` | ₹ INR, lakh grouping | GST (CGST+SGST / IGST), TDS | metric | en, hi, te, ta, kn, mr |
| United States | `us` | `com.mldynamic.fieldos.us` | $ USD | Sales tax (default 0%), hourly pay, OT past 40 h/week | US customary (ft, cu yd, lb, rebar #) | en, es |
| Malaysia | `my` | `com.mldynamic.fieldos.my` | RM MYR, "Ringgit Malaysia ... and Cents ... Only" | SST 6% (only when registered), e-Invoice note on bills, DuitNow | metric | en, ms, zh, ta |
| UAE | `ae` | `com.mldynamic.fieldos.ae` | AED | VAT 5% | metric | en, ar, hi, ur, ml |
| United Kingdom | `uk` | `com.mldynamic.fieldos.uk` | £ GBP | VAT 20%, CIS, reverse charge | metric | en, pl, ro |

Languages listed for a market appear in the app only once that language's
table exists (`AppLanguage.offered`).

## How the switch works

One build define picks everything:

```bash
flutter build appbundle --release --dart-define=FIELDOS_MARKET=us ...
FIELDOS_MARKET=us tool/android/build_store_release.sh
FIELDOS_MARKET=us tool/ios/build_ipa.sh
```

- Dart: `lib/core/market.dart` reads it (`currentMarket`, `market`).
- Android: `android/app/build.gradle.kts` decodes the same dart-define and
  sets `applicationId`. No define means India and the original id, so the
  app already on Play keeps updating.
- iPhone: `tool/ios/build_ipa.sh` writes the suffix into
  `ios/Flutter/Market.xcconfig`; the Runner target's bundle id is
  `com.mldynamic.fieldos$(FIELDOS_BUNDLE_SUFFIX)`.

There are no Gradle product flavors on purpose: flavors would make every
existing `flutter build` command (release.yml, play-upload.yml, the build
scripts) need `--flavor`, and the Indian app must keep building unchanged.

## What lives where

- **Plain values** (currency, grouping, date order, 12/24-hour clock, units,
  tax name and default rate, withholding, overtime rule, phone prefix,
  postcode label, languages): `MarketConfig` in `lib/core/market.dart`.
- **Money**: `money()` in `lib/core/format.dart` (`rupees()` is the old name
  and follows the market too). Amounts in words: `amountInWords()` in
  `lib/features/money/billing_calc.dart` (lakh/crore in India,
  thousand/million elsewhere, British "and" in the UK).
- **Wording** that differs by country ("GST" -> "Sales tax", "DPR" ->
  "Daily log"): `lib/l10n/market_terms.dart`, looked up by `tr()` before the
  language tables. Labels stay keyed by their Indian English text.

## Units

Quantities are stored as typed (a BOQ line keeps its own unit). What
changes by market: the unit converter's list (`unitGroups` in
`purchase_tools.dart`: the US starts in feet, cubic yards and pounds, a ton
is 2,000 lb and a cement bag 94 lb; India keeps brass, guntha and quintal),
steel entries in estimates (the US types a bar size, #3 to #18, stored as
mm so weights work everywhere, and sees pounds), and parsing of typed
quantities (`baseQty`). The material check uses Indian site-mix norms
(cement bags, PCC 1:4:8), so the US app hides it.

## Workers' permits and site cards

Malaysia (PLKS, CIDB Green Card, passport, FOMEMA), UAE (work permit and
visa, Emirates ID, passport) and UK (CSCS card, right to work) keep each
worker's papers with an expiry date: `permitKinds` in
`lib/features/workers/worker_permits.dart`, table `worker_permits` (synced
through the site-execution mapper; server migration
`supabase/migrations/20261114180000_worker_permits.sql`, to be deployed by
the owner). Owners and managers get reminders 90, 60, 30 and 7 days before
each date; an expired permit that blocks site work is a warning at
punch-in, never a block on pay. Numbers show in full only to the owner and
project managers. No health results are stored.

## Right-to-left languages (UAE)

The UAE app offers English, Arabic, Hindi, Urdu and Malayalam
(`strings_ar.dart`, `strings_ur.dart`, `strings_ml.dart`, machine-assisted,
each needing a native speaker's review). Arabic and Urdu screens mirror:
layouts use `EdgeInsetsDirectional`, `AlignmentDirectional`,
`PositionedDirectional` and `TextAlign.start/end`, never left and right
(test/market_uae_rtl_test.dart fails on a new left/right). Number fields
read Arabic-Indic (٠-٩) and Urdu (۰-۹) digits: `westernDigits` in
`core/format.dart`, and `WesternDigitsFormatter` first in any field that
filters its characters. PDFs stay in English.

## UAE site rules

- **Midday break** (`MarketConfig.middayBreak`): 12:30 to 3:00 pm, 15 June
  to 15 September. The labour tab shows the season, and a punch-in inside
  the window asks first (indoor, shaded or exempt work only). Hours are
  not cut automatically.
- **TRN** on bills: 15 digits, stored without spaces or dashes
  (`normaliseTaxId`, `validTaxId`). A bill is a TAX INVOICE only when the
  company has its TRN (`marketInvoiceTitle`); without it, an INVOICE.

## UK billing (VAT, CIS, reverse charge)

- **VAT number** on bills: GB plus 9 digits (12 for a branch), with HMRC's
  mod-97 check on both number series, or GBGD/GBHA (`isValidUkVat`). A
  bill is a VAT INVOICE only with the company's VAT number.
- **CIS** is the withholding (`TaxRegime.withholdingOnLabourOnly`): it is
  taken off labour only. Each bill line has a "Materials or plant hire"
  tick (`BillLine.materials`, stored in the lines JSON) that leaves it out.
- **Domestic reverse charge**: a switch on the bill. The VAT is shown but
  not added to the total, and the PDF carries HMRC's wording with the VAT
  in pounds and pence (`reverseChargeLine`). The flag is stored as `DRC`
  in the SAC column, which only India uses, so no migration was needed.
- **CIS rates** (`TaxRegime.withholdingRates`): one tap for gross payment
  status 0%, registered 20% or not registered 30%; the subcontractor's
  status itself comes from HMRC verification, which FieldOS does not do.
- UK English swaps (site diary, application for payment, delivery note,
  sign in/out, hourly pay) are in `market_terms.dart`.

## Minimum wage

Malaysia's wage sheet flags any daily rate under the Minimum Wages Order
2025 (RM1,700 a month: RM65.38 a day for a 6-day week, RM78.46 for 5,
RM98.08 for 4, from the company's rest days) and notes under the sheet that
Sabah and Sarawak have their own Labour Ordinances (`MarketConfig.minimumWage`,
`belowMinimumWage` in `wage_sheet.dart`). The UK checks hourly pay against the
National Living Wage (£12.71 an hour from age 21, from 1 April 2026), and the
note says lower rates apply under 21 and to apprentices. Other markets set
none here: India's and the US's vary by state, and the UAE sets none for most
private-sector workers.

## Legal texts and prices

- **Privacy policy, terms, privacy notice**: `lib/features/legal/legal_texts_markets.dart`
  adapts India's texts section by section (`adaptLegal`); the short notice
  in Settings > Your privacy is `privacyNoticeItems` in
  `lib/features/legal/privacy_notice.dart`. The US has its own (state privacy
  laws, arbitration, Delaware law). Malaysia has its own too (PDPA 2010 as
  amended in 2024: section 129 transfers to India and the USA, breach notice
  to the Commissioner within 72 hours, 21-day replies, a notice in English
  and Bahasa Melayu; Malaysian law with AIAC arbitration; the customer as
  data controller). The UAE has its own (PDPL, Federal Decree-Law 45/2021:
  Articles 22-23 transfers under contract (no consent is claimed, since the
  login line only links the texts), selfies kept with attendance records,
  no face recognition, DIFC/ADGM check; terms under Indian law with a
  carve-out for mandatory UAE rights and DIAC arbitration for company plans;
  the Arabic version of both is still to be made). The UK has its own (UK
  GDPR and DPA 2018: lawful bases, IDTA / UK Addendum transfers to India and
  the USA, ICO breach notice in 72 hours, one-month replies, complaints to
  the ICO, a notice in English, Polish and Romanian; terms under the law of
  England and Wales, B2B only, the Article 28 processor terms built in).
  Owner actions before the UK app ships: appoint the Article 27 UK
  representative and name them in the notice, and pay the ICO data
  protection fee. All of these are drafts that
  need a lawyer in that country; never call them lawyer-reviewed.
  The published pages (`PRIVACY_POLICY_URL`, `TERMS_URL`) are build defines,
  so each market's store build points at its own pages.
- **Prices**: `marketPrices` in `lib/core/market.dart`. India's are the
  owner's. The others are **proposed, not approved** (`approved: false`):
  make no store products from them until the owner agrees.

## Backend per market

All markets use the one Supabase project (Mumbai) for now. The backend is
chosen at build time by `SUPABASE_URL` and `SUPABASE_ANON_KEY`, so a market
moves to its own regional project (US, Singapore, London...) by building
its app with that project's values. No code change is needed. Before a
market moves, deploy the same migrations and functions to the new project
and update that market's privacy policy ("Where your data is processed").

## Per-market setup that is not code

Each market's app needs its own store listing, RevenueCat app (and key),
Google OAuth Android client (package name + upload-key SHA-1), privacy
policy and terms. The research, compliance checklist, pricing, brand
adaptation and store copy for each market are in the project files under
`international/<market>/`.

## Tests

`test/market_test.dart` checks each market's money, dates, words,
languages, app ids, tax and overtime values, and that India is unchanged.
Tests switch market with `debugSetMarket()` and reset it in `tearDown`.
