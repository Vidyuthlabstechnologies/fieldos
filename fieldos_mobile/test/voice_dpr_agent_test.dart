import 'dart:typed_data';

import 'package:fieldos_mobile/agents/voice_dpr_agent.dart';
import 'package:fieldos_mobile/services/sarvam_service.dart';
import 'package:fieldos_mobile/services/ai_backend.dart';
import 'package:fieldos_mobile/services/voice_service.dart';
import 'package:flutter_test/flutter_test.dart';

// --- fakes ----------------------------------------------------------------

/// FieldOS's server, answering speech requests with [text], or refusing.
class _FakeAi implements AiBackend {
  _FakeAi({this.signedIn = true, this.error});
  @override
  final bool signedIn;
  final AiException? error;
  final pieces = <(int bytes, String lang)>[];

  @override
  Future<AiReply> chat(List<Map<String, dynamic>> messages) => throw UnimplementedError();

  @override
  Future<String> transcribe(Uint8List wav, {String languageCode = 'unknown'}) async {
    pieces.add((wav.length, languageCode));
    if (error != null) throw error!;
    return '12 masons on site';
  }
}

VoiceDprAgent _agent([_FakeAi? ai]) => VoiceDprAgent(sarvam: SarvamService(ai ?? _FakeAi()));

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
      final agent = _agent();
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
      final agent = _agent();
      final res = await agent.run({'transcript': '  '});
      expect(res.ok, isFalse);
      expect(res.message, contains('No words were heard'));
    });
  });

  group('Sarvam fallback, through FieldOS\'s server', () {
    test('needs a FieldOS sign-in, never a key', () async {
      final agent = _agent(_FakeAi(signedIn: false));
      expect(await agent.canUseSarvam(), isFalse);
      final res = await agent.run({'audioBytes': _wav(2)});
      expect(res.ok, isFalse);
      expect(res.message, contains('Team & sync'));
      expect(await _agent().canUseSarvam(), isTrue);
    });

    test('a long recording goes up in pieces under 30 seconds and is joined', () async {
      final ai = _FakeAi();
      final progress = <int>[];
      final res = await _agent(ai).run({
        'audioBytes': _wav(70),
        'languageCode': 'hi-IN',
        'onProgress': (int done, int total) => progress.add(done),
      });

      expect(res.ok, isTrue);
      expect(ai.pieces, hasLength(3)); // 25 + 25 + 20 seconds
      expect(ai.pieces.every((p) => p.$1 <= 44 + 25 * 32000 && p.$2 == 'hi-IN'), isTrue);
      expect(res.data['transcript'], '12 masons on site 12 masons on site 12 masons on site');
      expect(progress.last, 3);
    });

    test("the server's reason is shown in plain words", () async {
      final ai = _FakeAi(error: AiException("Today's voice time is used up.", code: 'daily_limit'));
      final res = await _agent(ai).run({'audioBytes': _wav(3)});
      expect(res.ok, isFalse);
      expect(res.message, "Today's voice time is used up.");
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
