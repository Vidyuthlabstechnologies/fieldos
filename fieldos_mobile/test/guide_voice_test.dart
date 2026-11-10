/// Mitra's guide voice: every language has every line, recorded clips
/// match the lines they were made from, and the first launch asks for a
/// language without forcing one or turning the screens into it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/tour/app_tour.dart';
import 'package:fieldos_mobile/features/tour/guide_lines.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/language_welcome.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/read_aloud.dart';

void main() {
  tearDown(() {
    setCurrentLanguage(AppLanguage.en);
    setSpokenLanguage(AppLanguage.en);
  });

  test('every language has a voice, a greeting and one line per tour step', () {
    final keys = {'greet', for (var i = 0; i < appTourSteps().length; i++) 'tour_$i'};
    for (final l in AppLanguage.values) {
      expect(guideVoices[l.code], isNotNull, reason: l.englishName);
      expect(guideLines[l.code]?.keys.toSet(), keys, reason: l.englishName);
      for (final line in guideLines[l.code]!.values) {
        expect(line.trim(), isNotEmpty);
        expect(line.length, lessThan(2500), reason: "Sarvam's limit per request");
      }
    }
  });

  test('Indian-language lines keep everyday English words, the way people talk', () {
    for (final l in AppLanguage.values.where((l) => l != AppLanguage.en)) {
      expect(guideLines[l.code]!['tour_1'], contains('sites'), reason: l.englishName);
      expect(guideLines[l.code]!['tour_1'], contains('list'), reason: l.englishName);
    }
  });

  test('every recorded clip exists and matches its current line', () {
    final manifest = jsonDecode(File('assets/voice/manifest.json').readAsStringSync()) as Map<String, dynamic>;
    manifest.forEach((lang, clips) {
      (clips as Map<String, dynamic>).forEach((key, text) {
        expect(File('assets/voice/$lang/$key.mp3').existsSync(), isTrue, reason: '$lang/$key');
        expect(text, guideLines[lang]?[key], reason: '$lang/$key was recorded from older words; re-run make_clips.py');
      });
    });
  });

  test('guide text follows the spoken language, with a fallback', () {
    setSpokenLanguage(AppLanguage.ta);
    expect(ReadAloud.guideText('tour_0'), guideLines[spokenLanguage.code]!['tour_0']);
    expect(ReadAloud.guideText('no_such_line', fallback: 'x'), 'x');
    expect(ReadAloud.localeFor('ఇక్కడ మీ sites'), 'te-IN');
    expect(ReadAloud.localeFor('Hello'), 'en-IN');
  });

  test("the phone's language is offered first, but every language is there", () {
    expect(LanguageWelcomeScreen.order(const [Locale('kn', 'IN')]).first, AppLanguage.kn);
    expect(LanguageWelcomeScreen.order(const [Locale('en', 'US')]).first, AppLanguage.en);
    expect(LanguageWelcomeScreen.order(const [Locale('ta', 'IN')]).toSet(), AppLanguage.values.toSet());
  });

  testWidgets('first launch: picking Telugu saves it, and the screens stay English', (tester) async {
    final db = AppDatabase.memory();
    final container = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    expect(await tester.runAsync(() => container.read(languageChosenProvider.future)), isFalse);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildFieldOsTheme(Brightness.light), home: const LanguageWelcomeScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Which language do you speak?'), findsOneWidget);
    for (final l in AppLanguage.values) {
      expect(find.text(l.nativeName), findsOneWidget);
    }
    await tester.tap(find.text('తెలుగు'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(await tester.runAsync(() => db.settingsDao.get(languageSettingKey)), 'te');
    expect(spokenLanguage, AppLanguage.te);
    expect(currentLanguage, AppLanguage.en, reason: 'screens stay English unless switched on');
    expect(await tester.runAsync(() => container.read(languageChosenProvider.future)), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
