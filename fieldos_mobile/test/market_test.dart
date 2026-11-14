/// One codebase, one app per country: what each market's build shows for
/// money, dates, amounts in words, languages and its app id. India must
/// stay exactly as it was before markets existed.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/tour/guide_lines.dart';
import 'package:fieldos_mobile/services/read_aloud.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('a build without FIELDOS_MARKET is the Indian app', () {
    expect(currentMarket, Market.india);
    expect(Market.india.appId, 'com.mldynamic.fieldos');
  });

  test('every market has its own app id and its own currency', () {
    expect({for (final m in Market.values) m.appId}.length, Market.values.length);
    expect([for (final m in Market.values) m.config.currencyCode], ['INR', 'USD', 'MYR', 'AED', 'GBP']);
    expect(Market.us.appId, 'com.mldynamic.fieldos.us');
    expect(Market.uk.appId, 'com.mldynamic.fieldos.uk');
    for (final m in Market.values) {
      expect(Market.fromId(m.id), m);
      expect(m.config.languageCodes.first, 'en', reason: '$m');
    }
    expect(Market.fromId('gb'), isNull);
  });

  group('money', () {
    test('India keeps lakh grouping and the rupee sign', () {
      expect(money(1234567), '₹12,34,567');
      expect(money(999), '₹999');
      expect(money(45.5, cents: true), '₹45.50');
      expect(rupees(-1500), '-₹1,500');
      expect(rupees(12.25, paise: true), '₹12.25');
    });

    test('other markets group by thousands with their own symbol', () {
      final cases = {
        Market.us: r'$1,234,567.89',
        Market.malaysia: 'RM1,234,567.89',
        Market.uae: 'AED 1,234,567.89',
        Market.uk: '£1,234,567.89',
      };
      cases.forEach((m, want) {
        debugSetMarket(m);
        expect(money(1234567.89, cents: true), want, reason: '$m');
        // rupees() is the old name and must follow the market too.
        expect(rupees(1234567.89, paise: true), want, reason: '$m');
      });
      debugSetMarket(Market.us);
      expect(money(100), r'$100');
      expect(money(1000), r'$1,000');
      expect(money(-25000), r'-$25,000');
      expect(money(0.5), r'$1');
      expect(money(0), r'$0');
      expect(currencySymbol, r'$');
    });
  });

  group('dates', () {
    final d = DateTime(2026, 11, 6, 19, 5);
    final now = DateTime(2026, 11, 14);

    test('India: day first, 12-hour clock', () {
      expect(fmtDate(d), '6 Nov 2026');
      expect(fmtDate(d, short: true, now: now), '6 Nov');
      expect(fmtTime(d), '7:05 pm');
      expect(fmtDateNumeric(d), '06/11/2026');
    });

    test('US: month first', () {
      debugSetMarket(Market.us);
      expect(fmtDate(d), 'Nov 6, 2026');
      expect(fmtDate(d, short: true, now: now), 'Nov 6');
      expect(fmtDate(d, short: true, now: DateTime(2027, 1, 2)), 'Nov 6, 2026');
      expect(fmtDateNumeric(d), '11/06/2026');
      expect(fmtTime(d), '7:05 pm');
    });

    test('UK: day first, 24-hour clock', () {
      debugSetMarket(Market.uk);
      expect(fmtDate(d), '6 Nov 2026');
      expect(fmtTime(d), '19:05');
      expect(fmtTime(DateTime(2026, 1, 1, 7, 3)), '07:03');
      expect(fmtDateNumeric(d), '06/11/2026');
    });
  });

  group('amounts in words', () {
    test('India is unchanged', () {
      expect(amountInWords(107520), 'Rupees One Lakh Seven Thousand Five Hundred Twenty Only');
      expect(rupeesInWords(12500.5), 'Rupees Twelve Thousand Five Hundred and Fifty Paise Only');
    });

    test('international number words', () {
      expect(westernNumberWords(0), 'Zero');
      expect(westernNumberWords(15), 'Fifteen');
      expect(westernNumberWords(1234567), 'One Million Two Hundred Thirty Four Thousand Five Hundred Sixty Seven');
      expect(westernNumberWords(2000000000), 'Two Billion');
      expect(westernNumberWords(1000001), 'One Million One');
      expect(westernNumberWords(-40), 'Minus Forty');
      expect(westernNumberWords(105, and: true), 'One Hundred and Five');
      expect(westernNumberWords(1005, and: true), 'One Thousand and Five');
      expect(westernNumberWords(2300, and: true), 'Two Thousand Three Hundred');
      expect(westernNumberWords(1234567, and: true),
          'One Million Two Hundred and Thirty Four Thousand Five Hundred and Sixty Seven');
    });

    test('each market words its currency', () {
      final cases = {
        Market.us: 'Twelve Thousand Five Hundred Dollars and Fifty Cents Only',
        Market.malaysia: 'Ringgit Malaysia Twelve Thousand Five Hundred and Fifty Sen Only',
        Market.uae: 'UAE Dirhams Twelve Thousand Five Hundred and Fifty Fils Only',
        Market.uk: 'Twelve Thousand Five Hundred Pounds and Fifty Pence Only',
      };
      cases.forEach((m, want) {
        debugSetMarket(m);
        expect(amountInWords(12500.5), want, reason: '$m');
      });
      debugSetMarket(Market.us);
      expect(amountInWords(1000000), 'One Million Dollars Only');
      expect(numberWords(150000), 'One Hundred Fifty Thousand');
    });
  });

  group('languages', () {
    test('India offers English and the five Indian languages', () {
      expect(AppLanguage.offered, [
        AppLanguage.en, AppLanguage.hi, AppLanguage.te, AppLanguage.ta, AppLanguage.kn, AppLanguage.mr,
      ]);
      expect(speechCodeFor(AppLanguage.te), 'te-IN');
      expect(speechCodeFor(AppLanguage.en), 'en-IN');
    });

    test('other markets offer only their own languages', () {
      debugSetMarket(Market.us);
      expect(AppLanguage.offered, contains(AppLanguage.en));
      expect(AppLanguage.offered, isNot(contains(AppLanguage.hi)));
      expect(speechCodeFor(AppLanguage.en), 'en-US');
      expect(AppLanguage.en.locale.countryCode, 'US');

      debugSetMarket(Market.malaysia);
      expect(AppLanguage.offered, contains(AppLanguage.ta));
      // Tamil is Tamil wherever it is spoken from; the voice packs are ta-IN.
      expect(speechCodeFor(AppLanguage.ta), 'ta-IN');
      expect(speechCodeFor(AppLanguage.en), 'en-MY');

      debugSetMarket(Market.uae);
      expect(AppLanguage.offered, contains(AppLanguage.hi));
      expect(AppLanguage.offered, isNot(contains(AppLanguage.te)));
    });

    test("the phone's language only counts when the market offers it", () {
      debugSetMarket(Market.us);
      expect(languageFromDevice(const [Locale('te', 'IN')]), AppLanguage.en);
      debugSetMarket(Market.india);
      expect(languageFromDevice(const [Locale('te', 'IN')]), AppLanguage.te);
    });
  });

  test('the US app speaks US English and Spanish to Mitra', () {
    debugSetMarket(Market.us);
    expect(AppLanguage.offered, [AppLanguage.en, AppLanguage.es]);
    expect(guideLines['en_us']!.keys.toSet(), guideLines['en']!.keys.toSet());
    expect(guideLines['es']!.keys.toSet(), guideLines['en']!.keys.toSet());
    setSpokenLanguage(AppLanguage.en);
    expect(ReadAloud.guideText('tour_6'), contains('dollar'));
    expect(ReadAloud.guideText('tour_6'), isNot(contains('GST')));
    setSpokenLanguage(AppLanguage.es);
    expect(ReadAloud.guideText('tour_0'), startsWith('¡Hola!'));
    expect(ReadAloud.localeFor('Hola, ¿qué tal?'), 'es-US');
    setSpokenLanguage(AppLanguage.en);
    expect(ReadAloud.localeFor('Hello'), 'en-US');
    debugSetMarket(Market.india);
    expect(ReadAloud.localeFor('Hello'), 'en-IN');
    expect(ReadAloud.guideText('tour_6'), contains('rupee'));
  });

  test('tax and overtime differ by market', () {
    expect(Market.india.config.tax.name, 'GST');
    expect(Market.india.config.tax.splitsInsideState, isTrue);
    expect(Market.india.config.tax.withholdingLabel, 'TDS');
    expect(Market.us.config.tax.name, 'Sales tax');
    expect(Market.us.config.tax.withholdingLabel, isNull);
    expect(Market.us.config.units, UnitSystem.imperial);
    expect(Market.us.config.overtime.weeklyHours, 40);
    expect(Market.malaysia.config.tax.name, 'SST');
    expect(Market.uae.config.tax.defaultRate, 5);
    expect(Market.uk.config.tax.withholdingLabel, 'CIS');
    expect(Market.uk.config.tax.reverseChargeNote, isNotNull);
    for (final m in Market.values.where((m) => m != Market.india)) {
      expect(m.config.tax.splitsInsideState, isFalse, reason: '$m');
      expect(m.config.units == UnitSystem.imperial, m == Market.us, reason: '$m');
    }
  });
}
