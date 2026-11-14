/// Each market's app shows its own privacy policy, terms and privacy
/// notice; India's stay as they were.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/legal/legal_texts.dart';
import 'package:fieldos_mobile/features/legal/legal_texts_markets.dart';
import 'package:fieldos_mobile/features/legal/privacy_notice.dart';
import 'package:fieldos_mobile/l10n/language.dart';

String _all(LegalDocument d) => [d.title, d.intro, for (final s in d.sections) '${s.heading} ${s.body}'].join('\n');

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('India keeps its own texts', () {
    debugSetMarket(Market.india);
    expect(identical(marketPrivacyPolicy, privacyPolicy), isTrue);
    expect(identical(marketTermsOfUse, termsOfUse), isTrue);
    expect(privacyNoticeItems, same(indiaPrivacyNoticeItems));
    expect(marketLegalReady, isTrue);
  });

  test('the US texts carry no Indian law or authority', () {
    debugSetMarket(Market.us);
    expect(marketLegalReady, isTrue);
    final policy = _all(marketPrivacyPolicy), terms = _all(marketTermsOfUse);
    for (final text in [policy, terms, privacyNoticeKeys.join('\n')]) {
      for (final word in ['Data Protection Board', 'DPDP', 'Grievance', 'Information Technology Act', 'UPI', 'Hyderabad courts']) {
        expect(text, isNot(contains(word)), reason: '"$word" in a US text');
      }
    }
    expect(policy, contains('sell'));
    expect(policy, contains('India')); // the honest note that data is held in India today
    expect(terms.toLowerCase(), contains('arbitration'));
    expect(terms, contains('Delaware'));
  });

  test('the US notice reads in Spanish', () {
    debugSetMarket(Market.us);
    final missing = privacyNoticeKeys.where((k) => !hasTranslation(AppLanguage.es, k)).toList();
    expect(missing, isEmpty);
    for (final k in ['Appeal a privacy decision']) {
      expect(hasTranslation(AppLanguage.es, k), isTrue);
    }
  });

  test('markets without their own texts yet fall back and say so', () {
    for (final m in [Market.malaysia, Market.uae, Market.uk]) {
      debugSetMarket(m);
      expect(marketLegalReady, isFalse, reason: m.name);
    }
  });

  test('prices: India approved, the rest proposed and not approved', () {
    expect(marketPrices.keys.toSet(), Market.values.toSet());
    expect(marketPrices[Market.india]!.approved, isTrue);
    expect(marketPrices[Market.india]!.monthly, 999);
    for (final m in Market.values.where((m) => m != Market.india)) {
      expect(marketPrices[m]!.approved, isFalse, reason: m.name);
    }
  });
}
