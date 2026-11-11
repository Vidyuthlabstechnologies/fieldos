/// Blocking a teammate in project chat (issue #152). Blocking hides that
/// person's chat messages on this phone. It does not remove them from the
/// company or hide their site records, which belong to the company.
library;

import 'dart:convert';

import 'package:fieldos_mobile/data/app_database.dart';

class ChatBlockService {
  ChatBlockService(this.db);

  final AppDatabase db;
  static const _key = 'blocked_chat_senders';

  /// Blocked people, by user id, with the name they had when blocked.
  Future<Map<String, String>> blocked() async {
    final raw = await db.settingsDao.get(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> block(String userId, String name) async {
    final b = await blocked();
    b[userId] = name;
    await db.settingsDao.set(_key, jsonEncode(b));
  }

  Future<void> unblock(String userId) async {
    final b = await blocked()
      ..remove(userId);
    await db.settingsDao.set(_key, b.isEmpty ? '' : jsonEncode(b));
  }
}
