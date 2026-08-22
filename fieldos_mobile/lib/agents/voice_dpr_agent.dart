/// Voice-to-DPR agent: records/uploaded audio -> Sarvam STT -> Sarvam LLM ->
/// structured DPR draft. This is the app's first agent and the reference
/// implementation of the [Agent] contract.
library;

import 'dart:typed_data';

import 'package:fieldos_mobile/agents/agent.dart';
import 'package:fieldos_mobile/agents/dpr_intake.dart';
import 'package:fieldos_mobile/services/sarvam_service.dart';
import 'package:fieldos_mobile/services/settings_service.dart';

class VoiceDprAgent implements Agent {
  VoiceDprAgent({required this.sarvam, required this.settings});
  final SarvamService sarvam;
  final SettingsService settings;

  @override
  String get name => 'voice_dpr';

  @override
  String get description =>
      'Turn a spoken site report into a structured DPR draft (summary, manpower, weather).';

  @override
  List<AgentTool> get tools => const [
        AgentTool(name: 'transcribe', description: 'Speech-to-text via Sarvam.'),
        AgentTool(name: 'structure', description: 'Summarise transcript into DPR fields.'),
      ];

  /// `input` keys: `audioBytes` (Uint8List), `filename` (String),
  /// `languageCode` (String, optional, default 'unknown').
  @override
  Future<AgentResult> run(Map<String, dynamic> input) async {
    final audio = input['audioBytes'] as Uint8List?;
    final filename = (input['filename'] as String?) ?? 'dpr_voice.m4a';
    if (audio == null || audio.isEmpty) {
      return const AgentResult(ok: false, message: 'No audio provided.');
    }
    final apiKey = await settings.getSarvamApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return const AgentResult(
        ok: false,
        message: 'Voice-to-DPR is not configured. Ask a company owner to add the Sarvam API key in Settings.',
      );
    }
    try {
      final transcript = await sarvam.transcribe(
        audioBytes: audio,
        filename: filename,
        apiKey: apiKey,
        languageCode: (input['languageCode'] as String?) ?? 'unknown',
      );
      final structured = await sarvam.structureDpr(transcript, apiKey);
      final enriched = await DprIntakeAgent().run({
        'transcript': structured.transcript,
        'work_summary': structured.workSummary,
        'manpower_count': structured.manpowerCount,
        'weather': structured.weather,
      });
      return AgentResult(
        ok: true,
        message: 'Drafted DPR from voice.',
        data: {
          'work_summary': structured.workSummary,
          'manpower_count': structured.manpowerCount,
          'weather': structured.weather,
          'transcript': structured.transcript,
          'detected_issues': enriched.data['detected_issues'],
          'delay_flagged': enriched.data['delay_flagged'],
        },
      );
    } on SarvamException catch (e) {
      return AgentResult(ok: false, message: e.toString());
    }
  }
}
