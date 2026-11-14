/// The UK app's bills: the domestic reverse charge (VAT shown, not added),
/// CIS taken off labour only, and VAT numbers with HMRC's check digits.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/money/billing_calc.dart';
import 'package:fieldos_mobile/l10n/language.dart';

const _labour = BillLine(description: 'Brickwork', unit: 'm2', rate: 50, qty: 50); // £2,500
const _materials = BillLine(description: 'Bricks', unit: 'nr', rate: 1.5, qty: 1000, materials: true); // £1,500

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('a line marked as materials survives the round trip; old lines read as labour', () {
    expect(decodeLines(encodeLines([_labour, _materials])).map((l) => l.materials), [false, true]);
    expect(decodeLines('[{"d":"x","u":"m","r":1,"q":1}]').single.materials, isFalse);
    expect(encodeLines([_labour]), isNot(contains('"m"')));
  });

  test('CIS: 20% on £4,000 with £1,500 of materials is £500', () {
    debugSetMarket(Market.uk);
    final t = billTotals([_labour, _materials], gstRate: 0, tdsPct: 20);
    expect(t.gross, 4000);
    expect(t.tds, 500);
    expect(t.netPayable, 3500);
  });

  test('India still takes TDS on the whole bill', () {
    final t = billTotals([_labour, _materials], gstRate: 18, tdsPct: 2);
    expect(t.tds, 80);
  });

  test('reverse charge: VAT shown but not added, with the HMRC wording', () {
    debugSetMarket(Market.uk);
    final t = billTotals([_labour, _materials], gstRate: 20, tdsPct: 20, reverseCharge: true);
    expect(t.reverseCharge, isTrue);
    expect(t.gst, 800);
    expect(t.invoiceTotal, 4000);
    expect(t.netPayable, 3500);
    expect(reverseChargeLine(t.gst, 20),
        'Reverse charge: Customer to account to HMRC for the reverse charge VAT of £800.00 at 20%. (S55A VATA 1994 applies.)');
    final normal = billTotals([_labour], gstRate: 20);
    expect(normal.invoiceTotal, 3000);
    // Zero-rated work is never reverse charged.
    expect(billTotals([_labour], gstRate: 0, reverseCharge: true).reverseCharge, isFalse);
  });

  test('reverse charge exists only where the law has it, and the flag rides in the SAC column', () {
    expect(billTotals([_labour], gstRate: 18, reverseCharge: true).reverseCharge, isFalse);
    expect(isReverseCharge('DRC'), isFalse); // India: the column is a real SAC
    debugSetMarket(Market.uae);
    expect(billTotals([_labour], gstRate: 5, reverseCharge: true).reverseCharge, isFalse);
    debugSetMarket(Market.uk);
    expect(isReverseCharge(reverseChargeMark), isTrue);
    expect(isReverseCharge(''), isFalse);
    expect(isReverseCharge('995411'), isFalse);
  });

  test('UK VAT numbers: HMRC mod 97, both series, branches and government', () {
    for (final ok in ['GB980780684', 'GB 980 7806 84', '980780684', 'GB434031494', 'GB980780684001', 'GBGD001', 'GBHA599']) {
      expect(isValidUkVat(ok), isTrue, reason: ok);
    }
    for (final bad in ['GB980780685', 'GB12345678', 'GBGD500', 'GBHA499', 'FR12345678901', '']) {
      expect(isValidUkVat(bad), isFalse, reason: bad);
    }
    debugSetMarket(Market.uk);
    expect(normaliseTaxId('980 780 684'), 'GB980780684');
    expect(normaliseTaxId('gb980780684'), 'GB980780684');
    expect(validTaxId('GB980780684'), isTrue);
    expect(marketInvoiceTitle(ourTaxId: 'GB980780684'), 'VAT INVOICE');
    expect(marketInvoiceTitle(ourTaxId: ''), 'INVOICE');
  });

  test('UK English: application for payment, site diary, hourly pay', () {
    debugSetMarket(Market.uk);
    expect(trIn(AppLanguage.en, 'Make the next RA bill'), 'Make the next application for payment');
    expect(trIn(AppLanguage.en, 'DPR'), 'Site diary');
    expect(trIn(AppLanguage.en, 'GST'), 'VAT');
    expect(trIn(AppLanguage.en, '{amount}/day'), '{amount}/hr');
    expect(trIn(AppLanguage.en, 'Punch in'), 'Sign in');
  });

  test('the UK offers English, Polish and Romanian, with their own voices', () {
    debugSetMarket(Market.uk);
    expect(AppLanguage.offered, [AppLanguage.en, AppLanguage.pl, AppLanguage.ro]);
    expect(AppLanguage.en.locale, const Locale('en', 'GB'));
    expect(AppLanguage.pl.locale, const Locale('pl', 'PL'));
    expect(AppLanguage.ro.locale, const Locale('ro', 'RO'));
    expect(AppLanguage.pl.latinScript && AppLanguage.ro.latinScript, isTrue);
    expect(AppLanguage.pl.rightToLeft || AppLanguage.ro.rightToLeft, isFalse);
    for (final l in AppLanguage.offered) {
      expect(kMaterialSupportedLanguages, contains(l.code), reason: '${l.code} needs Material texts');
    }
    for (final l in [AppLanguage.pl, AppLanguage.ro]) {
      expect(trIn(l, 'Cancel'), isNot('Cancel'));
      expect(trIn(l, market.minimumWage!.note), isNot(market.minimumWage!.note), reason: l.code);
      expect(trIn(l, 'Amount (₹)'), contains('£'), reason: l.code);
    }
  });

  test('CIS rates: gross payment 0%, registered 20%, not registered 30%', () {
    debugSetMarket(Market.uk);
    expect([for (final w in market.tax.withholdingRates) w.pct], [0, 20, 30]);
    for (final l in AppLanguage.values.where((l) => l != AppLanguage.en)) {
      for (final w in market.tax.withholdingRates) {
        expect(trIn(l, w.label), isNot(w.label), reason: '${l.code}: ${w.label}');
      }
    }
    debugSetMarket(Market.india);
    expect(market.tax.withholdingRates, isEmpty, reason: 'India types its TDS rate');
  });
}
