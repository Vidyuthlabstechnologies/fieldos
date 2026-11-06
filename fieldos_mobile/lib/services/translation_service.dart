/// Translating a site report into English on the phone, with Google ML
/// Kit: free, private (the text never leaves the phone) and offline once
/// the language's pack (about 30 MB) has been downloaded the first time.
///
/// English matters because the PDF report and most clients read English,
/// while engineers speak their reports in Hindi, Telugu and the rest.
library;

import 'package:flutter/services.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

class TranslationException implements Exception {
  TranslationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TranslationService {
  TranslationService({OnDeviceTranslatorModelManager? models}) : _models = models ?? OnDeviceTranslatorModelManager();

  final OnDeviceTranslatorModelManager _models;

  /// Whether [code] (an ML Kit code like 'hi') can be translated at all.
  static bool supports(String? code) => code != null && BCP47Code.fromRawValue(code) != null;

  /// Whether the language pack is already on the phone, so translation
  /// works right now with no internet.
  Future<bool> isReady(String code) async {
    try {
      return await _models.isModelDownloaded(code) && await _models.isModelDownloaded(TranslateLanguage.english.bcpCode);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Downloads the pack for [code] (and English). Needs internet, once.
  Future<void> download(String code) async {
    try {
      final ok = await _models.downloadModel(code, isWifiRequired: false) &&
          await _models.downloadModel(TranslateLanguage.english.bcpCode, isWifiRequired: false);
      if (!ok) throw TranslationException('The language pack could not be downloaded. Check your internet and try again.');
    } on PlatformException catch (e) {
      throw TranslationException(
          'The language pack could not be downloaded (${e.message ?? e.code}). Check your internet and try again.');
    }
  }

  /// [text] in English. The pack must be ready ([isReady]).
  Future<String> toEnglish(String text, String code) async {
    final source = BCP47Code.fromRawValue(code);
    if (source == null) throw TranslationException('This language can’t be translated on the phone yet.');
    final translator = OnDeviceTranslator(sourceLanguage: source, targetLanguage: TranslateLanguage.english);
    try {
      // Sentence by sentence keeps long reports within what the model
      // handles well.
      final parts = text.split(RegExp(r'(?<=[.!?।॥])\s+')).where((p) => p.trim().isNotEmpty).toList();
      final out = <String>[];
      for (final p in parts) {
        out.add((await translator.translateText(p.trim())).trim());
      }
      return out.join(' ');
    } on PlatformException catch (e) {
      throw TranslationException('Translation failed (${e.message ?? e.code}). Try again.');
    } finally {
      await translator.close().catchError((_) {});
    }
  }
}
