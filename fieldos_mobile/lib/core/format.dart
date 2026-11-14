/// Dates and times the way people on site say them: "6 Nov 2026",
/// "Today, 7:12 pm", "Yesterday". No locale package needed, and nothing
/// here touches the network.
library;

import 'package:fieldos_mobile/core/market.dart';
import 'package:fieldos_mobile/l10n/language.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "6 Nov 2026" (the year is left out for dates in the current year when
/// [short] is true: "6 Nov"). In the US: "Nov 6, 2026" and "Nov 6".
String fmtDate(DateTime d, {bool short = false, DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final dropYear = short && l.year == n.year;
  if (market.dateOrder == DateOrder.mdy) {
    final base = '${_months[l.month - 1]} ${l.day}';
    return dropYear ? base : '$base, ${l.year}';
  }
  final base = '${l.day} ${_months[l.month - 1]}';
  return dropYear ? base : '$base ${l.year}';
}

/// "7:12 pm", or "19:12" where the 24-hour clock is the norm (UK).
String fmtTime(DateTime d) {
  final l = d.toLocal();
  final m = l.minute.toString().padLeft(2, '0');
  if (market.clock24h) return '${l.hour.toString().padLeft(2, '0')}:$m';
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '$h:$m ${l.hour < 12 ? 'am' : 'pm'}';
}

/// A date the way forms write it in this market: "06/11/2026", or
/// "11/06/2026" in the US.
String fmtDateNumeric(DateTime d) {
  final l = d.toLocal();
  final dd = l.day.toString().padLeft(2, '0'), mm = l.month.toString().padLeft(2, '0');
  return market.dateOrder == DateOrder.mdy ? '$mm/$dd/${l.year}' : '$dd/$mm/${l.year}';
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
  return h == 0 ? trf('{m} min', {'m': d.inMinutes}) : trf('{h} h {m} min', {'h': h, 'm': m});
}

/// "2 min 05 s" for recording timers and durations.
String fmtDuration(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return m == 0 ? trf('{s} s', {'s': d.inSeconds}) : trf('{m} min {s} s', {'m': m, 's': s});
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

/// [typed] with Arabic-Indic (٠-٩) and Persian/Urdu (۰-۹) digits as 0-9,
/// the Arabic decimal sign (٫) as "." and its thousands sign (٬) and the
/// bidi marks removed: an Arabic or Urdu keyboard types those, and
/// double.tryParse reads only 0-9.
String westernDigits(String typed) {
  if (!_easternDigit.hasMatch(typed)) return typed;
  final b = StringBuffer();
  for (final c in typed.runes) {
    if (c >= 0x0660 && c <= 0x0669) {
      b.writeCharCode(0x30 + c - 0x0660);
    } else if (c >= 0x06F0 && c <= 0x06F9) {
      b.writeCharCode(0x30 + c - 0x06F0);
    } else if (c == 0x066B) {
      b.write('.');
    } else if (c == 0x066C || c == 0x200E || c == 0x200F || (c >= 0x2066 && c <= 0x2069)) {
      // thousands sign and direction marks: dropped
    } else {
      b.writeCharCode(c);
    }
  }
  return b.toString();
}

final _easternDigit = RegExp('[\u0660-\u066C\u06F0-\u06F9\u200E\u200F\u2066-\u2069]');

/// A number as typed on a phone: "1,200", " 1250.5 ", "₹45,000". Null when
/// blank or unreadable, and for "NaN" or "Infinity", which double.tryParse
/// accepts but no amount or quantity can be.
double? parseTypedNumber(String typed) {
  final v = double.tryParse(
    westernDigits(typed).replaceAll(RegExp(r'[,₹\s]'), '').replaceAll(market.currencySymbol, '').replaceAll('د.إ', ''),
  );
  return v == null || !v.isFinite ? null : v;
}

/// An amount in this market's currency: "₹12,34,567" in India,
/// "$1,234,567" in the US, "RM1,234,567", "AED 1,234,567", "£1,234,567".
/// Whole units unless [cents] is true and the amount has some ("₹45.50").
String money(num v, {bool cents = false}) {
  final abs = v.abs();
  final hundredths = (abs * 100).round();
  final showCents = cents && hundredths % 100 != 0;
  final whole = (showCents ? hundredths ~/ 100 : abs.round()).toString();
  // "-₹0" for a balance that is only float dust below zero reads as owed.
  final neg = v < 0 && (showCents || whole != '0');
  final grouped = market.indianGrouping ? _groupIndian(whole) : _groupThousands(whole);
  final tail = showCents ? '.${(hundredths % 100).toString().padLeft(2, '0')}' : '';
  final sym = market.symbolSpace ? '${market.currencySymbol} ' : market.currencySymbol;
  return '${neg ? '-' : ''}$sym$grouped$tail';
}

/// [money] under its older name: every screen was written for India first.
/// It follows the build's market like [money] does.
String rupees(num v, {bool paise = false}) => money(v, cents: paise);

/// The currency symbol for a field's prefix or suffix: currencySymbol, r'$', 'RM'.
String get currencySymbol => market.currencySymbol;

String _groupThousands(String whole) {
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return b.toString();
}

/// 12,34,567: the last three digits, then pairs.
String _groupIndian(String whole) {
  if (whole.length <= 3) return whole;
  final last3 = whole.substring(whole.length - 3);
  var rest = whole.substring(0, whole.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}
