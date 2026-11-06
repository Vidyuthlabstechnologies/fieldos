/// Voice reports, heard by the phone itself.
///
/// Android's speech recognition (Google's, built into the phone) and
/// Apple's on iPhone turn speech into text for free. With the language's
/// offline speech pack on the phone it works with no internet at all, which
/// is the normal case on site. Sarvam is only used when the phone has no
/// recognizer or can't do the chosen language (see [VoiceDprAgent]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A language a site report can be spoken in.
class SpeechLanguage {
  const SpeechLanguage(this.code, this.name, this.englishName, {this.sarvamCode, this.translateCode});

  /// BCP-47 code the phone's recognizer takes: 'hi-IN'.
  final String code;

  /// The name in its own script, as people look for it: 'हिन्दी'.
  final String name;
  final String englishName;

  /// Sarvam's code, when Sarvam can transcribe it (Sarvam writes Odia as
  /// 'od-IN').
  final String? sarvamCode;

  /// ML Kit's code when it can translate it to English offline.
  final String? translateCode;

  bool get isEnglish => code.startsWith('en');

  String get label => isEnglish ? englishName : '$name · $englishName';
}

const speechLanguages = <SpeechLanguage>[
  SpeechLanguage('en-IN', 'English', 'English', sarvamCode: 'en-IN'),
  SpeechLanguage('hi-IN', 'हिन्दी', 'Hindi', sarvamCode: 'hi-IN', translateCode: 'hi'),
  SpeechLanguage('te-IN', 'తెలుగు', 'Telugu', sarvamCode: 'te-IN', translateCode: 'te'),
  SpeechLanguage('ta-IN', 'தமிழ்', 'Tamil', sarvamCode: 'ta-IN', translateCode: 'ta'),
  SpeechLanguage('kn-IN', 'ಕನ್ನಡ', 'Kannada', sarvamCode: 'kn-IN', translateCode: 'kn'),
  SpeechLanguage('mr-IN', 'मराठी', 'Marathi', sarvamCode: 'mr-IN', translateCode: 'mr'),
  SpeechLanguage('bn-IN', 'বাংলা', 'Bengali', sarvamCode: 'bn-IN', translateCode: 'bn'),
  SpeechLanguage('gu-IN', 'ગુજરાતી', 'Gujarati', sarvamCode: 'gu-IN', translateCode: 'gu'),
  SpeechLanguage('ml-IN', 'മലയാളം', 'Malayalam', sarvamCode: 'ml-IN'),
  SpeechLanguage('pa-IN', 'ਪੰਜਾਬੀ', 'Punjabi', sarvamCode: 'pa-IN'),
  SpeechLanguage('or-IN', 'ଓଡ଼ିଆ', 'Odia', sarvamCode: 'od-IN'),
  SpeechLanguage('ur-IN', 'اردو', 'Urdu', translateCode: 'ur'),
];

SpeechLanguage speechLanguageFor(String? code) =>
    speechLanguages.firstWhere((l) => l.code == code, orElse: () => speechLanguages.first);

/// Why listening stopped, in terms the screen can explain.
enum SpeechProblem {
  /// No speech recognition on this phone (rare: no Google app).
  noRecognizer,

  /// The microphone (or, on iPhone, speech recognition) was refused.
  permissionDenied,

  /// Offline, and this language's offline speech pack isn't on the phone.
  needsLanguagePack,

  /// The recognizer doesn't do this language at all.
  languageUnsupported,

  /// Something else went wrong in the recognizer.
  other,
}

enum DictationState { idle, starting, listening, paused, finishing, done, failed }

/// The phone's recognizer listens in short stretches: Android stops after a
/// second or two of silence and iPhone after about a minute. This keeps
/// listening across those stops until the person says they're done, and
/// keeps everything heard so far.
class DictationController extends ChangeNotifier {
  DictationController({SpeechToText? speech}) : _speech = speech ?? _shared;

  /// One recognizer for the app: the plugin only takes its listeners once.
  static final SpeechToText _shared = SpeechToText();
  static DictationController? _active;
  static bool _initialized = false;

  final SpeechToText _speech;

  DictationState state = DictationState.idle;
  SpeechProblem? problem;

  /// Words heard and settled, and the stretch being heard right now.
  String _committed = '';
  String _partial = '';
  double level = 0;
  Duration elapsed = Duration.zero;

  /// Set when listening paused on its own after a long silence.
  bool pausedForSilence = false;

  SpeechLanguage _language = speechLanguages.first;
  bool _wantListening = false;
  int _quietRestarts = 0;
  Timer? _ticker;
  Timer? _restartTimer;
  DateTime? _since;
  double _levelMin = 0, _levelMax = 1;
  Completer<void>? _finalResult;

  String get text {
    final parts = [_committed.trim(), _partial.trim()].where((p) => p.isNotEmpty);
    return parts.join(' ');
  }

  bool get hasText => text.isNotEmpty;
  SpeechLanguage get language => _language;

  /// Starts the recognizer once per app run, asking for the microphone (and
  /// on iPhone, speech recognition) the first time. False with [problem]
  /// set when it can't.
  Future<bool> prepare() async {
    _active = this;
    if (_initialized && _speech.isAvailable) return true;
    try {
      _initialized = await _speech.initialize(
        onError: (e) => _active?._onError(e),
        onStatus: (s) => _active?._onStatus(s),
        finalTimeout: const Duration(milliseconds: 1500),
      );
    } on PlatformException catch (e) {
      debugPrint('speech initialize failed: ${e.code} ${e.message}');
      _initialized = false;
    }
    if (!_initialized) {
      final permitted = await _speech.hasPermission.catchError((_) => false);
      problem = permitted ? SpeechProblem.noRecognizer : SpeechProblem.permissionDenied;
      state = DictationState.failed;
      notifyListeners();
    }
    return _initialized;
  }

  /// Start (or carry on) listening in [language].
  Future<void> start(SpeechLanguage language) async {
    _language = language;
    problem = null;
    pausedForSilence = false;
    _quietRestarts = 0;
    if (!await prepare()) return;
    _wantListening = true;
    state = DictationState.starting;
    notifyListeners();
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _since = DateTime.now();
    await _listen();
  }

  Future<void> _listen() async {
    if (!_wantListening) return;
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: SpeechListenOptions(
          localeId: _language.code,
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: true,
          // Long limits: the phone stops sooner on its own, and this
          // controller starts it again until the person taps Done.
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 30),
        ),
      );
      state = DictationState.listening;
      notifyListeners();
    } on ListenFailedException catch (e) {
      debugPrint('listen failed: ${e.message} ${e.details}');
      _fail(SpeechProblem.other);
    } on SpeechToTextNotInitializedException {
      _fail(SpeechProblem.noRecognizer);
    } on PlatformException catch (e) {
      debugPrint('listen failed: ${e.code} ${e.message}');
      _fail(SpeechProblem.other);
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    if (r.recognizedWords.trim().isNotEmpty) _quietRestarts = 0;
    if (r.finalResult) {
      _committed = [_committed.trim(), r.recognizedWords.trim()].where((p) => p.isNotEmpty).join(' ');
      _partial = '';
      _finalResult?.complete();
      _finalResult = null;
    } else {
      _partial = r.recognizedWords;
    }
    notifyListeners();
  }

  void _onLevel(double raw) {
    // Android reports roughly -2..10, iPhone decibels: scale to what this
    // phone has shown so far.
    if (raw < _levelMin) _levelMin = raw;
    if (raw > _levelMax) _levelMax = raw;
    final span = (_levelMax - _levelMin).abs() < 0.01 ? 1 : _levelMax - _levelMin;
    level = ((raw - _levelMin) / span).clamp(0.0, 1.0);
    notifyListeners();
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
      _commitPartial();
      level = 0;
      if (_wantListening) {
        _scheduleRestart();
      } else if (state == DictationState.finishing) {
        state = DictationState.done;
      }
      notifyListeners();
    }
  }

  void _onError(SpeechRecognitionError e) {
    final msg = e.errorMsg;
    if (!_wantListening) return; // Errors after Stop are the recognizer winding down.
    switch (msg) {
      case 'error_no_match':
      case 'error_speech_timeout':
        // Silence. Keep going for a while, then pause so the phone isn't
        // left listening in a pocket.
        _quietRestarts++;
        if (_quietRestarts >= 6) {
          pausedForSilence = true;
          pause();
        } else {
          _scheduleRestart();
        }
      case 'error_network':
      case 'error_network_timeout':
      case 'error_server':
      case 'error_server_disconnected':
        _fail(SpeechProblem.needsLanguagePack);
      case 'error_language_not_supported':
      case 'error_language_unavailable':
        _fail(SpeechProblem.languageUnsupported);
      case 'error_permission':
        _fail(SpeechProblem.permissionDenied);
      case 'error_busy':
      case 'error_client':
      case 'error_audio_error':
      case 'error_too_many_requests':
        _quietRestarts++;
        if (_quietRestarts >= 4) {
          _fail(SpeechProblem.other);
        } else {
          _scheduleRestart(delay: const Duration(milliseconds: 600));
        }
      default:
        if (e.permanent) _fail(SpeechProblem.other);
    }
  }

  void _scheduleRestart({Duration delay = const Duration(milliseconds: 250)}) {
    _restartTimer?.cancel();
    _restartTimer = Timer(delay, () {
      if (_wantListening && !_speech.isListening) _listen();
    });
  }

  void _commitPartial() {
    if (_partial.trim().isEmpty) return;
    _committed = [_committed.trim(), _partial.trim()].where((p) => p.isNotEmpty).join(' ');
    _partial = '';
  }

  void _tick() {
    if (state == DictationState.listening || state == DictationState.starting) {
      final since = _since;
      if (since != null) {
        elapsed += DateTime.now().difference(since);
        _since = DateTime.now();
      }
      notifyListeners();
    }
  }

  void _fail(SpeechProblem p) {
    _wantListening = false;
    _restartTimer?.cancel();
    problem = p;
    _commitPartial();
    // Keep what was heard: a problem halfway through shouldn't lose it.
    state = hasText ? DictationState.paused : DictationState.failed;
    _speech.cancel().catchError((_) {});
    notifyListeners();
  }

  /// Stop listening for now; [start] carries on with the same text.
  Future<void> pause() async {
    _wantListening = false;
    _restartTimer?.cancel();
    _tick();
    _since = null;
    await _speech.stop().catchError((_) {});
    _commitPartial();
    state = DictationState.paused;
    level = 0;
    notifyListeners();
  }

  /// Stop, wait briefly for the last words, and return everything heard.
  Future<String> finish() async {
    final wasListening = _wantListening || _speech.isListening;
    _wantListening = false;
    _restartTimer?.cancel();
    _tick();
    _since = null;
    state = DictationState.finishing;
    notifyListeners();
    if (wasListening) {
      _finalResult = Completer<void>();
      await _speech.stop().catchError((_) {});
      await _finalResult!.future.timeout(const Duration(milliseconds: 1800), onTimeout: () {});
    }
    _commitPartial();
    state = DictationState.done;
    notifyListeners();
    return text;
  }

  /// Replace what was heard, after the person edits it.
  void setText(String value) {
    _committed = value;
    _partial = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _wantListening = false;
    _ticker?.cancel();
    _restartTimer?.cancel();
    if (identical(_active, this)) {
      _speech.cancel().catchError((_) {});
      _active = null;
    }
    super.dispose();
  }
}
