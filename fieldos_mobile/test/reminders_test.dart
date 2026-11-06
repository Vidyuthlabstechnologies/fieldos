/// Reminders: what gets planned for the week, the settings round trip,
/// the time zone handed to the phone, and the scheduler reading the
/// company's sites, reports and tasks.
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/notification_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

Task _task(String title, DateTime? due, {String status = 'todo'}) => Task(
  id: title,
  projectId: 'p',
  title: title,
  status: status,
  progress: 0,
  priority: 'normal',
  dueDate: due,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

class _FakeNotifications extends NotificationService {
  List<PlannedReminder>? last;
  var inits = 0;
  @override
  Future<void> init() async => inits++;
  @override
  Future<void> replaceScheduled(List<PlannedReminder> plan) async => last = plan;
}

void main() {
  final morning = DateTime(2026, 11, 10, 7); // Tuesday, 7 am

  group('plan', () {
    test('an evening report reminder each day for a week, starting today', () {
      final plan = planReminders(
        now: morning,
        settings: const ReminderSettings(),
        runningSites: 2,
        reportedToday: false,
        openTasks: const [],
      );
      expect(plan, hasLength(7));
      expect(plan.first.at, DateTime(2026, 11, 10, 18, 30));
      expect(plan.last.at, DateTime(2026, 11, 16, 18, 30));
      expect(plan.map((r) => r.id).toSet(), hasLength(7));
      expect(plan.first.title, "Today's site report");
    });

    test('no reminder tonight once every site has reported, or after the time has passed', () {
      final reported = planReminders(
        now: morning,
        settings: const ReminderSettings(),
        runningSites: 2,
        reportedToday: true,
        openTasks: const [],
      );
      expect(reported.first.at, DateTime(2026, 11, 11, 18, 30));
      final late = planReminders(
        now: DateTime(2026, 11, 10, 19),
        settings: const ReminderSettings(),
        runningSites: 1,
        reportedToday: false,
        openTasks: const [],
      );
      expect(late.first.at.day, 11);
    });

    test('no running site, or reminders off: no report reminder', () {
      expect(
        planReminders(
          now: morning,
          settings: const ReminderSettings(),
          runningSites: 0,
          reportedToday: false,
          openTasks: const [],
        ),
        isEmpty,
      );
      expect(
        planReminders(
          now: morning,
          settings: const ReminderSettings(reportOn: false),
          runningSites: 3,
          reportedToday: false,
          openTasks: const [],
        ),
        isEmpty,
      );
    });

    test('tasks due on a day are listed at 8 am that day', () {
      final tasks = [
        _task('Plinth beam', DateTime(2026, 11, 10)),
        _task('Columns', DateTime(2026, 11, 10, 17)),
        _task('Slab', DateTime(2026, 11, 12)),
        _task('Brick work', DateTime(2026, 11, 30)),
        _task('No date', null),
      ];
      final plan = planReminders(
        now: morning,
        settings: const ReminderSettings(reportOn: false),
        runningSites: 1,
        reportedToday: false,
        openTasks: tasks,
      );
      expect(plan.map((r) => (r.at, r.title, r.body)), [
        (DateTime(2026, 11, 10, 8), '2 tasks due today', 'Columns, Plinth beam'),
        (DateTime(2026, 11, 12, 8), '1 task due today', 'Slab'),
      ]);
    });

    test('more than three tasks on a day are summed up', () {
      final tasks = [
        for (final t in ['A', 'B', 'C', 'D', 'E']) _task(t, DateTime(2026, 11, 11)),
      ];
      final r = planReminders(
        now: morning,
        settings: const ReminderSettings(reportOn: false),
        runningSites: 1,
        reportedToday: false,
        openTasks: tasks,
      ).single;
      expect(r.body, 'A, B, C and 2 more');
    });

    test('reminders are written in the app language', () {
      setCurrentLanguage(AppLanguage.te);
      addTearDown(() => setCurrentLanguage(AppLanguage.en));
      final r = planReminders(
        now: morning,
        settings: const ReminderSettings(),
        runningSites: 1,
        reportedToday: false,
        openTasks: [_task('Slab', DateTime(2026, 11, 10)), _task('Columns', DateTime(2026, 11, 10))],
      );
      expect(r.first.title, 'ఈ రోజు 2 పనుల గడువు');
    });
  });

  test('settings round trip, with defaults for anything missing or broken', () {
    const s = ReminderSettings(reportOn: false, reportMinutes: 20 * 60, tasksOn: false);
    final back = ReminderSettings.fromJson(s.toJson());
    expect((back.reportOn, back.reportMinutes, back.tasksOn), (false, 1200, false));
    final d = ReminderSettings.fromJson('not json');
    expect((d.reportOn, d.reportMinutes, d.tasksOn), (true, 1110, true));
    expect(ReminderSettings.fromJson('{"at": 99999}').reportMinutes, 24 * 60 - 1);
  });

  test('the time zone handed to the phone has a real id', () {
    expect(deviceLocation(const Duration(hours: 5, minutes: 30)).name, 'Asia/Kolkata');
    expect(deviceLocation(const Duration(hours: 4)).name, 'GMT+04:00');
    expect(deviceLocation(const Duration(hours: -3, minutes: -30)).name, 'GMT-03:30');
    final loc = deviceLocation(const Duration(hours: 5, minutes: 30));
    expect(
      loc.timeZone(DateTime.utc(2026, 11, 10).millisecondsSinceEpoch).offset,
      const Duration(hours: 5, minutes: 30),
    );
  });

  group('scheduler', () {
    late AppDatabase db;
    late ProviderContainer container;
    late _FakeNotifications notifications;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      notifications = _FakeNotifications();
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          notificationServiceProvider.overrideWithValue(notifications),
        ],
      );
      final session = container.read(sessionProvider.notifier);
      await session.register(username: 'ravi', name: 'Ravi', password: '123456');
      final c = await session.createCompany('Sri Sai Constructions');
      await db.projectDao.create(
        ProjectsCompanion.insert(id: 'a', companyId: c.id, name: 'Tower A', status: const Value('active')),
      );
      await db.projectDao.create(
        ProjectsCompanion.insert(id: 'b', companyId: c.id, name: 'Tower B', status: const Value('active')),
      );
      await db.projectDao.create(
        ProjectsCompanion.insert(id: 'old', companyId: c.id, name: 'Old', status: const Value('completed')),
      );
      await db.taskDao.create(
        TasksCompanion.insert(id: 't', projectId: 'a', title: 'Slab', dueDate: Value(DateTime(2026, 11, 10))),
      );
      await db.taskDao.create(
        TasksCompanion.insert(
          id: 'done',
          projectId: 'a',
          title: 'Footing',
          status: const Value('done'),
          dueDate: Value(DateTime(2026, 11, 10)),
        ),
      );
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> report(String projectId, DateTime day) => db.dprDao.create(
      DprEntriesCompanion.insert(
        id: '$projectId-${day.day}',
        projectId: projectId,
        createdBy: 'u',
        entryDate: day,
        workSummary: 'Work',
      ),
    );

    test('plans tonight while a running site has no report today, and open tasks only', () async {
      await report('a', DateTime(2026, 11, 10));
      await container.read(reminderSchedulerProvider).refresh(now: morning);
      final plan = notifications.last!;
      expect(plan.first.at, DateTime(2026, 11, 10, 8));
      expect(plan.first.body, 'Slab');
      expect(plan.where((r) => r.at == DateTime(2026, 11, 10, 18, 30)), hasLength(1));
      expect(notifications.inits, 1);
    });

    test('drops tonight once every running site has reported', () async {
      await report('a', DateTime(2026, 11, 10, 9));
      await report('b', DateTime(2026, 11, 10, 12));
      await container.read(reminderSchedulerProvider).refresh(now: morning);
      expect(notifications.last!.where((r) => r.at == DateTime(2026, 11, 10, 18, 30)), isEmpty);
    });

    test('saving settings re-plans: everything off means nothing scheduled', () async {
      await container.read(reminderSchedulerProvider).save(const ReminderSettings(reportOn: false, tasksOn: false));
      expect(notifications.last, isEmpty);
      expect((await container.read(reminderSchedulerProvider).settings()).reportOn, isFalse);
    });
  });
}
