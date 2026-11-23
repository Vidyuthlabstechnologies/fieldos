/// The one-time notice before someone's first own check-in: what the app
/// reads (one GPS position and a front-camera photo per check-in or out),
/// why, who sees it, and that it is never used for face recognition or
/// background tracking. Nothing is read until they agree. Privacy laws in
/// every market FieldOS sells in ask for this kind of notice for location
/// and photos at work (DPDP in India, PDPA in Malaysia, state laws in the
/// US, UK GDPR, the UAE PDPL), and the policies say the app asks first.
///
/// Saying no never blocks pay: a supervisor can still mark the person's
/// attendance from the site's labour screen.
library;

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/legal/consent_record.dart';

String attendanceConsentKey(String userId) => 'attendance_consent:$userId';

/// Whether [userId] agreed to the check-in photo and location. The stored
/// value is when they agreed, or '0' once withdrawn.
Future<bool> attendanceConsentGiven(AppDatabase db, String userId) async {
  final v = await db.settingsDao.get(attendanceConsentKey(userId));
  return v != null && v.isNotEmpty && v != '0';
}

/// Also queues the choice as proof of consent for the server (see
/// consent_record.dart).
Future<void> setAttendanceConsent(AppDatabase db, String userId, bool given) async {
  final at = DateTime.now().toUtc();
  await db.settingsDao.set(attendanceConsentKey(userId), given ? at.toIso8601String() : '0');
  await queueConsentRecord(db, userId, ConsentPurpose.attendancePhotoLocation, given, at: at);
}
