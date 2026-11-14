// The app bundles a Latin subset of Inter (tools/subset_fonts.sh). Any
// letter a Latin-script language uses must be in that subset, or the phone
// draws it in another font in the middle of a word (Polish ł and Romanian ș
// did, before the subset took Latin Extended-A).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<(int, int)> _subsetRanges() {
  final script = File('../tools/subset_fonts.sh').readAsStringSync();
  final spec = RegExp(r'--unicodes="([^"]+)"').firstMatch(script)!.group(1)!;
  return [
    for (final part in spec.split(','))
      if (part.contains('-'))
        (int.parse(part.substring(2).split('-')[0], radix: 16), int.parse(part.split('-')[1], radix: 16))
      else
        (int.parse(part.substring(2), radix: 16), int.parse(part.substring(2), radix: 16)),
  ];
}

void main() {
  test('every Latin letter in the Latin-script languages is in the bundled Inter', () {
    final ranges = _subsetRanges();
    bool covered(int c) => ranges.any((r) => c >= r.$1 && c <= r.$2);
    final files = Directory('lib/l10n')
        .listSync()
        .whereType<File>()
        .where((f) => RegExp(r'strings_(\w+_)?(es|ms|pl|ro)\.dart$').hasMatch(f.path));
    expect(files, isNotEmpty);
    final missing = <String>{};
    for (final f in files) {
      for (final c in f.readAsStringSync().runes) {
        // Latin letters and marks only; other scripts fall back on purpose.
        if (c >= 0x00A0 && c < 0x0250 && !covered(c)) missing.add('${String.fromCharCode(c)} in ${f.path}');
      }
    }
    expect(missing, isEmpty, reason: 'add these to tools/subset_fonts.sh and rerun it');
  });
}
