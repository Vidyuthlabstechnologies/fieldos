import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fieldos_mobile/agents/voice_dpr_agent.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/sarvam_service.dart';
import 'package:fieldos_mobile/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

// --- fakes ----------------------------------------------------------------

class _FakeSarvam extends SarvamService {
  _FakeSarvam({required this.transcript, required this.structured}) : super();
  final String transcript;
  final StructuredDpr structured;

  @override
  Future<String> transcribe({
    required List<int> audioBytes,
    required String filename,
    required String apiKey,
    String languageCode = 'unknown',
  }) async =>
      transcript;

  @override
  Future<StructuredDpr> structureDpr(String t, String apiKey) async => structured;
}

class _FakeSettings extends SettingsService {
  _FakeSettings(this.key) : super(AppDatabase.memory());
  final String? key;

  @override
  Future<String?> getSarvamApiKey() async => key;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        body,
        200,
        headers: {'content-type': ['application/json']},
      );

  @override
  void close({bool force = false}) {}
}

// --- tests ----------------------------------------------------------------

void main() {
  group('SarvamService parsing', () {
    test('transcribe returns the transcript field', () async {
      final dio = Dio()..httpClientAdapter = _FakeAdapter('{"transcript":"hello world"}');
      final s = SarvamService(dio: dio);
      expect(await s.transcribe(audioBytes: [1], filename: 'a.m4a', apiKey: 'k'), 'hello world');
    });

    test('structureDpr extracts JSON fields', () async {
      const content = '{"work_summary":"plastering","manpower_count":5,"weather":"rain"}';
      final body = jsonEncode({
        'choices': [
          {'message': {'content': content}}
        ]
      });
      final dio = Dio()..httpClientAdapter = _FakeAdapter(body);
      final s = SarvamService(dio: dio);
      final r = await s.structureDpr('transcript', 'k');
      expect(r.workSummary, 'plastering');
      expect(r.manpowerCount, 5);
      expect(r.weather, 'rain');
    });

    test('structureDpr falls back to transcript when content is null', () async {
      final body = jsonEncode({
        'choices': [
          {'message': {'content': null}}
        ]
      });
      final dio = Dio()..httpClientAdapter = _FakeAdapter(body);
      final s = SarvamService(dio: dio);
      final r = await s.structureDpr('raw site report', 'k');
      expect(r.workSummary, 'raw site report');
      expect(r.manpowerCount, 0);
      expect(r.weather, isNull);
    });
  });

  group('VoiceDprAgent wiring', () {
    test('drafts DPR from voice when a key is configured', () async {
      final sarvam = _FakeSarvam(
        transcript: 'we did plastering with 10 workers, weather sunny',
        structured: const StructuredDpr(
          workSummary: 'Plastering done',
          manpowerCount: 10,
          weather: 'sunny',
          transcript: 'we did plastering with 10 workers, weather sunny',
        ),
      );
      final agent = VoiceDprAgent(sarvam: sarvam, settings: _FakeSettings('sk_test'));

      final res = await agent.run({
        'audioBytes': Uint8List.fromList([1, 2, 3]),
        'filename': 'dpr_voice.m4a',
      });

      expect(res.ok, isTrue);
      expect(res.data['work_summary'], 'Plastering done');
      expect(res.data['manpower_count'], 10);
      expect(res.data['weather'], 'sunny');
    });

    test('refuses when no API key is configured', () async {
      final agent = VoiceDprAgent(
        sarvam: _FakeSarvam(
          transcript: 'x',
          structured: const StructuredDpr(workSummary: 'x', manpowerCount: 0, weather: null, transcript: 'x'),
        ),
        settings: _FakeSettings(null),
      );

      final res = await agent.run({
        'audioBytes': Uint8List.fromList([1]),
        'filename': 'dpr_voice.m4a',
      });

      expect(res.ok, isFalse);
      expect(res.message, contains('not configured'));
    });
  });
}
