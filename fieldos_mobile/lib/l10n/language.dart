/// The person's language: English, Hindi, Telugu, Tamil, Kannada or
/// Marathi. It is theirs to pick (the app asks on first launch, and
/// Settings can change it), never guessed and forced on them.
///
/// Picking a language changes how FieldOS talks and listens: Mitra's
/// guide, read-aloud and voice input use it, mixed with English the way
/// people really speak. Screens stay in English unless the person also
/// switches on "Show screens in Telugu" (and so on) ([screensInLanguageKey]);
/// then every label goes through [tr], which looks the English text up in
/// that language's table and falls back to English for anything missing.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/l10n/strings_hi.dart';
import 'package:fieldos_mobile/l10n/strings_kn.dart';
import 'package:fieldos_mobile/l10n/strings_mr.dart';
import 'package:fieldos_mobile/l10n/strings_ta.dart';
import 'package:fieldos_mobile/l10n/strings_te.dart';
import 'package:fieldos_mobile/providers.dart';

enum AppLanguage {
  en('en', 'English', 'English'),
  hi('hi', 'हिन्दी', 'Hindi'),
  te('te', 'తెలుగు', 'Telugu'),
  ta('ta', 'தமிழ்', 'Tamil'),
  kn('kn', 'ಕನ್ನಡ', 'Kannada'),
  mr('mr', 'मराठी', 'Marathi');

  const AppLanguage(this.code, this.nativeName, this.englishName);
  final String code;

  /// The name in its own script, as shown in the picker.
  final String nativeName;
  final String englishName;

  Locale get locale => Locale(code, 'IN');

  static AppLanguage? fromCode(String? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return null;
  }
}

const languageSettingKey = 'app_language';

/// '1' when the person wants every screen in their language too.
const screensInLanguageKey = 'screens_in_language';

const Map<AppLanguage, Map<String, String>> _tables = {
  AppLanguage.hi: stringsHi,
  AppLanguage.te: stringsTe,
  AppLanguage.ta: stringsTa,
  AppLanguage.kn: stringsKn,
  AppLanguage.mr: stringsMr,
};

/// The speech code (BCP-47) for [l], for the phone's voice and its
/// speech recognition: 'ta-IN'.
String speechCodeFor(AppLanguage l) => '${l.code}-IN';

AppLanguage _current = AppLanguage.en;
AppLanguage _spoken = AppLanguage.en;
bool _screensOn = false;

/// The language the screens are in now, the one [tr] uses.
AppLanguage get currentLanguage => _current;

/// Sets the language for [tr]. The app calls this through
/// [languageProvider]; tests call it directly.
void setCurrentLanguage(AppLanguage l) => _current = l;

/// The language the person picked: Mitra speaks it and voice input listens
/// for it, whatever language the screens are in.
AppLanguage get spokenLanguage => _spoken;

/// Sets the spoken language directly; the app goes through
/// [languageProvider], tests call this.
void setSpokenLanguage(AppLanguage l) => _spoken = l;

/// Whether the screens follow [spokenLanguage] (otherwise English).
bool get screensInLanguage => _screensOn;

void _apply(AppLanguage spoken, bool screens) {
  _spoken = spoken;
  _screensOn = screens;
  _current = screens ? spoken : AppLanguage.en;
}

/// [english] in language [l], or [english] when there is no translation.
String trIn(AppLanguage l, String english) => _tables[l]?[english] ?? english;

/// [english] in the person's spoken language, for words read aloud.
String trSpoken(String english) => trIn(_spoken, english);

/// [english] in the current language, or [english] itself when there is
/// no translation.
String tr(String english) => _tables[_current]?[english] ?? english;

/// [tr] with `{name}` placeholders filled in after the lookup:
/// `trf('{n} tasks late', {'n': '3'})`.
String trf(String english, Map<String, Object> args) {
  var s = tr(english);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

/// The phone's own language when FieldOS has it, else English: the first
/// launch offers it first, but nothing changes until the person taps.
AppLanguage languageFromDevice([List<Locale>? locales]) {
  for (final l in locales ?? PlatformDispatcher.instance.locales) {
    final found = AppLanguage.fromCode(l.languageCode);
    if (found != null) return found;
  }
  return AppLanguage.en;
}

class LanguageController extends Notifier<AppLanguage> {
  /// Set once the person picks, so a slower load of the saved setting
  /// can't undo their choice.
  bool _picked = false;

  @override
  AppLanguage build() {
    _load();
    return _spoken;
  }

  Future<void> _load() async {
    final settings = ref.read(appDatabaseProvider).settingsDao;
    final saved = AppLanguage.fromCode(await settings.get(languageSettingKey));
    final screens = await settings.get(screensInLanguageKey) == '1';
    if (!ref.mounted || _picked) return;
    _apply(saved ?? AppLanguage.en, screens);
    state = _spoken;
    ref.read(screensInLanguageProvider.notifier).sync();
  }

  Future<void> choose(AppLanguage l) async {
    _picked = true;
    _apply(l, _screensOn);
    state = l;
    ref.read(screensInLanguageProvider.notifier).sync();
    await ref.read(appDatabaseProvider).settingsDao.set(languageSettingKey, l.code);
    ref.invalidate(languageChosenProvider);
  }
}

final languageProvider = NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);

/// Whether the screens are in the person's language too (off: English).
class ScreensInLanguageController extends Notifier<bool> {
  @override
  bool build() => _screensOn;

  /// Picks up a change made through [LanguageController].
  void sync() => state = _screensOn;

  Future<void> set(bool on) async {
    _apply(_spoken, on);
    state = on;
    await ref.read(appDatabaseProvider).settingsDao.set(screensInLanguageKey, on ? '1' : '0');
  }
}

final screensInLanguageProvider =
    NotifierProvider<ScreensInLanguageController, bool>(ScreensInLanguageController.new);

/// False until the person has picked a language, so the first launch asks.
final languageChosenProvider = FutureProvider<bool>(
    (ref) async => await ref.read(appDatabaseProvider).settingsDao.get(languageSettingKey) != null);
