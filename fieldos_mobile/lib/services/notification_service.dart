/// On-device alerts for work that arrives from colleagues through sync: a
/// new issue on a project, an approval request, a team chat message.
///
/// Local notifications only (flutter_local_notifications), deliberately not
/// FCM push: push needs a Firebase project plus a server to send from,
/// which breaks the zero-running-cost rule. The trade-off is timing -- an
/// alert fires when this phone's sync runs (on launch, on resume, every 5
/// minutes while open), not the instant a colleague acts.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:fieldos_mobile/features/reminders/reminders.dart';

/// What to show for one newly-arrived row, or null to stay quiet. Kept a
/// pure function so the rules (skip my own rows, which tables alert) are
/// unit-testable without the Android plugin.
({String title, String body})? describeRemoteRow(
  String table,
  Map<String, dynamic> row, {
  required String? myUserId,
}) {
  String text(Object? v, [int max = 120]) {
    final s = (v as String? ?? '').trim();
    return s.length > max ? '${s.substring(0, max - 1)}…' : s;
  }

  switch (table) {
    case 'project_messages':
      if (row['sender_id'] == myUserId) return null;
      return (title: text(row['sender_name'], 60), body: text(row['body']));
    case 'issues':
      // Issues carry no author column; a row this phone wrote itself is
      // already in its local database, so it never reaches here as "new".
      final severity = text(row['severity'], 20);
      return (
        title: severity.isEmpty ? 'New issue' : 'New $severity-severity issue',
        body: text(row['description']),
      );
    case 'approvals':
      if (row['requested_by'] == myUserId) return null;
      if (row['status'] != null && row['status'] != 'pending') return null;
      final kind = text(row['entity_type'], 40).replaceAll('_', ' ');
      return (title: 'Approval requested', body: kind.isEmpty ? 'A request is waiting for a decision' : 'A $kind is waiting for a decision');
    default:
      return null;
  }
}

class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  int _nextId = 1;

  static const _channel = AndroidNotificationDetails(
    'site_updates',
    'Site updates',
    channelDescription: 'New issues, approval requests and team messages from your colleagues',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // iOS asks for alert/badge/sound permission on initialise.
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _ready = true;
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
    );
  }

  static const _reminderChannel = AndroidNotificationDetails(
    'reminders',
    'Reminders',
    channelDescription: "Today's site report and the tasks due today",
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Cancels the reminders planned before and schedules [plan] instead.
  /// Inexact on Android (within a few minutes), so no exact-alarm
  /// permission is needed.
  Future<void> replaceScheduled(List<PlannedReminder> plan) async {
    if (!_ready && plan.isEmpty) return;
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= reminderIdBase && p.id < reminderIdBase + reminderIdCount) await _plugin.cancel(id: p.id);
    }
    if (!_ready) return;
    final location = deviceLocation(DateTime.now().timeZoneOffset);
    for (final r in plan) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.at, location),
        notificationDetails: const NotificationDetails(android: _reminderChannel, iOS: DarwinNotificationDetails()),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// A time zone for the phone's current offset. Its name reaches Android's
/// ZoneId and iOS's TimeZone, so it must be a real id: India's own, or a
/// fixed GMT offset elsewhere.
tz.Location deviceLocation(Duration offset) {
  final minutes = offset.inMinutes;
  final String name;
  if (minutes == 330) {
    name = 'Asia/Kolkata';
  } else {
    final sign = minutes < 0 ? '-' : '+';
    final m = minutes.abs();
    name = 'GMT$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }
  return tz.Location(name, const [], const [], [tz.TimeZone(offset, isDst: false, abbreviation: name)]);
}
