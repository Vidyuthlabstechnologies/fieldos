/// Number fields accept the digits an Arabic or Urdu keyboard types.
library;

import 'package:flutter/services.dart';

import 'package:fieldos_mobile/core/format.dart';

/// Turns ٠-٩ and ۰-۹ into 0-9 as they are typed, so a field that allows
/// only [0-9.] (or digitsOnly) still takes them. Put it first in
/// inputFormatters.
class WesternDigitsFormatter extends TextInputFormatter {
  const WesternDigitsFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final t = westernDigits(newValue.text);
    if (t == newValue.text) return newValue;
    // Dropped marks shorten the text: keep the cursor at the same place
    // counted from the end.
    final fromEnd = newValue.text.length - newValue.selection.extentOffset;
    final at = (t.length - fromEnd).clamp(0, t.length);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: at));
  }
}
