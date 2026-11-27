/// Riverpod wiring for the cloud sync stack (SupabaseClient -> SyncEngine ->
/// CloudSyncService), separate from lib/providers.dart because this is the
/// one part of the app with a real network dependency -- keeping it in its
/// own file makes that boundary visible.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/data/secret_store.dart';
import 'package:fieldos_mobile/features/legal/consent_record.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/ai_backend.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/services/message_report_service.dart';
import 'app_version_gate.dart';
import 'cloud_sync_service.dart';
import 'periodic_sync_trigger.dart';
import 'sync_config.dart';
import 'sync_engine.dart';

/// Picks the right local-stack URL for where the app is actually running --
/// an Android emulator's 127.0.0.1 is itself, not the host machine (see
/// sync_config.dart). The app ships on Android and iOS (no web build), so
/// Platform.isAndroid is a safe check here; the iOS simulator shares the
/// host's 127.0.0.1. A real device on
/// the same Wi-Fi as the dev machine needs the host's LAN IP instead, which
/// isn't knowable here -- that's a manual override for whoever's testing on
/// physical hardware, same as any other local-dev-server setup.
SyncConfig _resolveConfig() {
  if (SyncConfig.production.isConfigured) return SyncConfig.production;
  return Platform.isAndroid ? SyncConfig.localAndroidEmulator : SyncConfig.local;
}

/// Whether this build can offer cloud sync to a real user: a release build
/// needs the production project baked in (see SyncConfig.production); a
/// debug/profile build may use the local dev stack.
final cloudSyncAvailableProvider = Provider<bool>((ref) {
  const isRelease = bool.fromEnvironment('dart.vm.product');
  return SyncConfig.production.isConfigured || !isRelease;
});

final cloudSyncClientProvider = Provider<SupabaseClient>((ref) {
  final client = _resolveConfig().createClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Where integrations call the open API (supabase/functions/public-api).
final openApiBaseUrlProvider = Provider<String>((ref) => '${_resolveConfig().url}/functions/v1/public-api/v1');

/// FieldOS's server-side AI (the assistant and the Sarvam fallback), signed
/// in with the same FieldOS account as Team & sync.
final aiBackendProvider = Provider<AiBackend>((ref) => SupabaseAiBackend(
      client: ref.watch(cloudSyncAvailableProvider) ? ref.watch(cloudSyncClientProvider) : null,
      subscriberId: () => ref.read(billingServiceProvider).customerId(
          linkTo: ref.read(cloudSyncAvailableProvider) ? ref.read(cloudSyncClientProvider).auth.currentUser?.id : null),
    ));

/// The server's minimum app build (issue #146), shared by sync and the
/// home banner.
final appVersionGateProvider = Provider<AppVersionGate>((ref) {
  final gate = AppVersionGate(db: ref.watch(appDatabaseProvider), client: () => ref.read(cloudSyncClientProvider));
  ref.onDispose(gate.dispose);
  return gate;
});

/// The "please update" notice for Home, from the answer sync last got (no
/// network of its own); null when this build is fine.
final appUpdateRequiredProvider = FutureProvider<AppUpdateRequired?>((ref) {
  final gate = ref.watch(appVersionGateProvider);
  final sub = gate.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(sub.cancel);
  return gate.cached();
});

final cloudSyncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = ref.watch(cloudSyncClientProvider);
  final engine = SyncEngine(db: db, client: client, versionGate: ref.watch(appVersionGateProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  final service = CloudSyncService(
    client: ref.watch(cloudSyncClientProvider),
    engine: ref.watch(cloudSyncEngineProvider),
    sessionStore: SettingsSessionStore(ref.watch(appDatabaseProvider), secrets: ref.watch(secretStoreProvider)),
    freshClient: _resolveConfig().createClient,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Company plans (sold by invoice, switched on by the FieldOS team) come
/// from the same cloud account as Team & sync.
final companyPlanServiceProvider = Provider<CompanyPlanService>((ref) {
  final available = ref.watch(cloudSyncAvailableProvider);
  return CompanyPlanService(
    db: ref.watch(appDatabaseProvider),
    cloud: available ? ref.watch(cloudSyncServiceProvider) : null,
    available: available,
  );
});

/// The phone's secure store (Keystore or Keychain). Only Android and iOS have
/// one here; a desktop development build, and the tests that run on the host,
/// keep the session in the database as before.
final secretStoreProvider = Provider<SecretStore?>(
  (ref) => (Platform.isAndroid || Platform.isIOS) ? const PlatformSecretStore() : null,
);

/// Keeps the Supabase session so a restart resumes cloud sync without asking
/// for the password again.
///
/// The session (its refresh token above all) lives in the phone's secure
/// store, Keystore or Keychain, not in the app's database. The database holds
/// only [secureMarker], which does three jobs: it says "the session is in the
/// secure store", it is non-empty so "a session is saved" checks keep working,
/// and it is how a fresh install ignores a Keychain item an earlier install
/// left behind (an iPhone keeps those across uninstalls).
///
/// If the secure store is not available or fails, the session is kept in the
/// database as before: nobody is signed out because of a Keystore problem. A
/// session an older version saved in the database moves to the secure store the
/// first time it is read.
class SettingsSessionStore implements SessionStore {
  SettingsSessionStore(this.db, {this.secrets});
  final AppDatabase db;
  final SecretStore? secrets;
  static const key = cloudSessionSettingsKey;
  static const secureMarker = 'secure:v1';

  @override
  Future<String?> read() async {
    final v = await db.settingsDao.get(key);
    if (v == null || v.isEmpty) return null;
    if (v == secureMarker) {
      try {
        final s = await secrets?.read(key);
        return (s == null || s.isEmpty) ? null : s;
      } catch (_) {
        return null; // sign in again; nothing else is lost
      }
    }
    // Saved by an older version, in the database: move it.
    if (secrets != null) {
      try {
        await secrets!.write(key, v);
        await db.settingsDao.set(key, secureMarker);
      } catch (_) {
        // Stays where it is.
      }
    }
    return v;
  }

  @override
  Future<void> write(String? sessionJson) async {
    if (sessionJson == null || sessionJson.isEmpty) {
      try {
        await secrets?.write(key, null);
      } catch (_) {
        // The database entry is what says a session exists.
      }
      await db.settingsDao.set(key, '');
      return;
    }
    if (secrets != null) {
      try {
        await secrets!.write(key, sessionJson);
        await db.settingsDao.set(key, secureMarker);
        return;
      } catch (_) {
        // Fall through: keep it in the database rather than lose the session.
      }
    }
    await db.settingsDao.set(key, sessionJson);
  }
}

/// Which local companies are registered/joined on the server, so the app
/// knows on launch whether to start background sync for the active one.
class CloudLinks {
  CloudLinks(this.db);
  final AppDatabase db;
  static const key = 'cloud_linked_companies';

  Future<Set<String>> all() async {
    final v = await db.settingsDao.get(key);
    if (v == null || v.isEmpty) return {};
    return (jsonDecode(v) as List).cast<String>().toSet();
  }

  Future<bool> isLinked(String companyId) async => (await all()).contains(companyId);

  Future<void> link(String companyId) async =>
      db.settingsDao.set(key, jsonEncode({...await all(), companyId}.toList()));

  Future<void> clear() => db.settingsDao.set(key, '');
}

final cloudLinksProvider = Provider<CloudLinks>((ref) => CloudLinks(ref.watch(appDatabaseProvider)));

/// Not started automatically -- a provider merely builds the object graph.
/// The Settings screen calls .start() right after a successful
/// enableSync(), which is the actual "turn background sync on" moment from
/// a user's point of view.
final periodicSyncTriggerProvider = Provider<PeriodicSyncTrigger>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final trigger = PeriodicSyncTrigger(
    service: ref.watch(cloudSyncServiceProvider),
    // Background ticks record success the same way "Sync now" does, so the
    // status line is honest about automatic syncs too.
    onSuccess: (result) async {
      if (result.failed == 0) await db.settingsDao.set('last_sync_at', DateTime.now().toIso8601String());
      // Online and signed in: a good moment to file any consent choices
      // made offline.
      await ref.read(consentRecorderProvider).flush(ref.read(sessionProvider).user?.id ?? '');
    },
  );
  ref.onDispose(trigger.stop);
  return trigger;
});

/// Proof of consent (consent_record.dart). With no cloud in this build the
/// choices stay on the phone.
final consentRecorderProvider = Provider<ConsentRecorder>((ref) {
  return ConsentRecorder(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(cloudSyncAvailableProvider) ? () => ref.read(cloudSyncClientProvider) : null,
  );
});

/// In-app bug reports go to the same cloud project. With no cloud in this
/// build (offline release) reports wait on the phone until one is.
final messageReportServiceProvider = Provider<MessageReportService>((ref) {
  return MessageReportService(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(cloudSyncAvailableProvider) ? ref.watch(cloudSyncClientProvider) : null,
  );
});

final bugReportServiceProvider = Provider<BugReportService>((ref) {
  return BugReportService(
    db: ref.watch(appDatabaseProvider),
    client: ref.watch(cloudSyncAvailableProvider) ? ref.watch(cloudSyncClientProvider) : null,
  );
});
