/// Voice reports offer each market's own languages, matched to the app's
/// language voice codes, and only India's have a Sarvam fallback.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/services/speech_service.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('India keeps its list, English first', () {
    expect(speechLanguages.first.code, 'en-IN');
    expect(speechLanguages.length, 12);
  });

  test('every market speaks its own languages, English first', () {
    for (final m in Market.values) {
      debugSetMarket(m);
      expect(speechLanguages.first.isEnglish, isTrue, reason: m.name);
      expect(speechLanguages.first.code, 'en-${m == Market.india ? 'IN' : m.countryCode}', reason: m.name);
      for (final l in AppLanguage.offered) {
        expect(speechLanguageFor(speechCodeFor(l)).code, speechCodeFor(l), reason: '${m.name} ${l.code}');
      }
      if (m != Market.india) {
        expect(speechLanguages.where((l) => l.sarvamCode != null && !l.code.endsWith('-IN')), isEmpty, reason: m.name);
      }
    }
  });
}
