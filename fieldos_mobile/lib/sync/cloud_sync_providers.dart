/// Riverpod wiring for the cloud sync stack (SupabaseClient -> SyncEngine ->
/// CloudSyncService), separate from lib/providers.dart because this is the
/// one part of the app with a real network dependency -- keeping it in its
/// own file makes that boundary visible.
library;

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/providers.dart';
import 'cloud_sync_service.dart';
import 'sync_config.dart';
import 'sync_engine.dart';

/// Picks the right local-stack URL for where the app is actually running --
/// an Android emulator's 127.0.0.1 is itself, not the host machine (see
/// sync_config.dart). This app targets Android only, so Platform.isAndroid
/// is a safe check here (no web build to guard against). A real device on
/// the same Wi-Fi as the dev machine needs the host's LAN IP instead, which
/// isn't knowable here -- that's a manual override for whoever's testing on
/// physical hardware, same as any other local-dev-server setup.
SyncConfig _resolveConfig() {
  if (SyncConfig.production.url.isNotEmpty) return SyncConfig.production;
  return Platform.isAndroid ? SyncConfig.localAndroidEmulator : SyncConfig.local;
}

final cloudSyncClientProvider = Provider<SupabaseClient>((ref) {
  final client = _resolveConfig().createClient();
  ref.onDispose(client.dispose);
  return client;
});

final cloudSyncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(db: ref.watch(appDatabaseProvider), client: ref.watch(cloudSyncClientProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService(client: ref.watch(cloudSyncClientProvider), engine: ref.watch(cloudSyncEngineProvider));
});
