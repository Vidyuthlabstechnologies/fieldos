/// What the site's own records say about one day, so the daily report can
/// fill itself in: who punched in, and what material arrived.
library;

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/data/app_database.dart';

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Distinct workers who punched in on [day]. A worker punched in twice
/// (lunch break, a second shift) counts once.
int workersOnDay(Iterable<LabourAttendanceData> attendance, DateTime day) {
  final seen = <String>{};
  for (final a in attendance) {
    if (_sameDay(a.punchIn, day)) seen.add(a.workerId ?? a.workerName.trim().toLowerCase());
  }
  return seen.length;
}

/// Material received on [day], one entry per material and unit, in the
/// order it first arrived: "Cement 40 bags", "Sand 2 brass".
List<String> materialsOnDay(Iterable<MaterialReceipt> receipts, DateTime day) {
  final totals = <String, ({String name, String unit, double qty})>{};
  final sorted = receipts.where((r) => _sameDay(r.receivedOn, day)).toList()
    ..sort((a, b) => a.receivedOn.compareTo(b.receivedOn));
  for (final r in sorted) {
    final name = r.materialName.trim();
    final unit = (r.unit ?? '').trim();
    final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
    final prev = totals[key];
    totals[key] = (name: prev?.name ?? name, unit: prev?.unit ?? unit, qty: (prev?.qty ?? 0) + r.quantity);
  }
  return [
    for (final t in totals.values) [t.name, fmtQty(t.qty), if (t.unit.isNotEmpty) t.unit].join(' '),
  ];
}

/// The line added to a report: "Material received: Cement 40 bags, Sand 2 brass."
String materialsLine(List<String> items) => items.isEmpty ? '' : 'Material received: ${items.join(', ')}.';

/// The most recent report before [day], to start today's from.
DprEntry? lastReportBefore(Iterable<DprEntry> reports, DateTime day) {
  final start = DateTime(day.year, day.month, day.day);
  DprEntry? best;
  for (final r in reports) {
    if (!r.entryDate.isBefore(start)) continue;
    if (best == null || r.entryDate.isAfter(best.entryDate)) best = r;
  }
  return best;
}
