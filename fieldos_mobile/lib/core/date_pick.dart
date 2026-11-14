/// The app's date picker: showDatePicker asserts (a red screen in debug, a
/// dead tap in release) when its initial date falls outside first..last,
/// and a saved date can: a bill from three years ago, a follow-up set last
/// year, a hire whose return date has passed.
library;

import 'package:flutter/material.dart';

/// The initial date and range a picker opens with. By default the range is
/// widened to take in [initial]; with [keepRange] (the range is a rule, such
/// as "not before today") [initial] is moved into it instead. Compared by
/// day, as the picker does.
({DateTime initial, DateTime first, DateTime last}) pickerBounds(DateTime initial, DateTime first, DateTime last,
    {bool keepRange = false}) {
  final d = DateUtils.dateOnly(initial);
  final f = DateUtils.dateOnly(first);
  final l = DateUtils.dateOnly(last).isBefore(f) ? f : DateUtils.dateOnly(last);
  if (keepRange) return (initial: d.isBefore(f) ? f : (d.isAfter(l) ? l : d), first: f, last: l);
  return (initial: d, first: d.isBefore(f) ? d : f, last: d.isAfter(l) ? d : l);
}

/// showDatePicker that never asserts on its initial date (see [pickerBounds]).
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initial,
  required DateTime first,
  required DateTime last,
  bool keepRange = false,
  String? helpText,
}) {
  final b = pickerBounds(initial, first, last, keepRange: keepRange);
  return showDatePicker(
    context: context,
    initialDate: b.initial,
    firstDate: b.first,
    lastDate: b.last,
    helpText: helpText,
  );
}
