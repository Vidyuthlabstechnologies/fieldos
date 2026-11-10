/// Reminders that build the daily habit: an evening nudge to send the
/// day's site report (skipped once every running site has one), and a
/// morning list of the tasks due that day. Planned a week ahead each time
/// the app opens or a report is saved, as phone notifications, so they
/// arrive even when FieldOS is closed and without any server.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/daily/day_close.dart';
import 'package:fieldos_mobile/features/daily/day_close_data.dart';
import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

const reminderSettingsKey = 'reminders';

/// Notification ids used for reminders, so they can all be replaced.
const reminderIdBase = 1000;
const reminderIdCount = 200;

class ReminderSettings {
  const ReminderSettings({
    this.reportOn = true,
    this.reportMinutes = 18 * 60 + 30,
    this.tasksOn = true,
    this.briefOn = true,
  });

  final bool reportOn;

  /// The owner's evening site brief, at [briefMinutes]. Only for people
  /// who can see the money (owners and managers).
  final bool briefOn;
  static const briefMinutes = 19 * 60 + 30;

  /// Minutes after midnight for the report reminder (default 6:30 pm).
  final int reportMinutes;
  final bool tasksOn;

  ReminderSettings copyWith({bool? reportOn, int? reportMinutes, bool? tasksOn, bool? briefOn}) => ReminderSettings(
    reportOn: reportOn ?? this.reportOn,
    reportMinutes: reportMinutes ?? this.reportMinutes,
    tasksOn: tasksOn ?? this.tasksOn,
    briefOn: briefOn ?? this.briefOn,
  );

  String toJson() => jsonEncode({'report': reportOn, 'at': reportMinutes, 'tasks': tasksOn, 'brief': briefOn});

  static ReminderSettings fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const ReminderSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final at = (j['at'] as num?)?.toInt() ?? 18 * 60 + 30;
      return ReminderSettings(
        reportOn: j['report'] as bool? ?? true,
        reportMinutes: at.clamp(0, 24 * 60 - 1),
        tasksOn: j['tasks'] as bool? ?? true,
        briefOn: j['brief'] as bool? ?? true,
      );
    } catch (_) {
      return const ReminderSettings();
    }
  }
}

class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.title, required this.body, this.payload});
  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// What a tap opens (`today:<projectId>` for a site's Today checklist).
  final String? payload;
}

/// One site's daily close reminder for this person, at the site's cutoff.
class SiteCloseReminder {
  const SiteCloseReminder({
    required this.projectId,
    required this.siteName,
    required this.cutoffMinutes,
    required this.days,
    this.sentToday = false,
    this.missingToday = const [],
  });
  final String projectId;
  final String siteName;
  final int cutoffMinutes;

  /// Days from today (0 = today) this person is the one expected to send
  /// it (the supervisor, or the backup while covering).
  final Set<int> days;
  final bool sentToday;

  /// What today's checklist still misses, in the app's language.
  final List<String> missingToday;
}

/// Sites get one reminder each (ids reminderIdBase + 150 + site * 7 + day).
const maxCloseReminderSites = 7;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// The reminders for the next [days] days from [now], soonest first.
///
/// [runningSites] is how many projects are active; with none, there is no
/// report to send. [reportedToday] is true once each of them has today's
/// report. [openTasks] are the company's unfinished tasks.
List<PlannedReminder> planReminders({
  required DateTime now,
  required ReminderSettings settings,
  required int runningSites,
  required bool reportedToday,
  required List<Task> openTasks,
  bool isOwner = false,
  int days = 7,
  List<SiteCloseReminder> closeReminders = const [],
  bool dailyCloseInUse = false,
}) {
  final out = <PlannedReminder>[];
  final today = _day(now);
  for (var i = 0; i < days; i++) {
    final day = today.add(Duration(days: i));
    // One reminder per site, to the one person expected to send it, at the
    // site's own cutoff, listing what is missing. Once a company uses the
    // daily close, the general evening nudge stops: escalation goes to the
    // manager's exceptions, not more reminders to everyone.
    if (settings.reportOn) {
      for (var s = 0; s < closeReminders.length && s < maxCloseReminderSites; s++) {
        final c = closeReminders[s];
        if (!c.days.contains(i) || (i == 0 && c.sentToday)) continue;
        final at = day.add(Duration(minutes: c.cutoffMinutes));
        if (!at.isAfter(now)) continue;
        out.add(PlannedReminder(
          id: reminderIdBase + 150 + s * 7 + i,
          at: at,
          title: trf("Today's report · {site}", {'site': c.siteName}),
          body: i == 0 && c.missingToday.isNotEmpty
              ? trf('Still to do: {items}. Tap to finish it.', {'items': c.missingToday.join(', ')})
              : tr('Tap to see what is still to do. Quiet day? Mark it in seconds.'),
          payload: 'today:${c.projectId}',
        ));
      }
    }
    if (settings.reportOn && runningSites > 0 && !dailyCloseInUse && !(i == 0 && reportedToday)) {
      final at = day.add(Duration(minutes: settings.reportMinutes));
      if (at.isAfter(now)) {
        out.add(
          PlannedReminder(
            id: reminderIdBase + i,
            at: at,
            title: tr("Today's site report"),
            body: tr('Speak or type what happened on site today. It takes a minute.'),
          ),
        );
      }
    }
    if (settings.briefOn && isOwner && runningSites > 0) {
      final at = day.add(const Duration(minutes: ReminderSettings.briefMinutes));
      if (at.isAfter(now)) {
        out.add(
          PlannedReminder(
            id: reminderIdBase + 50 + i,
            at: at,
            title: tr('Your site brief is ready'),
            body: tr('See which sites need you today: people, money, work and problems in one screen.'),
          ),
        );
      }
    }
    if (settings.tasksOn) {
      final due = openTasks.where((t) => t.dueDate != null && _day(t.dueDate!) == day).toList()
        ..sort((a, b) => a.title.compareTo(b.title));
      final at = day.add(const Duration(hours: 8));
      if (due.isNotEmpty && at.isAfter(now)) {
        final names = due.take(3).map((t) => t.title).join(', ');
        out.add(
          PlannedReminder(
            id: reminderIdBase + 100 + i,
            at: at,
            title: due.length == 1 ? tr('1 task due today') : trf('{n} tasks due today', {'n': due.length}),
            body: due.length > 3 ? trf('{names} and {n} more', {'names': names, 'n': due.length - 3}) : names,
          ),
        );
      }
    }
  }
  return out..sort((a, b) => a.at.compareTo(b.at));
}

class ReminderScheduler {
  ReminderScheduler(this._ref);
  final Ref _ref;

  AppDatabase get _db => _ref.read(appDatabaseProvider);

  Future<ReminderSettings> settings() async =>
      ReminderSettings.fromJson(await _db.settingsDao.get(reminderSettingsKey));

  Future<void> save(ReminderSettings s) async {
    await _db.settingsDao.set(reminderSettingsKey, s.toJson());
    await refresh();
  }

  /// Works out the week's reminders for the active company and hands them
  /// to the phone, replacing the old ones. Never throws: reminders must
  /// not get in the way of the app.
  Future<void> refresh({DateTime? now}) async {
    try {
      final company = _ref.read(sessionProvider).activeCompany;
      final notifications = _ref.read(notificationServiceProvider);
      if (company == null) {
        await notifications.replaceScheduled(const []);
        return;
      }
      final s = await settings();
      final t = now ?? DateTime.now();
      final today = _day(t);
      final running = (await _db.projectDao.forCompany(company.id)).where((p) => p.status == 'active').toList();
      var reported = running.isNotEmpty;
      for (final p in running) {
        final dprs = await _db.dprDao.forProject(p.id);
        if (!dprs.any((d) => _day(d.entryDate) == today)) {
          reported = false;
          break;
        }
      }
      final me = _ref.read(sessionProvider).user?.id;
      final role = _ref.read(sessionProvider).role;
      final canRecord = role != null && Roles.canWrite(role) && role != Roles.subcontractor;
      final close = <SiteCloseReminder>[];
      var closeInUse = false;
      for (final p in running) {
        final r = await SiteRecords.load(_db, p);
        if (r.trackingStart != null) closeInUse = true;
        if (me == null) continue;
        final days = {
          for (var i = 0; i < 7; i++)
            if (r.setup.remindsUser(me, today.add(Duration(days: i)), canRecord: canRecord)) i
        };
        if (days.isEmpty) continue;
        final d = r.day(today);
        close.add(SiteCloseReminder(
          projectId: p.id,
          siteName: p.name,
          cutoffMinutes: r.setup.cutoffMinutes,
          days: days,
          sentToday: d.isSubmitted,
          missingToday: missingItems(d.snapshot, const NothingMarks()).map(checkLabel).toList(),
        ));
      }
      final plan = planReminders(
        now: t,
        settings: s,
        runningSites: running.length,
        reportedToday: reported,
        closeReminders: close,
        dailyCloseInUse: closeInUse,
        openTasks: s.tasksOn ? await _db.taskDao.openForCompany(company.id) : const [],
        isOwner: canSeeMoneyIn(_ref.read(sessionProvider).role),
      );
      if (plan.isNotEmpty) await notifications.init();
      await notifications.replaceScheduled(plan);
    } catch (_) {
      // No plugin (tests, desktop) or no permission: nothing to do.
    }
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => ReminderScheduler(ref));
