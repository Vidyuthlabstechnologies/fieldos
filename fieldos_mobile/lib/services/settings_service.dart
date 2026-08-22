/// Installation-wide settings, including the optional Sarvam API key.
///
/// The key is write-only from the UI's perspective: it can be set, but the
/// value is never echoed back (mirrors the desktop Settings behaviour). Only
/// a company owner may write it — enforcement lives in the UI/auth layer.
library;

import 'package:fieldos_mobile/data/app_database.dart';

const sarvamApiKeySetting = 'sarvam_api_key';

class SettingsService {
  SettingsService(this.db);
  final AppDatabase db;

  Future<String?> getSarvamApiKey() => db.settingsDao.get(sarvamApiKeySetting);

  Future<bool> isVoiceConfigured() async =>
      (await getSarvamApiKey())?.isNotEmpty ?? false;

  /// Persist the key. Callers must have already verified the user is a company
  /// owner (owner-gated write, per the desktop authorization fix).
  Future<void> setSarvamApiKey(String key) =>
      db.settingsDao.set(sarvamApiKeySetting, key.trim());

  Future<void> clearSarvamApiKey() => db.settingsDao.set(sarvamApiKeySetting, '');
}
