// Dates on screen follow the screens' language; documents for clients and
// suppliers stay English.
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  final d = DateTime(2026, 11, 6, 9, 5);
  final sameYear = DateTime(2026, 12, 1);
  final nextYear = DateTime(2027, 2, 1);

  tearDown(() {
    setCurrentLanguage(AppLanguage.en);
    debugSetMarket(Market.india);
  });

  test('English keeps its own short form on every market', () {
    expect(fmtDate(d), '6 Nov 2026');
    expect(fmtDate(d, short: true, now: sameYear), '6 Nov');
    debugSetMarket(Market.us);
    expect(fmtDate(d), 'Nov 6, 2026');
  });

  test('screens in another language show its month names', () {
    setCurrentLanguage(AppLanguage.hi);
    expect(fmtDate(d, short: true, now: sameYear), contains('नव'));
    expect(fmtDate(d, now: nextYear), allOf(contains('2026'), contains('6')));
    setCurrentLanguage(AppLanguage.es);
    expect(fmtDate(d, short: true, now: sameYear), contains('nov'));
    setCurrentLanguage(AppLanguage.zh);
    expect(fmtDate(d, short: true, now: sameYear), contains('11月6日'));
    setCurrentLanguage(AppLanguage.pl);
    expect(fmtDate(d, short: true, now: sameYear), contains('lis'));
  });

  test('Arabic and Urdu months keep 0-9 digits, like the money beside them', () {
    for (final l in [AppLanguage.ar, AppLanguage.ur]) {
      setCurrentLanguage(l);
      final s = fmtDate(d, now: nextYear);
      expect(s, contains('2026'), reason: l.code);
      expect(RegExp('[٠-٩۰-۹]').hasMatch(s), isFalse, reason: s);
      expect(RegExp('[A-Za-z]').hasMatch(s), isFalse, reason: 'month in English: $s');
    }
  });

  test('every offered language formats without throwing', () {
    for (final l in AppLanguage.values) {
      setCurrentLanguage(l);
      expect(fmtDate(d), isNotEmpty, reason: l.code);
      expect(fmtDay(d, now: sameYear), isNotEmpty, reason: l.code);
    }
  });

  test('documents stay English whatever the screens show', () {
    setCurrentLanguage(AppLanguage.te);
    expect(fmtDate(d, english: true), '6 Nov 2026');
    expect(fmtDay(d, now: d, english: true), 'Today');
    expect(fmtDateTime(d, now: DateTime(2026, 11, 7), english: true), startsWith('Yesterday, '));
  });
}
