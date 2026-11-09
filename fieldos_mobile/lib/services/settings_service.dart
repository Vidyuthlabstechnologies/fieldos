/// Installation-wide settings, such as the language voice reports are
/// spoken in. (An owner's own Sarvam key used to live here; Sarvam now goes
/// through FieldOS's server with one shared key, so nobody types a key.)
library;

import 'package:fieldos_mobile/data/app_database.dart';

const voiceLanguageSetting = 'voice_language';

class SettingsService {
  SettingsService(this.db);
  final AppDatabase db;

  /// The language voice reports were last spoken in ('hi-IN'), if any.
  Future<String?> getVoiceLanguage() async {
    final v = await db.settingsDao.get(voiceLanguageSetting);
    return v == null || v.isEmpty ? null : v;
  }

  Future<void> setVoiceLanguage(String code) => db.settingsDao.set(voiceLanguageSetting, code);
}
