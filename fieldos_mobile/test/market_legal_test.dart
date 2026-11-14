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
      for (final word in [
        'Data Protection Board',
        'DPDP',
        'Grievance',
        'Information Technology Act',
        'UPI',
        'Hyderabad courts',
      ]) {
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

  test('every market has its own texts', () {
    for (final m in Market.values) {
      debugSetMarket(m);
      expect(marketLegalReady, isTrue, reason: m.name);
    }
  });

  test('the UK texts follow the UK GDPR and the law of England and Wales', () {
    debugSetMarket(Market.uk);
    expect(privacyNoticeItems, same(ukPrivacyNoticeItems));
    final policy = _all(marketPrivacyPolicy), terms = _all(marketTermsOfUse);
    for (final text in [policy, terms, privacyNoticeKeys.join('\n')]) {
      for (final word in ['Data Protection Board', 'DPDP', 'Grievance', 'Information Technology Act', 'UPI', 'GST',
          'PDPA', 'PDPL', 'Malaysia', 'UAE', 'Hyderabad, Telangana have', 'rupee', '₹', 'selfie attendance',
          '12 months unless']) {
        expect(text, isNot(contains(word)), reason: '"$word" in a UK text');
      }
    }
    for (final want in ['UK GDPR', 'Data Protection Act 2018', 'Article 27', 'International Data Transfer Agreement',
        'one month', 'Information Commissioner', 'face recognition', 'Mumbai, India', '72 hours']) {
      expect(policy, contains(want));
    }
    expect(policy, contains('decides its own lawful basis'));
    expect(policy, contains('acknowledge a complaint within 30 days'));
    for (final want in ['England and Wales', 'Article 28', 'HMRC', 'reverse charge', 'death or personal injury',
        'Consumer Rights Act 2015', 'if you or your business are in']) {
      expect(terms, contains(want));
    }
    final numbers = [for (final s in marketTermsOfUse.sections) int.parse(s.heading.split('.').first)];
    expect(numbers, List.generate(numbers.length, (i) => i + 1));
  });

  test('the UK notice reads in Polish and Romanian', () {
    debugSetMarket(Market.uk);
    for (final l in [AppLanguage.pl, AppLanguage.ro]) {
      final missing = privacyNoticeKeys.where((k) => !hasTranslation(l, k)).toList();
      expect(missing, isEmpty, reason: l.name);
    }
  });

  test('UAE: selfies stay with the attendance records, and no transfer consent is claimed', () {
    debugSetMarket(Market.uae);
    final policy = _all(marketPrivacyPolicy);
    expect(policy, isNot(contains('12 months unless')));
    expect(policy, isNot(contains('agree to these transfers')));
    expect(policy, isNot(contains('If your company uses selfie attendance')));
    expect(policy, contains('photo and location for your'));
  });

  test('the Malaysian texts follow the PDPA and Malaysian law', () {
    debugSetMarket(Market.malaysia);
    expect(marketLegalReady, isTrue);
    expect(privacyNoticeItems, same(myPrivacyNoticeItems));
    final policy = _all(marketPrivacyPolicy), terms = _all(marketTermsOfUse);
    for (final text in [policy, terms, privacyNoticeKeys.join('\n')]) {
      for (final word in [
        'Data Protection Board',
        'DPDP',
        'Grievance',
        'Information Technology Act',
        'UPI',
        'Hyderabad courts',
        'Consumer Protection Act, 2019',
        'unity, integrity',
        'GST',
      ]) {
        expect(text, isNot(contains(word)), reason: '"$word" in a Malaysian text');
      }
    }
    for (final want in [
      'Personal Data Protection Act 2010',
      'section 129',
      '72 hours',
      'Commissioner',
      'Mumbai, India',
      '21 days',
      'Bahasa Melayu',
    ]) {
      expect(policy, contains(want));
    }
    for (final want in ['laws of Malaysia', 'AIAC', 'MyInvois', 'data controller', 'Sabah and Sarawak']) {
      expect(terms, contains(want));
    }
    // The sections stay numbered in order, ending with the contact.
    final numbers = [for (final s in marketTermsOfUse.sections) int.parse(s.heading.split('.').first)];
    expect(numbers, List.generate(numbers.length, (i) => i + 1));
    expect(marketTermsOfUse.sections.last.heading, '21. Contact us');
    expect(marketPrivacyPolicy.sections.last.heading, 'Contact');
  });

  test('the Malaysian notice reads in Bahasa Melayu, Chinese and Tamil', () {
    debugSetMarket(Market.malaysia);
    for (final l in [AppLanguage.ms, AppLanguage.zh, AppLanguage.ta]) {
      final missing = privacyNoticeKeys.where((k) => !hasTranslation(l, k)).toList();
      expect(missing, isEmpty, reason: l.name);
    }
  });

  test('the UAE texts follow the PDPL and keep mandatory UAE rights', () {
    debugSetMarket(Market.uae);
    expect(marketLegalReady, isTrue);
    expect(privacyNoticeItems, same(aePrivacyNoticeItems));
    final policy = _all(marketPrivacyPolicy), terms = _all(marketTermsOfUse);
    for (final text in [policy, terms, privacyNoticeKeys.join('\n')]) {
      for (final word in ['Data Protection Board', 'DPDP', 'Grievance', 'Information Technology Act', 'UPI',
          'Consumer Protection Act, 2019', 'unity, integrity', 'GST', 'PDPA', 'Malaysia']) {
        expect(text, isNot(contains(word)), reason: '"$word" in a UAE text');
      }
    }
    for (final want in ['Decree-Law No. 45 of 2021', 'Articles 22 and 23', 'Mumbai, India', 'face recognition', 'DIFC']) {
      expect(policy, contains(want));
    }
    for (final want in ['UAE law', 'Wage Protection System', 'midday break', 'controller', 'Dubai International Arbitration Centre']) {
      expect(terms, contains(want));
    }
    final numbers = [for (final s in marketTermsOfUse.sections) int.parse(s.heading.split('.').first)];
    expect(numbers, List.generate(numbers.length, (i) => i + 1));
  });

  test('the UAE notice reads in Arabic, Hindi, Urdu and Malayalam', () {
    debugSetMarket(Market.uae);
    for (final l in [AppLanguage.ar, AppLanguage.hi, AppLanguage.ur, AppLanguage.ml]) {
      final missing = privacyNoticeKeys.where((k) => !hasTranslation(l, k)).toList();
      expect(missing, isEmpty, reason: l.name);
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
