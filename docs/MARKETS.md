# Markets: one codebase, one app per country

FieldOS ships as a separate store app per country, all built from
`fieldos_mobile/`:

| Market | `FIELDOS_MARKET` | App / bundle id | Currency | Tax on bills | Units | Languages |
|---|---|---|---|---|---|---|
| India | `in` (default) | `com.mldynamic.fieldos` | ₹ INR, lakh grouping | GST (CGST+SGST / IGST), TDS | metric | en, hi, te, ta, kn, mr |
| United States | `us` | `com.mldynamic.fieldos.us` | $ USD | Sales tax (default 0%), hourly pay, OT past 40 h/week | US customary (ft, cu yd, lb, rebar #) | en, es |
| Malaysia | `my` | `com.mldynamic.fieldos.my` | RM MYR | SST 8% | metric | en, ms, zh, ta |
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

## Legal texts and prices

- **Privacy policy, terms, privacy notice**: `lib/features/legal/legal_texts_markets.dart`
  adapts India's texts section by section (`adaptLegal`); the short notice
  in Settings > Your privacy is `privacyNoticeItems` in
  `lib/features/legal/privacy_notice.dart`. The US has its own (state privacy
  laws, arbitration, Delaware law). Malaysia, UAE and the UK still show
  India's until theirs are written, and `marketLegalReady` is false for them:
  do not publish those apps before it is true. All of these are drafts that
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
