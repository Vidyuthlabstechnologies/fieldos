/// Notes that are stored or produced in English (an approval's note, the
/// cost agent's alerts) and shown in the person's language: the English
/// stays the record everyone shares, and each phone translates it when it
/// shows it. A note that matches none of these is shown as written.
library;

import 'package:fieldos_mobile/l10n/language.dart';

final _patterns = <(RegExp, String, List<String>)>[
  (RegExp(r'^Spending is (.+) over the BOQ budget\.$'), 'Spending is {amount} over the BOQ budget.', ['amount']),
  (RegExp(r'^Over budget on (.+): spent (.+) of (.+)\.$'), 'Over budget on {item}: spent {spent} of {budget}.',
      ['item', 'spent', 'budget']),
  (RegExp(r'^Close to budget on (.+): (.+) of (.+) \((\d+)%\)\.$'),
      'Close to budget on {item}: {spent} of {budget} ({pct}%).', ['item', 'spent', 'budget', 'pct']),
  (RegExp(r'^(.+) spent without a BOQ item\.$'), '{amount} spent without a BOQ item.', ['amount']),
];

/// [note] in the person's language when it is one of the app's own.
String trStoredNote(String note) {
  for (final (re, label, names) in _patterns) {
    final m = re.firstMatch(note);
    if (m == null) continue;
    return trf(label, {for (var i = 0; i < names.length; i++) names[i]: m.group(i + 1)!});
  }
  return note;
}

/// The labels above, for the translation tests.
List<String> get storedNoteLabels => [for (final p in _patterns) p.$2];
