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

  test('retention: 10% a claim, stopping at 5% of the contract sum', () {
    debugSetMarket(Market.malaysia);
    expect(market.retentionDefaultPct, 10);
    // Contract RM1,000,000: limit RM50,000. RM40,000 already kept.
    expect(
        retentionPctWithinLimit(pct: 10, gross: 50000, alreadyKept: 40000, contractSum: 1000000, limitPctOfContract: 5),
        10); // 5,000 fits in the 10,000 left
    expect(
        retentionPctWithinLimit(pct: 10, gross: 200000, alreadyKept: 40000, contractSum: 1000000, limitPctOfContract: 5),
        5); // room 10,000 of 200,000 = 5%
    expect(retentionPctWithinLimit(pct: 10, gross: 100000, alreadyKept: 50000, contractSum: 1000000, limitPctOfContract: 5), 0);
    expect(retentionPctWithinLimit(pct: 10, gross: 100000, alreadyKept: 0, limitPctOfContract: 5), 10); // no sum: unchanged
    debugSetMarket(Market.india);
    expect(market.retentionDefaultPct, 5);
    expect(market.retentionLimitOfContractPct, isNull);
  });
}

