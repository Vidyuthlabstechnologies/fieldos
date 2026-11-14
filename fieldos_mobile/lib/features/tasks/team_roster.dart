/// The company's team as last seen online, kept on the phone so a task can
/// be given to someone, and "My tasks" can find yours, without internet.
///
/// Task assignees are cloud accounts (the server checks the id against its
/// users), so assigning only appears once the company uses Team & sync.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart' show CloudLinks;
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

String rosterKey(String companyId) => 'team_roster:$companyId';
const cloudUserIdKey = 'cloud_user_id';

/// The email of [cloudUserIdKey]'s account. Signing out of Team & sync
/// keeps both: they say whose cloud account this phone's data goes with,
/// which is what Forgot PIN asks for when the phone has no session.
const cloudUserEmailKey = 'cloud_user_email';

Future<void> saveRoster(AppDatabase db, String companyId, List<CloudMember> members, {String? myUserId}) async {
  await db.settingsDao.set(
    rosterKey(companyId),
    jsonEncode([
      for (final m in members) {'user_id': m.userId, 'email': m.email, 'role': m.role},
    ]),
  );
  if (myUserId != null && myUserId.isNotEmpty) {
    await db.settingsDao.set(cloudUserIdKey, myUserId);
    final me = members.where((m) => m.userId == myUserId).firstOrNull;
    if (me != null && me.email.isNotEmpty) await db.settingsDao.set(cloudUserEmailKey, me.email);
  }
}

/// Records [userId] as the cloud account this phone's data goes with.
/// Called when a company on this phone is put on the cloud or joined.
Future<void> recordLinkedAccount(AppDatabase db, {required String? userId, required String? email}) async {
  if (userId == null || userId.isEmpty) return;
  await db.settingsDao.set(cloudUserIdKey, userId);
  if (email != null && email.isNotEmpty) await db.settingsDao.set(cloudUserEmailKey, email);
}

/// The cloud account this phone's data was linked to and synced with, or
/// null when no company on the phone was ever put on the cloud (or the
/// account was deleted, which unlinks them).
Future<({String userId, String email})?> linkedCloudAccount(AppDatabase db) async {
  if ((await CloudLinks(db).all()).isEmpty) return null;
  final id = await db.settingsDao.get(cloudUserIdKey);
  if (id == null || id.isEmpty) return null;
  var email = await db.settingsDao.get(cloudUserEmailKey);
  if (email == null || email.isEmpty) {
    // Phones from before the email was kept: the saved team lists have it.
    final links = await CloudLinks(db).all();
    for (final companyId in links) {
      final me = (await loadRoster(db, companyId)).where((m) => m.userId == id).firstOrNull;
      if (me != null) {
        email = me.email;
        break;
      }
    }
  }
  if (email == null || email.isEmpty) return null;
  return (userId: id, email: email);
}

Future<List<CloudMember>> loadRoster(AppDatabase db, String companyId) async {
  final v = await db.settingsDao.get(rosterKey(companyId));
  if (v == null || v.isEmpty) return const [];
  try {
    return [
      for (final r in (jsonDecode(v) as List).cast<Map>())
        CloudMember(userId: r['user_id'] as String, email: r['email'] as String, role: r['role'] as String),
    ];
  } catch (_) {
    return const [];
  }
}

/// The short name shown on a task: the part of the email before the @.
String memberLabel(CloudMember m) {
  final at = m.email.indexOf('@');
  return at > 0 ? m.email.substring(0, at) : m.email;
}

class TeamRoster {
  const TeamRoster({required this.members, required this.myUserId});
  final List<CloudMember> members;

  /// This phone's cloud account, or null before Team & sync.
  final String? myUserId;

  bool get canAssign => members.isNotEmpty;

  CloudMember? byId(String? id) {
    if (id == null) return null;
    for (final m in members) {
      if (m.userId == id) return m;
    }
    return null;
  }

  /// "You", the member's short name, or null when the task is not assigned.
  String? labelFor(String? assigneeId) {
    if (assigneeId == null || assigneeId.isEmpty) return null;
    if (assigneeId == myUserId) return 'You';
    final m = byId(assigneeId);
    return m == null ? 'Someone on the team' : memberLabel(m);
  }
}

final teamRosterProvider = FutureProvider.autoDispose.family<TeamRoster, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final members = await loadRoster(db, companyId);
  final me = await db.settingsDao.get(cloudUserIdKey);
  return TeamRoster(members: members, myUserId: (me == null || me.isEmpty) ? null : me);
});
