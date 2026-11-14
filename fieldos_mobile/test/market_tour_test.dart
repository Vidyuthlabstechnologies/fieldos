/// Outside India the tour tells its own story: no Namaste, no Mr. Reddy's
/// G+1 house, no rupees or GST; the sample client is a local name; budget
/// notes stored in English show in the person's language.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/stored_notes.dart';
import 'package:fieldos_mobile/services/read_aloud.dart';

void main() {
  tearDown(() {
    debugSetMarket(Market.india);
    setCurrentLanguage(AppLanguage.en);
    setSpokenLanguage(AppLanguage.en);
  });

  test('India keeps its tour', () {
    debugSetMarket(Market.india);
    final text = appTourSteps().map((s) => '${s.title} ${s.body}').join('\n');
    expect(text, contains('Namaste'));
    expect(text, contains('Mr. Reddy'));
    expect(sampleClient, 'Mr. Reddy');
  });

  test('every other market tells its own story, in each of its languages', () {
    for (final m in Market.values.where((m) => m != Market.india)) {
      debugSetMarket(m);
      expect(sampleClient, isNot('Mr. Reddy'));
      for (final l in AppLanguage.offered) {
        setCurrentLanguage(l);
        setSpokenLanguage(l);
        final text = appTourSteps().map((s) => '${s.title} ${s.body}').join('\n');
        for (final word in ['Namaste', 'Reddy', 'G+1', 'GST', '₹', 'rupee', 'WhatsApp', 'Telugu']) {
          expect(text, isNot(contains(word)), reason: '${m.name} ${l.code}: $word');
        }
        for (var i = 0; i < appTourSteps().length; i++) {
          final spoken = ReadAloud.guideText('tour_$i', fallback: 'screen');
          expect(spoken ?? '', isNot(contains('Reddy')), reason: '${m.name} ${l.code} tour_$i');
        }
      }
    }
  });

  test('stored budget notes show in the person\'s language', () {
    debugSetMarket(Market.india);
    for (final l in AppLanguage.values.where((l) => l != AppLanguage.en)) {
      for (final label in storedNoteLabels) {
        expect(hasTranslation(l, label), isTrue, reason: '${l.code}: $label');
      }
    }
    expect(trStoredNote('Spending is ₹25,000 over the BOQ budget.'), 'Spending is ₹25,000 over the BOQ budget.');
    expect(trStoredNote('Something else.'), 'Something else.');
    setCurrentLanguage(AppLanguage.hi);
    final hi = trStoredNote('Over budget on Cement: spent ₹1,200 of ₹1,000.');
    expect(hi, isNot(startsWith('Over budget')));
    expect(hi, contains('Cement'));
    expect(hi, contains('₹1,200'));
  });

  test('UK Polish and Romanian: hourly pay wording and a £500 example', () {
    debugSetMarket(Market.uk);
    for (final l in [AppLanguage.pl, AppLanguage.ro]) {
      expect(trIn(l, 'Add ₹5,000 spent on cement'), contains('£500'), reason: l.code);
      expect(trIn(l, 'Daily wage (₹)'), contains('£'), reason: l.code);
      final note = trIn(l, 'A day counts as full at 7 hours on site and half at 3.5 hours, unless it was marked by hand on the day register. Tap a worker to pay wages or an advance.');
      expect(note, isNot(contains('3,5')), reason: l.code);
      expect(note, contains('48'), reason: l.code);
    }
    debugSetMarket(Market.india);
    expect(trIn(AppLanguage.hi, 'Add ₹5,000 spent on cement'), contains('5,000'));
  });

  test('the late beam has the local trade name, and the tour never says plinth outside India', () {
    debugSetMarket(Market.india);
    expect(sampleBeam, 'Plinth beam');
    debugSetMarket(Market.us);
    expect(sampleBeam, 'Grade beam');
    expect(appTourSteps().map((s) => s.body).join('\n'), contains('grade beam'));
    for (final m in [Market.malaysia, Market.uae, Market.uk]) {
      debugSetMarket(m);
      expect(sampleBeam, 'Ground beam');
      for (final l in AppLanguage.offered) {
        setCurrentLanguage(l);
        final text = appTourSteps().map((s) => s.body).join('\n').toLowerCase();
        expect(text, isNot(contains('plinth')), reason: '${m.name} ${l.code}');
      }
    }
  });

  test('Purchase request is translated in every language', () {
    for (final l in AppLanguage.values.where((l) => l != AppLanguage.en)) {
      expect(hasTranslation(l, 'Purchase request'), isTrue, reason: l.code);
    }
  });

  test('in Arabic and Urdu a filled-in amount is kept in its own direction', () {
    setCurrentLanguage(AppLanguage.ar);
    expect(trf('{amount}/day', {'amount': 'AED 100'}), contains('\u2068AED 100\u2069'));
    setCurrentLanguage(AppLanguage.hi);
    expect(trf('{amount}/day', {'amount': '₹100'}), isNot(contains('\u2068')));
  });
}
