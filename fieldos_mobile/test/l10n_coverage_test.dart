/// Hindi and Telugu: every label the app passes to tr()/trf() (and to
/// showSnack and SectionHeader, which translate inside) has an entry in
/// both tables, placeholders survive translation, and switching language
/// changes what tr() returns.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/strings_hi.dart';
import 'package:fieldos_mobile/l10n/strings_te.dart';

// A single- or double-quoted Dart string literal (\x22 is the double quote).
const _lit = r"'(?:[^'\\\n]|\\.)*'|\x22(?:[^\x22\\\n]|\\.)*\x22";
final _literal = RegExp(r"'((?:[^'\\\n]|\\.)*)'|\x22((?:[^\x22\\\n]|\\.)*)\x22");
final _calls = [
  RegExp(r'\b(?:tr|trf)\(\s*((?:(?:' + _lit + r')\s*)+)'),
  RegExp(r'\b(?:showSnack\(\s*\w+,\s*|SectionHeader\(\s*)((?:(?:' + _lit + r')\s*)+)[,)]'),
];

/// Every literal label in lib/, as the English key tr() looks up.
Set<String> labelsInSource() {
  final out = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.contains('${Platform.pathSeparator}l10n${Platform.pathSeparator}')) {
      continue;
    }
    final src = f.readAsStringSync();
    for (final rx in _calls) {
      for (final m in rx.allMatches(src)) {
        final key = _literal
            .allMatches(m.group(1)!)
            .map((p) => p.group(1) ?? p.group(2)!)
            .join()
            .replaceAll(r"\'", "'")
            .replaceAll(r'\"', '"');
        if (!key.contains(r'$')) out.add(key);
      }
    }
  }
  return out;
}

void main() {
  tearDown(() => setCurrentLanguage(AppLanguage.en));

  test('every label has Hindi and Telugu', () {
    final labels = labelsInSource();
    expect(labels.length, greaterThan(350));
    for (final (name, table) in [('Hindi', stringsHi), ('Telugu', stringsTe)]) {
      final missing = labels.where((l) => (table[l] ?? '').trim().isEmpty).toList()..sort();
      expect(missing, isEmpty, reason: '$name is missing ${missing.length} labels');
    }
  });

  test('translations keep their placeholders and are not left in English', () {
    final placeholder = RegExp(r'\{\w+\}');
    for (final table in [stringsHi, stringsTe]) {
      table.forEach((en, t) {
        expect(
          placeholder.allMatches(t).map((m) => m[0]).toSet(),
          placeholder.allMatches(en).map((m) => m[0]).toSet(),
          reason: en,
        );
      });
      final untouched = table.entries
          .where((e) => e.key == e.value && e.key.contains(RegExp('[a-z]{3}')) && !e.key.startsWith('e.g.'))
          .map((e) => e.key);
      expect(untouched, isEmpty);
    }
  });

  test('tr follows the chosen language and falls back to English', () {
    expect(tr('Save report'), 'Save report');
    setCurrentLanguage(AppLanguage.hi);
    expect(tr('Save report'), 'रिपोर्ट सेव करें');
    expect(trf('{n} tasks late', {'n': 3}), '3 काम देर से');
    setCurrentLanguage(AppLanguage.te);
    expect(tr('Save report'), 'రిపోర్ట్ సేవ్ చేయండి');
    expect(tr('Something not in the table'), 'Something not in the table');
  });

  test('a phone set to Hindi or Telugu starts in it, anything else in English', () {
    expect(languageFromDevice(const [Locale('te', 'IN')]), AppLanguage.te);
    expect(languageFromDevice(const [Locale('fr'), Locale('hi', 'IN')]), AppLanguage.hi);
    expect(languageFromDevice(const [Locale('en', 'GB')]), AppLanguage.en);
    expect(AppLanguage.fromCode('xx'), isNull);
  });
}
