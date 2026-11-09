/// Voice-to-DPR agent: a spoken site report in, a DPR draft out (summary,
/// headcount, weather and the issues worth raising), for the engineer to
/// check and save.
///
/// The phone hears the report itself ([DictationController]), and this
/// agent reads it on the phone ([extractManpower], [extractWeather],
/// [detectIssueEvidence]): free, offline, no account. Only when the phone
/// can't recognise speech in the chosen language does a recording go to
/// Sarvam for the words, through FieldOS's server and its shared key.
library;

import 'dart:typed_data';

import 'package:fieldos_mobile/agents/agent.dart';
import 'package:fieldos_mobile/agents/dpr_intake.dart';
import 'package:fieldos_mobile/agents/site_report_parser.dart';
import 'package:fieldos_mobile/services/sarvam_service.dart';

/// What a voice report says, ready for the draft screen.
class DprDraft {
  const DprDraft({
    required this.transcript,
    required this.summary,
    this.manpower,
    this.weather,
    this.issues = const {},
    this.delayFlagged = false,
  });

  /// The words as heard.
  final String transcript;

  /// Tidied for the report.
  final String summary;
  final int? manpower;
  final String? weather;

  /// Issue name ("water ingress") to the words that raised it.
  final Map<String, String> issues;
  final bool delayFlagged;
}

/// Reads [transcript] (and its English translation, when there is one, so
/// a Hindi report that names the weather in English still finds it).
DprDraft draftFromTranscript(String transcript, {String? english}) {
  final readings = [transcript, if (english != null && english.trim().isNotEmpty) english];
  int? manpower;
  String? weather;
  final issues = <String, String>{};
  var delay = false;
  for (final text in readings) {
    manpower ??= extractManpower(text);
    weather ??= extractWeather(text);
    for (final e in detectIssueEvidence(text).entries) {
      issues.putIfAbsent(e.key, () => e.value);
    }
    delay = delay || mentionsDelay(text);
  }
  return DprDraft(
    transcript: transcript.trim(),
    summary: tidySummary(transcript),
    manpower: manpower,
    weather: weather,
    issues: issues,
    delayFlagged: delay,
  );
}

class VoiceDprAgent implements Agent {
  VoiceDprAgent({required this.sarvam});
  final SarvamService sarvam;

  @override
  String get name => 'voice_dpr';

  @override
  String get description =>
      'Turn a spoken site report into a DPR draft (summary, manpower, weather, issues), on the phone.';

  @override
  List<AgentTool> get tools => const [
        AgentTool(name: 'read_report', description: 'Find headcount, weather and issues in the report, offline.'),
        AgentTool(name: 'transcribe_fallback', description: 'Speech-to-text via Sarvam when the phone cannot.'),
      ];

  /// Whether the Sarvam fallback can be used: it goes through FieldOS's
  /// server, so the phone has to be signed in to Team & sync.
  Future<bool> canUseSarvam() async => sarvam.available;

  /// `input` keys:
  ///  - `transcript` (String): what the phone heard. The usual path.
  ///  - `english` (String, optional): its English translation.
  ///  - or `audioBytes` (Uint8List, WAV) with `languageCode` (Sarvam's
  ///    code, optional): a recording for the Sarvam fallback.
  ///  - `onProgress` (optional `void Function(int, int)`): Sarvam pieces done.
  @override
  Future<AgentResult> run(Map<String, dynamic> input) async {
    var transcript = ((input['transcript'] as String?) ?? '').trim();
    if (transcript.isEmpty) {
      final audio = input['audioBytes'] as Uint8List?;
      if (audio == null || audio.isEmpty) {
        return const AgentResult(ok: false, message: 'No words were heard. Try again, a little closer to the phone.');
      }
      if (!sarvam.available) {
        return const AgentResult(
          ok: false,
          message: "This phone can't turn speech into text in this language by itself. Type the report instead, "
              'or sign in to Team & sync so FieldOS can do it over the internet.',
        );
      }
      try {
        transcript = await sarvam.transcribeWav(
          wav: audio,
          languageCode: (input['languageCode'] as String?) ?? 'unknown',
          onProgress: input['onProgress'] as void Function(int, int)?,
        );
      } on SarvamException catch (e) {
        return AgentResult(ok: false, message: e.message);
      }
    }

    final draft = draftFromTranscript(transcript, english: input['english'] as String?);
    return AgentResult(
      ok: true,
      message: draft.issues.isEmpty ? 'Drafted the DPR from your report.' : 'Drafted the DPR and found ${draft.issues.length} issue(s).',
      data: {
        'transcript': draft.transcript,
        'work_summary': draft.summary,
        'manpower_count': draft.manpower,
        'weather': draft.weather,
        'detected_issues': draft.issues.keys.toList(),
        'issue_evidence': draft.issues,
        'delay_flagged': draft.delayFlagged,
      },
    );
  }
}
