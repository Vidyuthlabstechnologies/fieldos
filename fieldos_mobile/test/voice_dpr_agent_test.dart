import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fieldos_mobile/agents/voice_dpr_agent.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/services/sarvam_service.dart';
import 'package:fieldos_mobile/services/settings_service.dart';
import 'package:fieldos_mobile/services/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

// --- fakes ----------------------------------------------------------------

class _FakeSettings extends SettingsService {
  _FakeSettings(this.key) : super(AppDatabase.memory());
  final String? key;

  @override
  Future<String?> getSarvamApiKey() async => key;
}

/// Answers every request with [body] and records what was sent.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.status = 200});
  final String body;
  final int status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<dynamic>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(body, status, headers: {
      'content-type': ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

/// [seconds] of 16 kHz mono 16-bit silence as a WAV file.
Uint8List _wav(int seconds) {
  final pcm = Uint8List(16000 * 2 * seconds);
  return Uint8List.fromList([..._header(pcm.length), ...pcm]);
}

List<int> _header(int dataLength) {
  final b = ByteData(44);
  void put(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  put(0, 'RIFF');
  b.setUint32(4, 36 + dataLength, Endian.little);
  put(8, 'WAVE');
  put(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 16000, Endian.little);
  b.setUint32(28, 32000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  put(36, 'data');
  b.setUint32(40, dataLength, Endian.little);
  return b.buffer.asUint8List().toList();
}

// --- tests ----------------------------------------------------------------

void main() {
  group('reading a report on the phone', () {
    test('a typed or heard report becomes a draft with no network', () async {
      final agent = VoiceDprAgent(sarvam: SarvamService(), settings: _FakeSettings(null));
      final res = await agent.run({
        'transcript': 'second floor plastering done with 12 masons and 8 helpers. sunny. cement ran out at 3 pm',
      });
      expect(res.ok, isTrue);
      expect(res.data['work_summary'], startsWith('Second floor plastering done'));
      expect(res.data['manpower_count'], 20);
      expect(res.data['weather'], 'Sunny');
      expect(res.data['detected_issues'], contains('material shortage'));
    });

    test('a Telugu report is read too, and its English translation helps', () {
      final d = draftFromTranscript('ఈరోజు 20 మంది కూలీలు వచ్చారు. సిమెంట్ అయిపోయింది.',
          english: 'Today 20 labourers came. The weather was cloudy. Cement ran out.');
      expect(d.manpower, 20);
      expect(d.weather, 'Cloudy');
      expect(d.issues.keys, contains('material shortage'));
      // The summary stays as spoken; translation is the person's choice.
      expect(d.summary, startsWith('ఈరోజు'));
    });

    test('nothing heard is a plain message, not a crash', () async {
      final agent = VoiceDprAgent(sarvam: SarvamService(), settings: _FakeSettings('k'));
      final res = await agent.run({'transcript': '  '});
      expect(res.ok, isFalse);
      expect(res.message, contains('No words were heard'));
    });
  });

  group('Sarvam fallback', () {
    test('only with a key', () async {
      final agent = VoiceDprAgent(sarvam: SarvamService(), settings: _FakeSettings(null));
      expect(await agent.canUseSarvam(), isFalse);
      final res = await agent.run({'audioBytes': _wav(2)});
      expect(res.ok, isFalse);
      expect(res.message, contains('Sarvam key'));
    });

    test('a long recording goes up in pieces under 30 seconds and is joined', () async {
      final adapter = _FakeAdapter('{"transcript":"12 masons on site"}');
      final sarvam = SarvamService(dio: Dio()..httpClientAdapter = adapter);
      final agent = VoiceDprAgent(sarvam: sarvam, settings: _FakeSettings('sk_test'));
      final progress = <int>[];

      final res = await agent.run({
        'audioBytes': _wav(70),
        'languageCode': 'hi-IN',
        'onProgress': (int done, int total) => progress.add(done),
      });

      expect(res.ok, isTrue);
      expect(adapter.requests, hasLength(3)); // 25 + 25 + 20 seconds
      expect(res.data['transcript'], '12 masons on site 12 masons on site 12 masons on site');
      expect(progress.last, 3);
      final form = adapter.requests.first.data as FormData;
      final fields = {for (final f in form.fields) f.key: f.value};
      expect(fields['model'], sarvamSttModel);
      expect(fields['mode'], 'transcribe');
      expect(fields['language_code'], 'hi-IN');
      expect(adapter.requests.first.headers['api-subscription-key'], 'sk_test');
    });

    test('a rejected key says so in plain words', () async {
      final adapter = _FakeAdapter('{"error":"invalid key"}', status: 403);
      final sarvam = SarvamService(dio: Dio()..httpClientAdapter = adapter);
      final agent = VoiceDprAgent(sarvam: sarvam, settings: _FakeSettings('bad'));
      final res = await agent.run({'audioBytes': _wav(3)});
      expect(res.ok, isFalse);
      expect(res.message, contains('not accepted'));
    });
  });

  group('WAV pieces', () {
    test('each piece is a complete WAV of at most 25 seconds', () {
      final audio = WavAudio.parse(_wav(60));
      expect(audio.duration, const Duration(seconds: 60));
      final pieces = audio.chunks(maxSeconds: 25);
      expect(pieces, hasLength(3));
      for (final p in pieces) {
        final w = WavAudio.parse(p);
        expect(w.sampleRate, 16000);
        expect(w.duration.inSeconds, lessThanOrEqualTo(25));
      }
    });

    test('a recording whose header never got its size still reads', () {
      final bytes = Uint8List.fromList([..._header(0), ...Uint8List(32000 * 4)]);
      expect(WavAudio.parse(bytes).duration, const Duration(seconds: 4));
    });

    test('something that is not a WAV is refused', () {
      expect(() => WavAudio.parse(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])), throwsFormatException);
    });
  });
}
