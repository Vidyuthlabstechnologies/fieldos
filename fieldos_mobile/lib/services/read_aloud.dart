/// Mitra's voice. Guide lines play as clips recorded with Sarvam's voices
/// in the person's own language mixed with English, the way people talk
/// (assets/voice/, see tool/guide_voice/make_clips.py). Anything without a
/// clip is read by the phone's own text-to-speech, free and offline once
/// the phone has that language's voice. Nothing speaks until the person
/// taps Mitra or the speaker.
library;

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';

import 'package:fieldos_mobile/features/tour/guide_lines.dart';
import 'package:fieldos_mobile/l10n/language.dart';

class ReadAloud {
  ReadAloud._();

  static FlutterTts? _tts;
  static AudioPlayer? _player;
  static Map<String, dynamic>? _manifest;

  /// What is being said now, so a second tap on the same words stops them.
  static final speaking = ValueNotifier<String?>(null);

  /// The phone voice for [text], by its script. Devanagari is Marathi when
  /// the person speaks Marathi, else Hindi.
  static String localeFor(String text, {AppLanguage? spoken}) {
    final lang = spoken ?? spokenLanguage;
    if (RegExp(r'[ఀ-౿]').hasMatch(text)) return 'te-IN';
    if (RegExp(r'[஀-௿]').hasMatch(text)) return 'ta-IN';
    if (RegExp(r'[ಀ-೿]').hasMatch(text)) return 'kn-IN';
    if (RegExp(r'[ऀ-ॿ]').hasMatch(text)) return lang == AppLanguage.mr ? 'mr-IN' : 'hi-IN';
    return 'en-IN';
  }

  /// The guide line [key] in the person's language ([guideLines]), or
  /// [fallback] when there is none.
  static String? guideText(String key, {String? fallback}) => guideLines[spokenLanguage.code]?[key] ?? fallback;

  /// Says Mitra's guide line [key], or stops it if it is playing now.
  static Future<void> toggleGuide(String key, {String? fallback}) async {
    final text = guideText(key, fallback: fallback);
    if (text != null && speaking.value == text) return stop();
    await guide(key, fallback: fallback);
  }

  /// Plays the recorded clip for guide line [key] in the person's
  /// language, or reads the same line with the phone's voice.
  static Future<void> guide(String key, {String? fallback}) async {
    final lang = spokenLanguage.code;
    final text = guideText(key, fallback: fallback);
    if (text == null) return;
    if (await _hasClip(lang, key, text)) {
      try {
        await stop();
        final p = _player ??= AudioPlayer();
        speaking.value = text;
        unawaited(p.onPlayerComplete.first.then((_) {
          if (speaking.value == text) speaking.value = null;
        }));
        await p.play(AssetSource('voice/$lang/$key.mp3'));
        return;
      } catch (_) {
        speaking.value = null;
      }
    }
    await say(text);
  }

  /// Whether a clip was recorded for exactly this [text] (a line changed
  /// since recording falls back to the phone's voice).
  static Future<bool> _hasClip(String lang, String key, String text) async {
    try {
      _manifest ??= jsonDecode(await rootBundle.loadString('assets/voice/manifest.json')) as Map<String, dynamic>;
    } catch (_) {
      _manifest = const {};
    }
    final forLang = _manifest![lang];
    return forLang is Map && forLang[key] == text;
  }

  /// Reads [english] aloud, or stops if it is what is being read now. Screen
  /// labels are spoken in the person's language when there is a
  /// translation, even while the screens are in English.
  static Future<void> toggle(String english) async {
    final t = trSpoken(english);
    if (speaking.value == t) return stop();
    await say(t);
  }

  /// [parts] in the person's language, joined into one thing to say.
  static String spoken(List<String> parts) => parts.map(trSpoken).join('. ');

  static Future<void> say(String text, {double rate = 0.45}) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await stop();
      final tts = _tts ??= FlutterTts();
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
      await _player?.stop();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
  }
}
