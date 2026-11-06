/// Dates and times the way people on site say them: "6 Nov 2026",
/// "Today, 7:12 pm", "Yesterday". No locale package needed, and nothing
/// here touches the network.
library;

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
    0 => 'Today',
    1 => 'Yesterday',
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
    0 => 'Today',
    1 => 'Yesterday',
    _ => fmtDate(l, short: true, now: n),
  };
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
