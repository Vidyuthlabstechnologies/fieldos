/// Malaysia's wage sheet flags a daily rate under the minimum wage, for
/// the company's working week; other markets set no national floor here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet.dart';
import 'package:fieldos_mobile/l10n/language.dart';

void main() {
  tearDown(() => debugSetMarket(Market.india));

  test('India, the US, UAE and UK: no check', () {
    for (final m in [Market.india, Market.us, Market.uae]) {
      debugSetMarket(m);
      expect(market.minimumWage, isNull, reason: m.name);
      expect(belowMinimumWage(10, const PayCalendar()), isNull);
    }
  });

  test('Malaysia: RM1,700 a month as a daily rate for the working week', () {
    debugSetMarket(Market.malaysia);
    final min = market.minimumWage!;
    expect(min.monthly, 1700);
    expect(min.dailyFor(6), 65.38);
    expect(min.dailyFor(5), 78.46);
    expect(min.dailyFor(4), 98.08);
    expect(min.dailyFor(7), 65.38); // clamped
    // The Order's own hourly rate: RM1,700 x 12 / 52 weeks / 45 hours.
    expect(min.hourly, 8.72);
    expect(min.hourly, closeTo(1700 * 12 / 52 / 45, 0.01));

    const sixDays = PayCalendar(restDays: {DateTime.sunday});
    const fiveDays = PayCalendar(restDays: {DateTime.saturday, DateTime.sunday});
    expect(belowMinimumWage(60, sixDays), 65.38);
    expect(belowMinimumWage(65.38, sixDays), isNull);
    expect(belowMinimumWage(70, sixDays), isNull);
    expect(belowMinimumWage(70, fiveDays), 78.46);
    expect(belowMinimumWage(60, const PayCalendar()), 65.38); // default: Sunday off
    expect(belowMinimumWage(null, sixDays), isNull);
    expect(belowMinimumWage(0, sixDays), isNull);
  });

  test('UK: the National Living Wage, by the hour', () {
    debugSetMarket(Market.uk);
    expect(market.minimumWage!.hourly, 12.71);
    expect(belowMinimumWage(12, const PayCalendar()), 12.71);
    expect(belowMinimumWage(12.71, const PayCalendar()), isNull);
    expect(belowMinimumWage(15, const PayCalendar()), isNull);
  });

  test('the Sabah and Sarawak note reads in every Malaysian language', () {
    debugSetMarket(Market.malaysia);
    final note = market.minimumWage!.note;
    expect(note, contains('Sabah'));
    expect(note, contains('Sarawak'));
    for (final l in [AppLanguage.ms, AppLanguage.zh, AppLanguage.ta]) {
      expect(hasTranslation(l, note), isTrue, reason: l.name);
    }
  });
}
