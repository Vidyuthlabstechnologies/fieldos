/// Sarvam speech-to-text: the fallback for phones that can't turn speech
/// into text themselves (no recognizer, or not in the chosen language).
/// Everything else about a voice report (headcount, weather, issues,
/// translation) happens on the phone, offline and free; Sarvam is never
/// called when the phone can do the job.
///
/// Only used when a company owner has added their own Sarvam key in
/// Settings. Sarvam's REST endpoint takes at most 30 seconds per request,
/// so a longer recording goes up in 25-second pieces and the text is
/// joined back together.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:fieldos_mobile/services/voice_service.dart';

class SarvamException implements Exception {
  SarvamException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SarvamNotConfigured implements Exception {
  @override
  String toString() => 'Sarvam API key is not configured.';
}

const _sttUrl = 'https://api.sarvam.ai/speech-to-text';

/// Sarvam's default, recommended speech model (saaras:v3 takes the same
/// request if this ever needs to go back).
const sarvamSttModel = 'saaras:v4';

class SarvamService {
  SarvamService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 60),
            ));

  final Dio _dio;

  /// Text of one recording of at most 30 seconds, in the language spoken.
  Future<String> transcribe({
    required List<int> audioBytes,
    required String filename,
    required String apiKey,
    String languageCode = 'unknown',
  }) async {
    try {
      final resp = await _dio.post(
        _sttUrl,
        options: Options(headers: {'api-subscription-key': apiKey}),
        data: FormData.fromMap({
          'model': sarvamSttModel,
          'mode': 'transcribe',
          'language_code': languageCode,
          'file': MultipartFile.fromBytes(audioBytes, filename: filename),
        }),
      );
      final json = resp.data as Map<String, dynamic>;
      return ((json['transcript'] as String?) ?? '').trim();
    } on DioException catch (e) {
      throw SarvamException(_explain(e));
    }
  }

  /// Text of a WAV recording of any length: split into 25-second pieces,
  /// sent one after another, and joined. [onProgress] reports pieces done.
  Future<String> transcribeWav({
    required Uint8List wav,
    required String apiKey,
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
      final text = await transcribe(
        audioBytes: pieces[i],
        filename: 'report_${i + 1}.wav',
        apiKey: apiKey,
        languageCode: languageCode,
      );
      if (text.isNotEmpty) texts.add(text);
    }
    onProgress?.call(pieces.length, pieces.length);
    final joined = texts.join(' ').trim();
    if (joined.isEmpty) throw SarvamException("Sarvam didn't catch any words. Speak a little closer to the phone and try again.");
    return joined;
  }

  static String _explain(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'The Sarvam key in Settings was not accepted. Ask a company owner to check it.';
    }
    if (status == 429) return 'Sarvam is busy or the key has run out of credit. Try again in a minute.';
    if (status == 422 || status == 400) {
      return 'Sarvam could not use this recording. Try again, or type the report instead.';
    }
    if (status != null && status >= 500) return 'Sarvam is having trouble right now. Try again later.';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Sarvam took too long to answer. Check your internet and try again.';
      case DioExceptionType.connectionError:
        return 'No internet connection. Sarvam needs internet to turn your recording into text.';
      default:
        return 'Could not reach Sarvam. Check your internet and try again.';
    }
  }
}
