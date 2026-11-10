/// Rules for staff marking their own attendance with a selfie and GPS: is
/// the fix inside the site's geofence, which site is nearest, and how many
/// days of a month count towards their salary.
///
/// Inside the geofence a check-in counts at once ("ok"). Outside it, or
/// with no GPS fix or no site location, it waits for an owner or project
/// manager to approve or turn down. The server works the geofence out
/// again from the coordinates, so a changed app cannot mark itself inside.
library;

import 'package:fieldos_mobile/core/geo.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/payroll/payroll_rules.dart';

/// ok | pending | approved | rejected
const staffAttendanceStatuses = ['ok', 'pending', 'approved', 'rejected'];

const staffAttendanceStatusLabels = {
  'ok': 'At site',
  'pending': 'Waiting for OK',
  'approved': 'Approved',
  'rejected': 'Not approved',
};

/// A day that counts towards salary.
bool countsAsPresent(String status) => status == 'ok' || status == 'approved';

/// yyyy-MM-dd of the local day.
String dayKey(DateTime t) {
  final l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

class GeoCheck {
  const GeoCheck(this.distanceM, this.within);

  /// Metres from the site's centre, or null without a fix or a site location.
  final double? distanceM;

  /// Inside the geofence; null when it cannot be told.
  final bool? within;
}

GeoCheck geoCheck(double? lat, double? lng, ProjectGeofence? fence) {
  if (lat == null || lng == null || fence == null) return const GeoCheck(null, null);
  final d = haversineMeters(lat, lng, fence.centerLat, fence.centerLng);
  return GeoCheck(d, d <= fence.radiusMeters);
}

/// The site whose centre is nearest to the fix, with its distance; null
/// when no site has a location.
(String, double)? nearestSite(double lat, double lng, Map<String, ProjectGeofence> fences) {
  (String, double)? best;
  for (final e in fences.entries) {
    final d = haversineMeters(lat, lng, e.value.centerLat, e.value.centerLng);
    if (best == null || d < best.$2) best = (e.key, d);
  }
  return best;
}

/// "120 m" or "2.4 km".
String distanceText(double m) => m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

/// One person's month from their check-ins.
class StaffMonth {
  const StaffMonth({
    required this.month,
    required this.present,
    required this.waiting,
    required this.notApproved,
    required this.weeklyOffs,
    required this.daysInMonth,
  });

  final String month;

  /// Days with a check-in at a site or an approved one.
  final int present;

  /// Days with only check-ins still waiting for an OK.
  final int waiting;

  /// Days whose only check-ins were turned down.
  final int notApproved;

  /// Sundays they did not work, counted as paid weekly offs (up to today,
  /// and not before they joined).
  final int weeklyOffs;
  final int daysInMonth;

  /// Days to pay from attendance: present plus paid Sundays, at most the
  /// month.
  double get paidDays => (present + weeklyOffs).clamp(0, daysInMonth).toDouble();
  bool get hasAny => present + waiting + notApproved > 0;
}

/// [rows] are one person's check-ins (any months). Only [month] is counted.
StaffMonth staffMonth(List<StaffAttendanceData> rows, String month, {required DateTime now, DateTime? joinedOn}) {
  final byDay = <String, List<String>>{};
  for (final r in rows) {
    if (!r.day.startsWith(month)) continue;
    (byDay[r.day] ??= []).add(r.status);
  }
  var present = 0, waiting = 0, rejected = 0;
  for (final statuses in byDay.values) {
    if (statuses.any(countsAsPresent)) {
      present++;
    } else if (statuses.contains('pending')) {
      waiting++;
    } else {
      rejected++;
    }
  }
  final start = monthStart(month);
  final days = daysInMonth(month);
  final today = DateTime(now.year, now.month, now.day);
  final joined = joinedOn == null ? null : DateTime(joinedOn.year, joinedOn.month, joinedOn.day);
  var offs = 0;
  for (var d = 1; d <= days; d++) {
    final date = DateTime(start.year, start.month, d);
    if (date.weekday != DateTime.sunday || date.isAfter(today)) continue;
    if (joined != null && date.isBefore(joined)) continue;
    final statuses = byDay[dayKey(date)];
    if (statuses != null && statuses.any(countsAsPresent)) continue;
    offs++;
  }
  return StaffMonth(
      month: month, present: present, waiting: waiting, notApproved: rejected, weeklyOffs: offs, daysInMonth: days);
}

/// Hours between check-in and check-out, or null while still in.
double? hoursOnSite(StaffAttendanceData r) {
  final out = r.checkOut;
  if (out == null) return null;
  return out.difference(r.checkIn).inMinutes / 60;
}
