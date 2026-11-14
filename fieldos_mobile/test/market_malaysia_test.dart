/// Malaysia: amounts in words as local accounting software prints them,
/// DuitNow, the e-Invoice note, and Malay and Chinese screens.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show paymentModes;
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() {
    debugSetMarket(Market.india);
    setCurrentLanguage(AppLanguage.en);
  });

  test('amount in words: Ringgit Malaysia ... and Cents ... Only', () {
    debugSetMarket(Market.malaysia);
    expect(amountInWords(1234.56), 'Ringgit Malaysia One Thousand Two Hundred Thirty Four and Cents Fifty Six Only');
    expect(amountInWords(500), 'Ringgit Malaysia Five Hundred Only');
    expect(amountInWords(1200000), 'Ringgit Malaysia One Million Two Hundred Thousand Only');
  });

  test('India keeps Paise after the number and UPI', () {
    debugSetMarket(Market.india);
    expect(amountInWords(12500.5), endsWith('and Fifty Paise Only'));
    expect(paymentModes['upi'], 'UPI');
    expect(market.billFooterNote, isNull);
  });

  test('DuitNow and the e-Invoice note', () {
    debugSetMarket(Market.malaysia);
    expect(paymentModes['upi'], 'DuitNow');
    expect(market.billFooterNote, contains('not an e-Invoice'));
    expect(market.tax.onlyWhenRegistered, isTrue);
  });

  test('Malay and Chinese screens', () {
    debugSetMarket(Market.malaysia);
    setCurrentLanguage(AppLanguage.ms);
    expect(tr('Cancel'), isNot('Cancel'));
    setCurrentLanguage(AppLanguage.zh);
    expect(tr('Cancel'), isNot('Cancel'));
    // The market's wording comes first in English too.
    setCurrentLanguage(AppLanguage.en);
    expect(tr('Make the next RA bill'), 'Make the next progress claim');
    expect(tr('GST'), 'SST');
  });
}
