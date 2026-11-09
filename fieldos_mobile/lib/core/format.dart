/// Dates and times the way people on site say them: "6 Nov 2026",
/// "Today, 7:12 pm", "Yesterday". No locale package needed, and nothing
/// here touches the network.
library;

import 'package:fieldos_mobile/l10n/language.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "6 Nov 2026" (the year is left out for dates in the current year when
/// [short] is true: "6 Nov").
String fmtDate(DateTime d, {bool short = false, DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final base = '${l.day} ${_months[l.month - 1]}';
  return short && l.year == n.year ? base : '$base ${l.year}';
}

/// "7:12 pm".
String fmtTime(DateTime d) {
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  final m = l.minute.toString().padLeft(2, '0');
  return '$h:$m ${l.hour < 12 ? 'am' : 'pm'}';
}

/// "Today, 7:12 pm", "Yesterday, 9:05 am" or "3 Nov, 6:40 pm".
String fmtDateTime(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final day = DateTime(l.year, l.month, l.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  final label = switch (diff) {
    0 => tr('Today'),
    1 => tr('Yesterday'),
    _ => fmtDate(l, short: true, now: n),
  };
  return '$label, ${fmtTime(l)}';
}

/// "Today", "Yesterday" or a date, for list headers and DPR rows.
String fmtDay(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final diff = DateTime(n.year, n.month, n.day).difference(DateTime(l.year, l.month, l.day)).inDays;
  return switch (diff) {
    0 => tr('Today'),
    1 => tr('Yesterday'),
    _ => fmtDate(l, short: true, now: n),
  };
}

/// Whether [a] and [b] fall on the same local calendar day.
bool isSameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// "9 h 05 min", "45 min".
String fmtHours(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  return h == 0 ? '${d.inMinutes} min' : '$h h $m min';
}

/// "2 min 05 s" for recording timers and durations.
String fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return m == 0 ? '${d.inSeconds} s' : '$m min $s s';
}

/// "0:42" or "12:05", for a running timer.
String fmtClock(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// A quantity without a trailing ".0": "50", "12.5", "0.25".
String fmtQty(num q) {
  if (q == q.roundToDouble()) return q.round().toString();
  final t = q.toStringAsFixed(3);
  return t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

/// Rupees with Indian grouping: "₹12,34,567". Whole rupees unless [paise]
/// is true and the amount has some ("₹45.50").
String rupees(num v, {bool paise = false}) {
  final neg = v < 0;
  final abs = v.abs();
  final cents = (abs * 100).round();
  final showPaise = paise && cents % 100 != 0;
  final whole = (showPaise ? cents ~/ 100 : abs.round()).toString();
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  final tail = showPaise ? '.${(cents % 100).toString().padLeft(2, '0')}' : '';
  return '${neg ? '-' : ''}₹$grouped$tail';
}
