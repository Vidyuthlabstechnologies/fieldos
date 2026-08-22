/// Sarvam AI integration for voice-to-DPR. This is the one network call the
/// app makes — everything else is offline. If no key is configured, the
/// feature simply isn't offered.
///
/// Faithful port of `fieldos/sarvam.py`: same endpoints, same system prompt,
/// same defensive fallbacks (a truncated/garbled response never loses the
/// engineer's report — it degrades to the raw transcript).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

class SarvamException implements Exception {
  SarvamException(this.message);
  final String message;
  @override
  String toString() => 'Sarvam error: $message';
}

class SarvamNotConfigured implements Exception {
  @override
  String toString() => 'Sarvam API key is not configured.';
}

const _sttUrl = 'https://api.sarvam.ai/speech-to-text';
const _chatUrl = 'https://api.sarvam.ai/v1/chat/completions';

const _structureSystemPrompt = '''
You turn a construction site engineer's spoken daily progress report into structured JSON. Extract only what's actually said -- don't invent details. Output ONLY a JSON object, no other text, with exactly these keys:
{
  "work_summary": "<a clean written summary of the work described, in English>",
  "manpower_count": <integer number of workers mentioned, or 0 if not mentioned>,
  "weather": "<one word/short phrase for weather if mentioned, else null>"
}''';

class StructuredDpr {
  const StructuredDpr({
    required this.workSummary,
    required this.manpowerCount,
    required this.weather,
    required this.transcript,
  });
  final String workSummary;
  final int manpowerCount;
  final String? weather;
  final String transcript;
}

class SarvamService {
  SarvamService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

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
          'model': 'saaras:v3',
          'language_code': languageCode,
          'with_timestamps': 'false',
          'file': MultipartFile.fromBytes(audioBytes, filename: filename),
        }),
      );
      final json = resp.data as Map<String, dynamic>;
      final transcript = json['transcript'] as String?;
      if (transcript == null || transcript.isEmpty) {
        throw SarvamException('Empty transcript returned.');
      }
      return transcript;
    } on DioException catch (e) {
      throw SarvamException('STT request failed: ${e.message}');
    }
  }

  /// Turn a transcript into structured DPR fields. Always returns *something*
  /// usable — on any failure it falls back to the raw transcript so the
  /// engineer's report is never lost.
  Future<StructuredDpr> structureDpr(String transcript, String apiKey) async {
    try {
      final resp = await _dio.post(
        _chatUrl,
        options: Options(headers: {'api-subscription-key': apiKey}),
        data: {
          'model': 'sarvam-105b',
          'messages': [
            {'role': 'system', 'content': _structureSystemPrompt},
            {'role': 'user', 'content': transcript},
          ],
          'temperature': 0.1,
          // sarvam-105b is a reasoning model; a small budget truncates its
          // answer (finish_reason: "length") and content comes back null.
          'max_tokens': 2000,
        },
      );
      final json = resp.data as Map<String, dynamic>;
      final content = (json['choices'] as List).first['message']['content'] as String?;
      if (content == null || content.isEmpty) {
        return StructuredDpr(
          workSummary: transcript,
          manpowerCount: 0,
          weather: null,
          transcript: transcript,
        );
      }
      final cleaned = content
          .trim()
          .replaceFirst(RegExp(r'^```json'), '')
          .replaceFirst(RegExp(r'^```'), '')
          .replaceAll(RegExp(r'```$'), '')
          .trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      return StructuredDpr(
        workSummary: (parsed['work_summary'] as String?) ?? transcript,
        manpowerCount: int.tryParse(parsed['manpower_count']?.toString() ?? '') ?? 0,
        weather: parsed['weather'] as String?,
        transcript: transcript,
      );
    } on DioException catch (e) {
      throw SarvamException('Structuring request failed: ${e.message}');
    } on FormatException {
      return StructuredDpr(
        workSummary: transcript,
        manpowerCount: 0,
        weather: null,
        transcript: transcript,
      );
    }
  }
}
