/// Wording that changes by country, on top of the language tables.
///
/// Every label in the app is written once, in Indian English ("GST",
/// "DPR", "RA bill"). For the other markets tr() first looks the label up
/// here, by market and then language, so the US app says "Sales tax" and
/// "Daily log" while the code keeps one key per label. A label missing
/// here falls through to the language table and then to the English key.
///
/// test/market_terms_test.dart fails when a label shown in a non-Indian
/// market still carries an India-only word (GST, lakh, TDS...) with no
/// entry here.
library;

import 'package:fieldos_mobile/core/market.dart';

/// Per market, per language code ('en', 'es'...), English key -> label.
const Map<Market, Map<String, Map<String, String>>> marketTerms = {};
