/// Mitra's voice: reads words aloud with the phone's own text-to-speech,
/// free and offline once the phone has that language's voice. It is for
/// people who find reading slow: the tour, Mitra's tips and the
/// assistant's answers can all be heard instead of read.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:fieldos_mobile/l10n/language.dart';

class ReadAloud {
  ReadAloud._();

  static FlutterTts? _tts;

  /// What is being read now, so a second tap on the same words stops them.
  static final speaking = ValueNotifier<String?>(null);

  /// The voice for [text], by its script. Devanagari is Marathi when the
  /// app is in Marathi, else Hindi.
  static String localeFor(String text, {AppLanguage? appLanguage}) {
    final app = appLanguage ?? currentLanguage;
    if (RegExp(r'[ఀ-౿]').hasMatch(text)) return 'te-IN';
    if (RegExp(r'[஀-௿]').hasMatch(text)) return 'ta-IN';
    if (RegExp(r'[ಀ-೿]').hasMatch(text)) return 'kn-IN';
    if (RegExp(r'[ऀ-ॿ]').hasMatch(text)) return app == AppLanguage.mr ? 'mr-IN' : 'hi-IN';
    return 'en-IN';
  }

  /// Reads [text] aloud, or stops if it is the text being read now.
  static Future<void> toggle(String text) async {
    if (speaking.value == text) return stop();
    await say(text);
  }

  static Future<void> say(String text, {double rate = 0.45}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      final tts = _tts ??= FlutterTts();
      await tts.stop();
      await tts.setLanguage(localeFor(t));
      await tts.setSpeechRate(rate);
      tts.setCompletionHandler(() => speaking.value = null);
      tts.setCancelHandler(() => speaking.value = null);
      tts.setErrorHandler((_) => speaking.value = null);
      speaking.value = t;
      await tts.speak(t);
    } catch (_) {
      // No voice for this language on the phone: the words stay on screen.
      speaking.value = null;
    }
  }

  static Future<void> stop() async {
    speaking.value = null;
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
