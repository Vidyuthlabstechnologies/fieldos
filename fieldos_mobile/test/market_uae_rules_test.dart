/// UAE rules the app checks: the summer midday break, the TRN on bills and
/// when a bill may be called a tax invoice.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('midday break: 12:30 to 3:00 pm, 15 June to 15 September, UAE only', () {
    expect(market.middayBreak, isNull);
    debugSetMarket(Market.uae);
    final b = market.middayBreak!;
    expect(b.covers(DateTime(2026, 7, 1, 12, 30)), isTrue);
    expect(b.covers(DateTime(2026, 7, 1, 14, 59)), isTrue);
    expect(b.covers(DateTime(2026, 7, 1, 15, 0)), isFalse);
    expect(b.covers(DateTime(2026, 7, 1, 12, 29)), isFalse);
    expect(b.covers(DateTime(2026, 6, 15, 13)), isTrue);
    expect(b.covers(DateTime(2026, 9, 15, 13)), isTrue);
    expect(b.covers(DateTime(2026, 6, 14, 13)), isFalse);
    expect(b.covers(DateTime(2026, 9, 16, 13)), isFalse);
    expect(b.inSeason(DateTime(2026, 8, 1)), isTrue);
    expect(b.inSeason(DateTime(2026, 11, 14)), isFalse);
    expect(b.seasonEnd(2026), DateTime(2026, 9, 15));
    for (final m in [Market.us, Market.malaysia, Market.uk]) {
      debugSetMarket(m);
      expect(market.middayBreak, isNull, reason: m.name);
    }
  });

  test('TRN: 15 digits, stored without spaces or dashes', () {
    debugSetMarket(Market.uae);
    expect(validTaxId('100123456700003'), isTrue);
    expect(normaliseTaxId('100-123-456-700-003'), '100123456700003');
    expect(normaliseTaxId('١٠٠١٢٣٤٥٦٧٠٠٠٠٣'), '100123456700003');
    expect(validTaxId(normaliseTaxId('100 123 456 700 003')), isTrue);
    expect(validTaxId('10012345670000'), isFalse);
    expect(validTaxId('36ABCDE1234F1Z1'), isFalse);
    debugSetMarket(Market.india);
    expect(validTaxId('36ABCDE1234F1Z1'), isTrue);
    expect(normaliseTaxId(' 36abcde1234f1z1 '), '36ABCDE1234F1Z1');
    debugSetMarket(Market.uk);
    expect(validTaxId('GB980780684'), isTrue);
    expect(validTaxId('GB123456789'), isFalse, reason: 'fails the HMRC check');
  });

  test('a tax invoice only from a supplier with a TRN', () {
    debugSetMarket(Market.uae);
    expect(marketInvoiceTitle(ourTaxId: ''), 'INVOICE');
    expect(marketInvoiceTitle(ourTaxId: '100123456700003'), 'TAX INVOICE');
    debugSetMarket(Market.us);
    expect(marketInvoiceTitle(ourTaxId: ''), 'INVOICE');
  });

  test('the TRN error reads in every UAE language', () {
    debugSetMarket(Market.uae);
    const key = "That TRN doesn't look right. It has 15 digits, like 100123456700003.";
    for (final l in AppLanguage.offered.where((l) => l != AppLanguage.en)) {
      expect(hasTranslation(l, key), isTrue, reason: l.name);
    }
  });
}
