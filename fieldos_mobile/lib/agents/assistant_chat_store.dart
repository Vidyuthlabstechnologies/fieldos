/// Ask FieldOS chats, kept on the phone so a chat is still there after
/// leaving the screen or restarting the app, and earlier chats can be
/// opened again. Each person's chats are kept apart, per company.
///
/// Stored in the app's own settings table: an index of chats (newest
/// first) and one row per chat with its messages.
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';

class SavedChatInfo {
  const SavedChatInfo({required this.id, required this.title, required this.updatedAt});
  final String id;

  /// The first thing the person asked.
  final String title;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'updated': updatedAt.toIso8601String()};

  static SavedChatInfo? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'], updated = DateTime.tryParse('${j['updated']}');
    if (id is! String || title is! String || updated == null) return null;
    return SavedChatInfo(id: id, title: title, updatedAt: updated);
  }
}

class AssistantChatStore {
  AssistantChatStore({required this.db, required this.companyId, required this.userId});

  final AppDatabase db;
  final String companyId;
  final String userId;

  /// Chats kept; the oldest go first.
  static const keep = 20;

  // Settings keys hold at most 100 characters: two ids take 73 of them.
  String get _indexKey => 'ai_chats:$companyId:$userId';
  String _chatKey(String id) => 'ai_chat:$companyId:$userId:$id';

  /// A short id for a new chat.
  static String newId() => const Uuid().v4().replaceAll('-', '').substring(0, 12);

  /// Saved chats, newest first.
  Future<List<SavedChatInfo>> list() async {
    try {
      final raw = await db.settingsDao.get(_indexKey);
      if (raw == null || raw.isEmpty) return [];
      return [for (final j in jsonDecode(raw) as List) ?SavedChatInfo.fromJson(j)];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> load(String id) async {
    try {
      final raw = await db.settingsDao.get(_chatKey(id));
      if (raw == null || raw.isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Saves chat [id] and moves it to the top of the list.
  Future<void> save(String id, {required String title, required Map<String, dynamic> chat, DateTime? at}) async {
    await db.settingsDao.set(_chatKey(id), jsonEncode(chat));
    final chats = (await list()).where((c) => c.id != id).toList()
      ..insert(0, SavedChatInfo(id: id, title: title, updatedAt: at ?? DateTime.now()));
    for (final old in chats.skip(keep)) {
      await db.settingsDao.remove(_chatKey(old.id));
    }
    await _writeIndex(chats.take(keep).toList());
  }

  Future<void> delete(String id) async {
    await db.settingsDao.remove(_chatKey(id));
    await _writeIndex((await list()).where((c) => c.id != id).toList());
  }

  Future<void> deleteAll() async {
    for (final c in await list()) {
      await db.settingsDao.remove(_chatKey(c.id));
    }
    await db.settingsDao.remove(_indexKey);
  }

  Future<void> _writeIndex(List<SavedChatInfo> chats) =>
      db.settingsDao.set(_indexKey, jsonEncode([for (final c in chats) c.toJson()]));
}
