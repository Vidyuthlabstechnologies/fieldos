/// Agentic DPR intake: turns a spoken or typed site narrative into a structured
/// DPR *and* surfaces the things a passive daily-report form misses —
/// emerging issues, schedule risk, and the BOQ cost heads the report touches.
///
/// Offline and dependency-free so it can run on every submission without a
/// network round-trip, and be golden-tested deterministically. The voice
/// transcription/structuring still lives in [VoiceDprAgent]; this layer is the
/// "so what" that makes the report agentic rather than a transcription dump.
library;

import 'agent.dart';

/// Curated keyword -> issue phrase map. Extend as the field teams report new
/// failure modes; matching is case-insensitive whole-word/substring.
const _issueKeywords = <String, List<String>>{
  'schedule delay': ['delay', 'behind schedule', 'slower than', 'not started', 'pending approval'],
  'water ingress': ['waterlogging', 'leak', 'leaking', 'seepage', 'damp', 'dampness'],
  'cracks observed': ['crack', 'cracking', 'cracked'],
  'material shortage': ['shortage', 'out of stock', 'not available', 'scarcity', 'supply gap'],
  'safety concern': ['accident', 'injury', 'injured', 'unsafe', 'safety', 'hazard'],
  'quality defect': ['defect', 'rework', 'substandard', 'poor quality', 'not per spec'],
  'labour dispute': ['dispute', 'agitation', 'strike', 'labour issue', 'union'],
  'weather disruption': ['rain', 'waterlogged', 'halted due to weather', 'storm', 'flooded'],
  'drawing deviation': ['deviation', 'not as per drawing', 'changed from drawing', 'variation'],
};

const _delayWords = ['delay', 'late', 'behind', 'pending', 'slow', 'not started', 'behind schedule'];

/// Detect the issues implied by a site narrative.
List<String> detectIssues(String text) {
  final lower = text.toLowerCase();
  final found = <String>[];
  for (final entry in _issueKeywords.entries) {
    for (final kw in entry.value) {
      if (lower.contains(kw)) {
        found.add(entry.key);
        break;
      }
    }
  }
  return found;
}

/// True when the narrative implies the work is off plan / slipping.
bool mentionsDelay(String text) {
  final lower = text.toLowerCase();
  return _delayWords.any(lower.contains);
}

/// Link a narrative to BOQ cost heads whose names appear in it.
List<Map<String, String>> linkCostHeads(
  String text,
  List<Map<String, String>> costHeads,
) {
  final lower = text.toLowerCase();
  final linked = <Map<String, String>>[];
  for (final ch in costHeads) {
    final name = (ch['name'] ?? '').trim();
    if (name.length > 3 && lower.contains(name.toLowerCase())) {
      linked.add({'id': ch['id'] ?? '', 'name': name});
    }
  }
  return linked;
}

class DprIntakeAgent implements Agent {
  const DprIntakeAgent();

  @override
  String get name => 'dpr_intake';

  @override
  String get description =>
      'Enriches a DPR narrative with detected issues, schedule risk, and linked cost heads.';

  @override
  List<AgentTool> get tools => const [
        AgentTool(name: 'detect_issues', description: 'Surface issues from the narrative.'),
        AgentTool(name: 'link_cost_heads', description: 'Associate the report with BOQ lines.'),
      ];

  /// `input` keys:
  ///  - `transcript` (String): the raw narrative.
  ///  - `work_summary`, `manpower_count`, `weather` (optional pre-structured fields).
  ///  - `cost_heads` (optional list of `{id, name}` maps) used for linkage.
  @override
  Future<AgentResult> run(Map<String, dynamic> input) async {
    final transcript = (input['transcript'] as String?) ?? '';
    final costHeads = (input['cost_heads'] as List?)?.cast<Map<String, String>>() ?? const [];

    final issues = detectIssues(transcript);
    final delay = mentionsDelay(transcript);
    final linked = linkCostHeads(transcript, costHeads);

    return AgentResult(
      ok: true,
      message: issues.isEmpty
          ? 'No issues detected in the report.'
          : 'Detected ${issues.length} potential issue(s).',
      data: {
        'transcript': transcript,
        'work_summary': input['work_summary'],
        'manpower_count': input['manpower_count'],
        'weather': input['weather'],
        'detected_issues': issues,
        'delay_flagged': delay,
        'linked_cost_heads': linked,
      },
    );
  }
}
