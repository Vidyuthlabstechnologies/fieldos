/// The app's own language: English, Hindi or Telugu. Every label goes
/// through [tr], which looks the English text up in the chosen language's
/// table and falls back to English for anything not yet translated, so a
/// missing entry shows English rather than a blank or a key.
///
/// The choice is kept on the phone (settings key [languageSettingKey]).
/// Before anyone picks, a phone set to Hindi or Telugu starts in that
/// language.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/l10n/strings_hi.dart';
import 'package:fieldos_mobile/l10n/strings_te.dart';
import 'package:fieldos_mobile/providers.dart';

enum AppLanguage {
  en('en', 'English', 'English'),
  hi('hi', 'हिन्दी', 'Hindi'),
  te('te', 'తెలుగు', 'Telugu');

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

const Map<AppLanguage, Map<String, String>> _tables = {AppLanguage.hi: stringsHi, AppLanguage.te: stringsTe};

AppLanguage _current = AppLanguage.en;

/// The language [tr] is using now.
AppLanguage get currentLanguage => _current;

/// Sets the language for [tr]. The app calls this through
/// [languageProvider]; tests call it directly.
void setCurrentLanguage(AppLanguage l) => _current = l;

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

/// Hindi or Telugu when the phone is set to it, else English.
AppLanguage languageFromDevice([List<Locale>? locales]) {
  for (final l in locales ?? PlatformDispatcher.instance.locales) {
    final found = AppLanguage.fromCode(l.languageCode);
    if (found != null) return found;
  }
  return AppLanguage.en;
}

class LanguageController extends Notifier<AppLanguage> {
  @override
  AppLanguage build() {
    _load();
    return _current;
  }

  Future<void> _load() async {
    final saved = AppLanguage.fromCode(await ref.read(appDatabaseProvider).settingsDao.get(languageSettingKey));
    final l = saved ?? languageFromDevice();
    if (!ref.mounted) return;
    setCurrentLanguage(l);
    state = l;
  }

  Future<void> choose(AppLanguage l) async {
    setCurrentLanguage(l);
    state = l;
    await ref.read(appDatabaseProvider).settingsDao.set(languageSettingKey, l.code);
  }
}

final languageProvider = NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);
