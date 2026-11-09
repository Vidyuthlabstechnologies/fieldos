/// Sarvam speech-to-text: the fallback for phones that can't turn speech
/// into text themselves (no recognizer, or not in the chosen language).
/// Everything else about a voice report (headcount, weather, issues,
/// translation) happens on the phone, offline and free; Sarvam is never
/// called when the phone can do the job.
///
/// The recording goes to FieldOS's own server ([AiBackend]), which holds the
/// one shared Sarvam key: nobody has to get or type a key. It needs a
/// FieldOS sign-in (Team & sync) and internet. Sarvam takes at most 30
/// seconds per request, so a longer recording goes up in 25-second pieces
/// and the text is joined back together.
library;

import 'dart:typed_data';

import 'package:fieldos_mobile/services/ai_backend.dart';
import 'package:fieldos_mobile/services/voice_service.dart';

class SarvamException implements Exception {
  SarvamException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SarvamService {
  SarvamService(this.backend);

  final AiBackend backend;

  /// Whether the fallback can be used on this phone now.
  bool get available => backend.signedIn;

  /// Text of a WAV recording of any length: split into 25-second pieces,
  /// sent one after another, and joined. [onProgress] reports pieces done.
  Future<String> transcribeWav({
    required Uint8List wav,
    String languageCode = 'unknown',
    void Function(int done, int total)? onProgress,
  }) async {
    final WavAudio audio;
    try {
      audio = WavAudio.parse(wav);
    } on FormatException {
      throw SarvamException('The recording could not be read. Please record it again.');
    }
    final pieces = audio.chunks(maxSeconds: 25);
    final texts = <String>[];
    for (var i = 0; i < pieces.length; i++) {
      onProgress?.call(i, pieces.length);
      try {
        final text = await backend.transcribe(pieces[i], languageCode: languageCode);
        if (text.isNotEmpty) texts.add(text);
      } on AiException catch (e) {
        throw SarvamException(e.message);
      }
    }
    onProgress?.call(pieces.length, pieces.length);
    final joined = texts.join(' ').trim();
    if (joined.isEmpty) throw SarvamException("No words were caught. Speak a little closer to the phone and try again.");
    return joined;
  }
}
