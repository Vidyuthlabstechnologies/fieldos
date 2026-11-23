/// Proof of consent, kept on the server (DPDP Act s.6(10): the company
/// must be able to show that notice was given and consent obtained).
///
/// Every time a person gives or withdraws the AI assistant or the check-in
/// photo and location consent, the choice is also put in a small outbox on
/// the phone, per local account. When that account is signed in to Team &
/// sync, the outbox is sent to `consent_records` (append-only, see
/// supabase/migrations/20261123210000_india_compliance.sql) and emptied. An
/// account that never signs in keeps its proof only on the phone, which is
/// also the only place its data is.
///
/// The outbox is keyed by the LOCAL account id and only sent while that
/// account is the one using the app, so one person's choice is never filed
/// under another person's cloud sign-in on a shared phone.
library;

import 'dart:async';
import 'dart:convert';

import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/legal/legal_texts.dart';

enum ConsentPurpose {
  aiAssistant('ai_assistant'),
  attendancePhotoLocation('attendance_photo_location');

  const ConsentPurpose(this.wire);
  final String wire;
}

String consentOutboxKey(String userId) => 'consent_outbox:$userId';

/// Where the signed-in cloud session is kept (SettingsSessionStore.key).
const cloudSessionSettingsKey = 'cloud_session';

/// Queues [granted] for [purpose] for [userId]. Called by setAiConsent and
/// setAttendanceConsent, so every path that changes a consent leaves proof.
Future<void> queueConsentRecord(
  AppDatabase db,
  String userId,
  ConsentPurpose purpose,
  bool granted, {
  DateTime? at,
  String? language,
}) async {
  if (userId.isEmpty) return;
  final key = consentOutboxKey(userId);
  final list = await _read(db, key);
  list.add({
    'purpose': purpose.wire,
    'granted': granted,
    'given_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
    'notice_version': privacyPolicy.updated,
    'language': ?language,
  });
  // A person flipping a switch back and forth offline for months must not
  // grow settings without bound; the newest 200 choices are plenty of proof.
  final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
  await db.settingsDao.set(key, jsonEncode(trimmed));
}

/// The choices still waiting to be sent for [userId].
Future<List<Map<String, dynamic>>> pendingConsentRecords(AppDatabase db, String userId) =>
    _read(db, consentOutboxKey(userId));

Future<List<Map<String, dynamic>>> _read(AppDatabase db, String key) async {
  final raw = await db.settingsDao.get(key);
  if (raw == null || raw.isEmpty) return [];
  try {
    return [for (final e in jsonDecode(raw) as List) Map<String, dynamic>.from(e as Map)];
  } catch (_) {
    return [];
  }
}

class ConsentRecorder {
  ConsentRecorder({required this.db, required this.client, this.appVersion});

  final AppDatabase db;

  /// Null in a build without cloud. A getter, so that a phone that never
  /// turned on Team & sync never even builds a cloud client for this.
  final SupabaseClient? Function()? client;
  final String? appVersion;

  /// Sends [localUserId]'s waiting choices if a cloud session is signed in.
  /// Returns how many were sent. Never throws: a failed send stays queued
  /// for the next call.
  Future<int> flush(String localUserId) async {
    if (client == null || localUserId.isEmpty) return 0;
    final key = consentOutboxKey(localUserId);
    final pending = await _read(db, key);
    if (pending.isEmpty) return 0;
    // No saved cloud session (Team & sync never turned on, or signed out).
    final session = await db.settingsDao.get(cloudSessionSettingsKey);
    if (session == null || session.isEmpty) return 0;
    final c = client!();
    if (c == null || c.auth.currentUser == null) return 0;
    try {
      await c.from('consent_records').insert([
        for (final p in pending) {...p, 'app_version': ?appVersion},
      ]);
    } catch (_) {
      return 0;
    }
    // Only drop what was sent: a choice made while the insert was in flight
    // stays for the next flush.
    final now = await _read(db, key);
    final rest = now.length > pending.length ? now.sublist(pending.length) : <Map<String, dynamic>>[];
    if (rest.isEmpty) {
      await db.settingsDao.remove(key);
    } else {
      await db.settingsDao.set(key, jsonEncode(rest));
    }
    return pending.length;
  }

  /// Fire-and-forget [flush], for UI code right after a choice.
  void nudge(String localUserId) => unawaited(flush(localUserId));
}
