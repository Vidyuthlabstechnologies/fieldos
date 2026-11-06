/// "Speak your report": the phone listens, shows the words as they come,
/// and hands them to the draft screen. Listening is the phone's own speech
/// recognition, so it's free and works offline once the language's speech
/// pack is installed. Only if the phone can't recognise the chosen
/// language at all does it record instead and send the recording to Sarvam
/// (with an owner's key, and internet).
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/speech_service.dart';
import 'package:fieldos_mobile/services/voice_service.dart';

/// What the sheet hands back.
class VoiceReport {
  const VoiceReport({required this.text, required this.language, this.viaSarvam = false, this.typeInstead = false});

  final String text;
  final SpeechLanguage language;
  final bool viaSarvam;

  /// The person chose to type; [text] holds anything heard so far.
  final bool typeInstead;
}

Future<VoiceReport?> showVoiceReportSheet(BuildContext context) => showModalBottomSheet<VoiceReport>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      enableDrag: false,
      builder: (_) => const VoiceReportSheet(),
    );

enum _Mode { phone, sarvam }

class VoiceReportSheet extends ConsumerStatefulWidget {
  const VoiceReportSheet({super.key});

  @override
  ConsumerState<VoiceReportSheet> createState() => _VoiceReportSheetState();
}

class _VoiceReportSheetState extends ConsumerState<VoiceReportSheet> {
  final _dictation = DictationController();
  SpeechLanguage _language = speechLanguages.first;
  _Mode _mode = _Mode.phone;
  bool _loading = true;

  // Sarvam fallback recording.
  VoiceService? _recorder;
  StreamSubscription<double>? _levelSub;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;
  double _recLevel = 0;
  bool _recording = false;
  String? _sending;
  String? _sarvamError;

  @override
  void initState() {
    super.initState();
    _dictation.addListener(_onDictation);
    _begin();
  }

  Future<void> _begin() async {
    final saved = await ref.read(settingsServiceProvider).getVoiceLanguage();
    _language = saved != null ? speechLanguageFor(saved) : _defaultLanguage();
    if (!mounted) return;
    setState(() => _loading = false);
    await _dictation.start(_language);
  }

  /// The phone's own language when it's one we offer, else English.
  SpeechLanguage _defaultLanguage() {
    final tag = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return speechLanguages.firstWhere((l) => l.code.startsWith('$tag-'), orElse: () => speechLanguages.first);
  }

  void _onDictation() {
    if (!mounted) return;
    final p = _dictation.problem;
    if ((p == SpeechProblem.noRecognizer || p == SpeechProblem.languageUnsupported) &&
        !_dictation.hasText &&
        _mode == _Mode.phone) {
      _maybeSwitchToSarvam();
    }
    setState(() {});
  }

  Future<void> _maybeSwitchToSarvam() async {
    final can = _language.sarvamCode != null && await ref.read(voiceDprAgentProvider).canUseSarvam();
    if (can && mounted) setState(() => _mode = _Mode.sarvam);
  }

  Future<void> _pickLanguage() async {
    final picked = await showModalBottomSheet<SpeechLanguage>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Which language will you speak?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final l in speechLanguages)
              ListTile(
                title: Text(l.isEnglish ? l.englishName : l.name),
                subtitle: l.isEnglish ? null : Text(l.englishName),
                trailing: l.code == _language.code ? const Icon(Icons.check_circle, color: Brand.ok) : null,
                onTap: () => Navigator.pop(ctx, l),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked.code == _language.code || !mounted) return;
    await ref.read(settingsServiceProvider).setVoiceLanguage(picked.code);
    setState(() {
      _language = picked;
      _mode = _Mode.phone;
      _sarvamError = null;
    });
    if (_dictation.state == DictationState.listening || _dictation.state == DictationState.starting) {
      await _dictation.pause();
    }
    await _dictation.start(picked);
  }

  Future<void> _toggleListening() async {
    if (_dictation.state == DictationState.listening || _dictation.state == DictationState.starting) {
      await _dictation.pause();
    } else {
      await _dictation.start(_language);
    }
  }

  Future<void> _done() async {
    final text = await _dictation.finish();
    if (!mounted) return;
    if (text.trim().isEmpty) {
      showSnack(context, "Nothing was heard yet. Tap the mic and speak, or type the report.", error: true);
      return;
    }
    Navigator.pop(context, VoiceReport(text: text, language: _language));
  }

  Future<void> _typeInstead() async {
    final text = _dictation.hasText ? await _dictation.finish() : '';
    await _recorder?.cancel();
    if (mounted) Navigator.pop(context, VoiceReport(text: text, language: _language, typeInstead: true));
  }

  // --- Sarvam fallback -----------------------------------------------------

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _sendRecording();
      return;
    }
    _recorder ??= ref.read(voiceServiceFactoryProvider)();
    try {
      await _recorder!.start();
    } on VoiceException catch (e) {
      setState(() => _sarvamError = e.message);
      return;
    }
    _levelSub = _recorder!.levels.listen((l) => setState(() => _recLevel = l));
    _recElapsed = Duration.zero;
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _recElapsed += const Duration(seconds: 1)));
    setState(() {
      _recording = true;
      _sarvamError = null;
    });
  }

  Future<void> _sendRecording() async {
    _recTimer?.cancel();
    await _levelSub?.cancel();
    final wav = await _recorder!.stop();
    setState(() {
      _recording = false;
      _recLevel = 0;
      _sending = 'Turning your recording into text…';
    });
    final result = await ref.read(voiceDprAgentProvider).run({
      'audioBytes': wav,
      'languageCode': _language.sarvamCode,
      'onProgress': (int done, int total) {
        if (mounted && total > 1) setState(() => _sending = 'Turning your recording into text… ${done + 1 > total ? total : done + 1} of $total');
      },
    });
    if (!mounted) return;
    if (!result.ok) {
      setState(() {
        _sending = null;
        _sarvamError = result.message;
      });
      return;
    }
    Navigator.pop(
      context,
      VoiceReport(text: result.data['transcript'] as String, language: _language, viaSarvam: true),
    );
  }

  @override
  void dispose() {
    _dictation.removeListener(_onDictation);
    _dictation.dispose();
    _recTimer?.cancel();
    _levelSub?.cancel();
    _recorder?.dispose();
    super.dispose();
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Speak your report', style: theme.textTheme.titleLarge)),
              ActionChip(
                avatar: const Icon(Icons.translate, size: 18),
                label: Text(_language.isEnglish ? 'English' : _language.name),
                onPressed: _sending == null && !_recording ? _pickLanguage : null,
                tooltip: 'Change language',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          else if (_mode == _Mode.sarvam)
            _buildSarvam(theme)
          else
            _buildPhone(theme),
        ],
      ),
    );
  }

  Widget _buildPhone(ThemeData theme) {
    final d = _dictation;
    final listening = d.state == DictationState.listening || d.state == DictationState.starting;
    final finishing = d.state == DictationState.finishing;
    final status = switch (d.state) {
      DictationState.starting => 'Starting the microphone…',
      DictationState.listening => 'Listening · ${fmtClock(d.elapsed)}',
      DictationState.finishing => 'Getting the last words…',
      DictationState.paused => d.pausedForSilence ? 'Paused after a long silence. Tap the mic to carry on.' : 'Paused. Tap the mic to carry on.',
      _ => d.problem == null ? 'Tap the mic and speak' : '',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: _MicButton(active: listening, level: d.level, onTap: finishing ? null : _toggleListening)),
        const SizedBox(height: 12),
        if (status.isNotEmpty)
          Text(status, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        _TranscriptBox(text: d.text, hint: _hint()),
        if (d.problem != null) ...[
          const SizedBox(height: 12),
          _ProblemCard(problem: d.problem!, language: _language, onRetry: () => d.start(_language)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(onPressed: finishing ? null : _typeInstead, child: const Text('Type instead')),
            const Spacer(),
            FilledButton.icon(
              onPressed: d.hasText && !finishing ? _done : null,
              icon: const Icon(Icons.check),
              label: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }

  String _hint() => switch (_language.code) {
        'hi-IN' => 'आज क्या काम हुआ, कितने मजदूर थे, मौसम कैसा था और कोई समस्या बताइए। जैसे: "दूसरी मंजिल पर प्लास्टर पूरा हुआ। 12 मिस्त्री और 8 हेल्पर। धूप थी। 3 बजे सीमेंट खत्म हो गया।"',
        'te-IN' => 'ఈరోజు జరిగిన పని, ఎంత మంది పనిచేశారు, వాతావరణం, ఏమైనా సమస్యలు చెప్పండి. ఉదా: "రెండో అంతస్తులో ప్లాస్టరింగ్ పూర్తయింది. 12 మంది మేస్త్రీలు, 8 మంది హెల్పర్లు. ఎండగా ఉంది. 3 గంటలకు సిమెంట్ అయిపోయింది."',
        _ => 'Say what was done today, how many people worked, the weather and any problems. For example: '
            '"Second floor plastering done. 12 masons and 8 helpers. Sunny. Cement ran out at 3 pm."',
      };

  Widget _buildSarvam(ThemeData theme) {
    final sending = _sending != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
          child: Text(
            "This phone can't turn ${_language.englishName} speech into text itself, so FieldOS will record you and "
            'send the recording to Sarvam when you stop. This needs internet.',
            style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: _MicButton(
            active: _recording,
            level: _recLevel,
            icon: _recording ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
            onTap: sending ? null : _toggleRecording,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          sending
              ? _sending!
              : _recording
                  ? 'Recording · ${fmtClock(_recElapsed)} · tap to stop and send'
                  : 'Tap to start recording',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (sending) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_sarvamError != null) ...[
          const SizedBox(height: 12),
          Text(_sarvamError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            TextButton(onPressed: sending ? null : _typeInstead, child: const Text('Type instead')),
          ],
        ),
      ],
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.active, required this.level, required this.onTap, this.icon});

  final bool active;
  final double level;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ring = active ? 1.0 + 0.35 * level : 1.0;
    return Semantics(
      button: true,
      label: active ? 'Pause listening' : 'Start listening',
      child: SizedBox(
        width: 132,
        height: 132,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedScale(
              scale: ring,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (active ? Brand.amber : Brand.navy).withValues(alpha: 0.18),
                ),
              ),
            ),
            Material(
              color: active ? Brand.amber : Brand.navy,
              shape: const CircleBorder(),
              elevation: active ? 4 : 1,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: Icon(icon ?? (active ? Icons.pause_rounded : Icons.mic_rounded),
                      size: 40, color: active ? Brand.navyDeep : Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.text, required this.hint});
  final String text;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 110, maxHeight: 240),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: SizedBox(
          width: double.infinity,
          child: text.isEmpty
              ? Text(hint, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.4)),
        ),
      ),
    );
  }
}

class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.problem, required this.language, required this.onRetry});

  final SpeechProblem problem;
  final SpeechLanguage language;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ios = Platform.isIOS;
    final lang = language.englishName;
    final (String title, String body, List<Widget> actions) = switch (problem) {
      SpeechProblem.permissionDenied => (
          'Microphone is off for FieldOS',
          ios
              ? 'Allow the microphone and speech recognition for FieldOS in Settings, then come back.'
              : 'Allow the microphone for FieldOS in Settings, then come back.',
          [
            FilledButton.tonal(onPressed: () => Geolocator.openAppSettings(), child: const Text('Open Settings')),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      SpeechProblem.needsLanguagePack => (
          ios ? 'This needs internet for $lang' : 'Get the $lang speech pack to work offline',
          ios
              ? 'This iPhone needs internet to recognise $lang speech. Connect and try again, or type the report.'
              : 'There is no internet, and the offline speech pack for $lang is not on this phone yet. '
                  'Connect once, then download it: Google app › Settings › Voice › Offline speech recognition › $lang. '
                  'After that, voice reports work anywhere on site.',
          [TextButton(onPressed: onRetry, child: const Text('Try again'))],
        ),
      SpeechProblem.languageUnsupported || SpeechProblem.noRecognizer => (
          problem == SpeechProblem.noRecognizer ? 'This phone has no speech recognition' : "This phone can't do $lang yet",
          problem == SpeechProblem.noRecognizer
              ? 'Install or update the Google app from the Play Store, then try again. You can also type the report.'
              : 'Update the Google app from the Play Store, pick another language above, or type the report.',
          [TextButton(onPressed: onRetry, child: const Text('Try again'))],
        ),
      SpeechProblem.other => (
          'Listening stopped',
          'The phone stopped listening. Tap Try again, or type the report.',
          [TextButton(onPressed: onRetry, child: const Text('Try again'))],
        ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? const Color(0xFF4A3305) : Brand.warnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(body, style: theme.textTheme.bodyMedium),
          Wrap(spacing: 4, children: actions),
        ],
      ),
    );
  }
}
