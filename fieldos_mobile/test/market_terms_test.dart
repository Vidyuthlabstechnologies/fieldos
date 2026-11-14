/// The US app (and, as their tables land, the other non-Indian apps) must
/// not show India-only words: GST, TDS, lakh, ₹, DPR, RA bill... Every
/// label the app passes to tr() is checked after the market's wording and
/// word swaps. Labels that only appear on India-only screens (RERA, PF/ESI
/// salaries, UPI, Tally, the IGST switches) are listed with the gate that
/// hides them.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/market_terms.dart';

import 'l10n_coverage_test.dart' show labelsInSource;

final _indiaOnly = RegExp(
    r'\b(GST|GSTIN|CGST|SGST|IGST|TDS|SAC|HSN|PAN|UPI|lakhs?|crores?|DPR|RA|paise|rupees?|Rs|RERA|BOCW|PF|ESIC?|Aadhaar|challan|Tally|labour)\b|₹',
    caseSensitive: false);

/// Shown only behind `isIndia` (see each note).
const _hiddenOutsideIndia = {
  // Staff salaries (PF, ESI, professional tax): home menu, isIndia.
  'Add the people on a monthly salary. Each month FieldOS works out their pay for the days worked, PF, ESI, professional tax and advance recovery, and makes the payslips.',
  'Cut when the salary is ₹21,000 or less', 'Not cut: salary is above ₹21,000', 'ESI', 'ESI to deposit', 'PF to deposit',
  'Provident fund (PF)', 'Provident fund', 'Basic a month (₹)', 'HRA (₹)',
  // RERA: project menu and reminders, isIndia.
  'As on the RERA certificate', 'Progress is as recorded on site. The architect certifies the stage of completion for RERA.',
  'RERA quarterly report', 'RERA quarterly report is due', 'RERA quarterly report: 5 days left', 'RERA registration number',
  'Upload to TS-RERA by {date}',
  // GST registration and the CGST/SGST/IGST split: bill, quote and expense forms, isIndia.
  'Add your GSTIN, address and UPI id', 'Client GSTIN (optional)', 'Client is in another state (IGST)',
  'For building work, GST follows the state where the site is. Inside your state it splits into CGST and SGST',
  'Add your GSTIN in "Your details on bills" first. Without it a bill cannot charge GST; pick None.', 'Other state (IGST)', 'Supplier in another state (IGST)',
  "That GSTIN doesn't look right, so it wasn't saved.", "That GSTIN doesn't look right. It has 15 characters, like 36ABCDE1234F1Z5.",
  'Your GSTIN', 'UPI id for payments (optional)', 'TDS %',
  // Tally export: accounts sheet, isIndia.
  'Tally vouchers (XML)', 'Tally vouchers or a Zoho Books file, with GST split out',
};

void main() {
  tearDown(() {
    debugSetMarket(Market.india);
    setCurrentLanguage(AppLanguage.en);
  });

  test('the US app shows no India-only words', () {
    debugSetMarket(Market.us);
    final leaks = <String>[];
    for (final label in labelsInSource()) {
      if (_hiddenOutsideIndia.contains(label)) continue;
      final shown = tr(label);
      if (_indiaOnly.hasMatch(shown.replaceAll(RegExp(r'\{\w+\}'), ''))) leaks.add('$label  ->  $shown');
    }
    leaks.sort();
    expect(leaks, isEmpty, reason: '${leaks.length} labels still read as Indian:\n${leaks.join('\n')}');
  });

  test('every hidden label is still in the app (or drop it from the list)', () {
    final labels = labelsInSource();
    expect(_hiddenOutsideIndia.where((l) => !labels.contains(l)), isEmpty);
  });

  test('the US wording keeps the placeholders of the English key', () {
    final placeholder = RegExp(r'\{\w+\}');
    marketTerms.forEach((m, byLang) {
      byLang.forEach((lang, table) {
        table.forEach((en, out) {
          expect(placeholder.allMatches(out).map((x) => x[0]).toSet(),
              placeholder.allMatches(en).map((x) => x[0]).toSet(), reason: '$m/$lang: $en');
        });
      });
    });
  });

  test('word swaps keep case and leave placeholders alone', () {
    expect(applyWordSwaps(Market.us, 'Labour on site'), 'Labor on site');
    expect(applyWordSwaps(Market.us, 'Send the DPR'), 'Send the Daily log');
    expect(applyWordSwaps(Market.us, '{gst}% GST'), '{gst}% Sales tax');
    expect(applyWordSwaps(Market.us, 'labourers'), 'laborers');
    expect(applyWordSwaps(Market.india, 'Labour'), 'Labour');
  });

  test('India is untouched by market wording', () {
    expect(tr('GST'), 'GST');
    expect(tr('Labour'), 'Labour');
    expect(tr('Amount (₹)'), 'Amount (₹)');
  });

  test('US: currency sign and tax name in labels', () {
    debugSetMarket(Market.us);
    expect(tr('Amount (₹)'), r'Amount ($)');
    expect(tr('GST'), 'Sales tax');
    expect(tr('Labour'), 'Labor');
  });
}
