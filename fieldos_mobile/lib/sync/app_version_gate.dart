import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/l10n/language.dart';

/// This build is older than the server accepts (issue #146): cloud sync
/// stops until the app is updated. Nothing on the phone is touched.
class AppUpdateRequired implements Exception {
  const AppUpdateRequired({required this.minBuild, required this.build, this.note});
  final int minBuild;
  final int build;
  final String? note;

  String get message =>
      tr('Update FieldOS to keep syncing. Everything you enter is saved on this phone and goes up once you update.');

  @override
  String toString() => 'App update required for sync (build $build, server needs $minBuild)';
}

/// Reads the server's minimum build (`min_app_build()`,
/// 20261111140000_min_app_build.sql) at most once a [maxAge], remembers it
/// on the phone, and says whether this build may sync.
///
/// Never blocks on its own failure: offline, a server without the function
/// yet, or any error all fall back to the last answer seen, or to "no
/// minimum" when there is none.
class AppVersionGate {
  AppVersionGate({
    required this.db,
    required this.client,
    Future<int> Function()? currentBuild,
    String? platform,
    DateTime Function()? clock,
    this.maxAge = const Duration(hours: 24),
  })  : _currentBuild = currentBuild ?? _packageBuild,
        _platform = platform ?? (Platform.isIOS ? 'ios' : 'android'),
        _clock = clock ?? DateTime.now;

  final AppDatabase db;
  /// Asked for only when the server is checked, so reading the cached
  /// answer never starts a cloud client.
  final SupabaseClient Function() client;
  final Duration maxAge;
  final Future<int> Function() _currentBuild;
  final String _platform;
  final DateTime Function() _clock;

  static const cacheKey = 'min_app_build_v1';

  final _changes = StreamController<void>.broadcast();

  /// Fires after each fresh answer from the server, so Home can re-read
  /// [cached] without asking the network itself.
  Stream<void> get changes => _changes.stream;

  void dispose() => _changes.close();

  static Future<int> _packageBuild() async => int.tryParse((await PackageInfo.fromPlatform()).buildNumber) ?? 0;

  /// The cached rule only, no network: for the home banner.
  Future<AppUpdateRequired?> cached() async {
    final c = await _readCache();
    if (c == null) return null;
    return _judge(c.$1, c.$2);
  }

  /// Fresh when the cached answer is older than [maxAge] (or [force]).
  Future<AppUpdateRequired?> check({bool force = false}) async {
    final c = await _readCache();
    if (c != null && !force && _clock().difference(c.$3) < maxAge) return _judge(c.$1, c.$2);
    try {
      final res = await client().rpc('min_app_build').timeout(const Duration(seconds: 8));
      final m = res is Map ? Map<String, dynamic>.from(res) : const <String, dynamic>{};
      final min = (m[_platform] as num?)?.toInt() ?? 0;
      final note = m['message'] as String?;
      await db.settingsDao.set(
          cacheKey, jsonEncode({'min': min, 'note': note, 'at': _clock().toUtc().toIso8601String()}));
      if (!_changes.isClosed) _changes.add(null);
      return _judge(min, note);
    } catch (_) {
      // Offline, timeout, or a backend without the function: keep what we
      // knew; never stop someone working because the check failed.
      return c == null ? null : _judge(c.$1, c.$2);
    }
  }

  /// Throws [AppUpdateRequired] when this build may not sync.
  Future<void> requireSupported() async {
    final r = await check();
    if (r != null) throw r;
  }

  Future<AppUpdateRequired?> _judge(int min, String? note) async {
    if (min <= 0) return null;
    final build = await _currentBuild();
    return build < min ? AppUpdateRequired(minBuild: min, build: build, note: note) : null;
  }

  Future<(int, String?, DateTime)?> _readCache() async {
    final raw = await db.settingsDao.get(cacheKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return ((m['min'] as num).toInt(), m['note'] as String?, DateTime.parse(m['at'] as String));
    } catch (_) {
      return null;
    }
  }
}
