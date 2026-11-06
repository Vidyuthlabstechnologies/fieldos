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
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

String rosterKey(String companyId) => 'team_roster:$companyId';
const cloudUserIdKey = 'cloud_user_id';

Future<void> saveRoster(AppDatabase db, String companyId, List<CloudMember> members, {String? myUserId}) async {
  await db.settingsDao.set(
    rosterKey(companyId),
    jsonEncode([
      for (final m in members) {'user_id': m.userId, 'email': m.email, 'role': m.role},
    ]),
  );
  if (myUserId != null && myUserId.isNotEmpty) await db.settingsDao.set(cloudUserIdKey, myUserId);
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
