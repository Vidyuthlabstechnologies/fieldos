/// A message a form shows when it refuses something ("Say what you did.") is
/// translated in every language (customer review: about two thirds of them
/// appeared in English on a Hindi or Telugu screen).
///
/// The messages are found in the code itself: every `ArgumentError('...')` a
/// screen can show. Add a new one without a translation and this fails.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/l10n/language.dart';

/// Thrown for a programmer, never shown to a person.
const _developerOnly = {
  'accepted quantity below zero',
  'cast day and grade',
  'cutoff outside the day',
};

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  final messages = <String>{};
  final re = RegExp(r"ArgumentError\(\s*'((?:[^'\\]|\\.)*)'");
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
    for (final m in re.allMatches(f.readAsStringSync())) {
      final text = m.group(1)!.replaceAll("\\'", "'");
      if (text.contains(r'$') || _developerOnly.contains(text)) continue;
      messages.add(text);
    }
  }

  test('the messages were found', () => expect(messages.length, greaterThan(40)));

  for (final lang in AppLanguage.values.where((l) => l != AppLanguage.en)) {
    test('every form message reads in ${lang.code}', () {
      setCurrentLanguage(lang);
      final english = [for (final m in messages) if (tr(m) == m) m]..sort();
      expect(english, isEmpty, reason: 'shown in English on a ${lang.code} screen:\n${english.join('\n')}');
    });
  }
}
