/// Plain audio recording, for the one case the phone can't turn speech into
/// text itself and the report goes to Sarvam instead (see
/// [VoiceDprAgent]). Records 16 kHz mono WAV, which Sarvam reads best, and
/// stops when the person taps Stop.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceException implements Exception {
  VoiceException(this.message, {this.permissionDenied = false});
  final String message;
  final bool permissionDenied;
  @override
  String toString() => message;
}

class VoiceService {
  VoiceService({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();
  final AudioRecorder _recorder;

  String? _path;
  StreamSubscription<Amplitude>? _amp;
  final _levels = StreamController<double>.broadcast();

  /// The microphone level, 0 to 1, while recording.
  Stream<double> get levels => _levels.stream;

  bool get isRecording => _path != null;

  /// Starts recording. Throws [VoiceException] when the microphone is
  /// refused or busy.
  Future<void> start() async {
    if (_path != null) return;
    if (!await _recorder.hasPermission()) {
      throw VoiceException('FieldOS needs the microphone to record your report.', permissionDenied: true);
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_report_${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1, noiseSuppress: true),
        path: path,
      );
    } on PlatformException catch (e) {
      throw VoiceException('The microphone could not start (${e.message ?? e.code}). Close other apps using it and try again.');
    }
    _path = path;
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((a) {
      // dBFS: about -45 is quiet room noise, 0 is as loud as it gets.
      _levels.add(((a.current + 45) / 45).clamp(0.0, 1.0));
    });
  }

  /// Stops and returns the recording as WAV bytes (the file is removed).
  Future<Uint8List> stop() async {
    final path = _path;
    if (path == null) return Uint8List(0);
    await _amp?.cancel();
    _amp = null;
    final saved = await _recorder.stop() ?? path;
    _path = null;
    final file = File(saved);
    if (!await file.exists()) return Uint8List(0);
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    return bytes;
  }

  /// Stops and throws the recording away.
  Future<void> cancel() async {
    await _amp?.cancel();
    _amp = null;
    if (_path != null) {
      await _recorder.cancel().catchError((_) {});
      _path = null;
    }
  }

  void dispose() {
    cancel();
    _levels.close();
    _recorder.dispose();
  }
}

/// A WAV file's sound, split into pieces Sarvam accepts (it takes at most
/// 30 seconds per request). Each piece is a complete WAV file of its own.
class WavAudio {
  WavAudio._(this.sampleRate, this.channels, this.bitsPerSample, this.pcm);

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Uint8List pcm;

  int get bytesPerSecond => sampleRate * channels * (bitsPerSample ~/ 8);
  Duration get duration => Duration(milliseconds: bytesPerSecond == 0 ? 0 : pcm.length * 1000 ~/ bytesPerSecond);

  /// Reads a RIFF/WAVE file. Phones sometimes write extra chunks, or leave
  /// the data size unset while recording, so this walks the chunks rather
  /// than assuming a 44-byte header.
  static WavAudio parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
    if (bytes.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Not a WAV recording');
    }
    var sampleRate = 16000, channels = 1, bits = 16;
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = tag(at);
      var size = data.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (size == 0 || size == 0xFFFFFFFF || body + size > bytes.length) size = bytes.length - body;
        return WavAudio._(sampleRate, channels, bits, Uint8List.sublistView(bytes, body, body + size));
      }
      at = body + size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('The recording has no sound data');
  }

  /// Pieces of at most [maxSeconds], each a standalone WAV file.
  List<Uint8List> chunks({int maxSeconds = 25}) {
    final frame = channels * (bitsPerSample ~/ 8);
    var step = bytesPerSecond * maxSeconds;
    step -= step % (frame == 0 ? 1 : frame);
    if (step <= 0) return [toWav(pcm)];
    final out = <Uint8List>[];
    for (var start = 0; start < pcm.length; start += step) {
      final end = (start + step).clamp(0, pcm.length);
      // Skip a sliver at the end: under half a second is just the tap on Stop.
      if (end - start < bytesPerSecond ~/ 2 && out.isNotEmpty) break;
      out.add(toWav(Uint8List.sublistView(pcm, start, end)));
    }
    return out;
  }

  Uint8List toWav(Uint8List samples) {
    final header = ByteData(44);
    void put(int at, String s) {
      for (var i = 0; i < 4; i++) {
        header.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    put(0, 'RIFF');
    header.setUint32(4, 36 + samples.length, Endian.little);
    put(8, 'WAVE');
    put(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, bytesPerSecond, Endian.little);
    header.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    put(36, 'data');
    header.setUint32(40, samples.length, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...samples]);
  }
}
