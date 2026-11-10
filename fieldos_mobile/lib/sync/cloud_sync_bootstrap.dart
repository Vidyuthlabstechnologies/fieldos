/// Starts cloud sync on its own: on launch (resuming the saved Supabase
/// session) and whenever the app comes back to the foreground.
///
/// Before this, background sync only ran after someone typed the password
/// into Settings -- and the session lived only in memory, so every app
/// restart silently turned sync off again until they did it once more.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/notification_service.dart';
import 'package:fieldos_mobile/features/tasks/team_roster.dart';
import 'cloud_sync_providers.dart';
import 'cloud_sync_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

final cloudSyncBootstrapProvider = Provider<CloudSyncBootstrap>((ref) => CloudSyncBootstrap(ref));

class CloudSyncBootstrap {
  CloudSyncBootstrap(this._ref);
  final Ref _ref;

  /// At most this many alerts per sync run; a bigger batch collapses into
  /// one summary so a long-offline phone doesn't buzz 40 times.
  static const maxAlertsPerRun = 3;
  final _queued = <({String title, String body})>[];
  Timer? _flush;

  /// Safe to call repeatedly (launch, company switch, resume, after linking).
  Future<void> ensureRunning() async {
    if (!_ref.read(cloudSyncAvailableProvider)) return;
    final session = _ref.read(sessionProvider);
    final user = session.user;
    final company = session.activeCompany;
    if (user == null || company == null) return;

    final engine = _ref.read(cloudSyncEngineProvider);
    engine.localUserId = user.id;
    engine.onRemoteRowCreated ??= _onRemoteRow;

    final service = _ref.read(cloudSyncServiceProvider);
    if (!service.isSignedIn) await service.restoreSession();
    if (!service.isSignedIn) return;
    if (!await _ref.read(cloudLinksProvider).isLinked(company.id)) return;

    // Photos and bills from before attachments synced (1.7.x) go up once.
    await _ref.read(appDatabaseProvider).queueFilesFromBeforeSync();
    unawaited(_ref.read(notificationServiceProvider).init().catchError((_) {}));
    final trigger = _ref.read(periodicSyncTriggerProvider);
    if (!trigger.isRunning) trigger.start();
    unawaited(trigger.tick());
    unawaited(_refreshRoster(service, company.id));
  }

  /// Keeps the team list on the phone fresh, for assigning tasks offline.
  Future<void> _refreshRoster(CloudSyncService service, String companyId) async {
    try {
      final roster = await service.roster(companyId);
      await saveRoster(_ref.read(appDatabaseProvider), companyId, roster, myUserId: service.userId);
    } catch (_) {
      // Offline or not allowed: the last saved list stays.
    }
  }

  /// App back in the foreground: pick up what colleagues did meanwhile.
  Future<void> onResume() async {
    final trigger = _ref.read(periodicSyncTriggerProvider);
    if (trigger.isRunning) {
      await trigger.tick();
    } else {
      await ensureRunning();
    }
  }

  void stop() => _ref.read(periodicSyncTriggerProvider).stop();

  void _onRemoteRow(String table, Map<String, dynamic> row) {
    // The first full pull on a newly-linked phone brings down the whole
    // company's history; none of that is news. Alerts start once this
    // device has completed one sync (last_sync_at is set after it).
    _ref.read(appDatabaseProvider).settingsDao.get('last_sync_at').then((lastSync) {
      if (lastSync == null || lastSync.isEmpty) return;
      final alert = describeRemoteRow(table, row, myUserId: _ref.read(cloudSyncClientProvider).auth.currentUser?.id);
      if (alert == null) return;
      _queued.add(alert);
      _flush ??= Timer(const Duration(seconds: 2), _flushAlerts);
    });
  }

  Future<void> _flushAlerts() async {
    _flush = null;
    final batch = List.of(_queued);
    _queued.clear();
    final notifications = _ref.read(notificationServiceProvider);
    if (batch.length > maxAlertsPerRun) {
      await notifications.show('FieldOS', trf('{n} new updates from your team', {'n': batch.length}));
      return;
    }
    for (final a in batch) {
      await notifications.show(a.title, a.body);
    }
  }
}
