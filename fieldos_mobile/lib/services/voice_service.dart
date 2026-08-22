/// Voice capture for the optional voice-to-DPR feature.
///
/// Records to a local temp file, then hands back the raw bytes for the
/// [VoiceDprAgent] to send to Sarvam. Requires a real device/mic at runtime;
/// the rest of the app works fully offline without it.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceException implements Exception {
  VoiceException(this.message);
  final String message;
  @override
  String toString() => 'Voice error: $message';
}

class VoiceService {
  VoiceService({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();
  final AudioRecorder _recorder;

  bool _recording = false;

  Future<bool> get hasPermission => _recorder.hasPermission();

  /// Record up to [maxDuration], stop, and return the audio file bytes.
  /// Throws [VoiceException] if the mic is unavailable or permission is denied.
  Future<Uint8List> record({Duration maxDuration = const Duration(minutes: 2)}) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/dpr_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(const RecordConfig(), path: path);
    } on PlatformException catch (e) {
      throw VoiceException(
        e.code == 'Permission' || (e.message ?? '').toLowerCase().contains('permission')
            ? 'Microphone permission was denied. Enable it in system settings to use voice-to-DPR.'
            : 'Could not start recording: ${e.message ?? e.code}',
      );
    }
    _recording = true;
    await Future.delayed(maxDuration);
    if (_recording) {
      await stop();
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  Future<void> stop() async {
    if (_recording) {
      await _recorder.stop();
      _recording = false;
    }
  }

  void dispose() => _recorder.dispose();
}
