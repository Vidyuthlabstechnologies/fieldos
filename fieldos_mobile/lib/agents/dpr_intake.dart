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
import 'site_report_parser.dart';

/// What each issue sounds like, in English, Hindi and Telugu (and the
/// Hinglish people type in English letters). Single words match whole
/// words ("rain" is not in "drain"), a trailing `*` matches the start of a
/// word (Telugu joins endings on: "ఆలస్యం*" also finds "ఆలస్యంగా"), and a
/// negated mention ("no delay", "देरी नहीं") is skipped. Extend as the
/// field teams report new failure modes.
final Map<String, List<Keyword>> _issueKeywords = {
  'schedule delay': keywords([
    'delay*', 'behind schedule', 'slower than', 'not started', 'pending approval', 'work stopped', 'work halted',
    'held up', 'deri', 'der se',
    'देरी', 'देर से', 'देर हो', 'डिले', 'शुरू नहीं', 'काम रुका', 'काम रुक', 'काम बंद', 'पीछे चल',
    'ఆలస్యం*', 'ఆలస్యమ*', 'ఆలస్యంగా*', 'డిలే*', 'మొదలు కాలేదు', 'ప్రారంభం కాలేదు', 'పని ఆగి*', 'ఆగిపోయ*', 'వెనుకబడ*',
  ]),
  'water ingress': keywords([
    'waterlogging', 'leak', 'leaking', 'leakage', 'seepage', 'damp', 'dampness', 'water logging', 'water stagnation',
    'रिसाव', 'लीकेज', 'लीक', 'सीलन', 'पानी भर', 'पानी टपक', 'पानी रिस',
    'లీకేజ్*', 'లీక్*', 'సీపేజ్*', 'కారుతోంది*', 'కారుతున్న*', 'నీరు నిలి*', 'నీళ్లు నిలి*', 'నీరు చేరి*', 'చెమ్మ*',
  ]),
  'cracks observed': keywords([
    'crack*', 'दरार', 'दरारें', 'दरारे', 'क्रैक', 'పగుళ్ల*', 'పగులు*', 'పగిలి*', 'క్రాక్*', 'బీటలు*', 'బీట*', 'చీలి*',
  ]),
  'material shortage': keywords([
    'shortage', 'out of stock', 'not available', 'scarcity', 'supply gap', 'ran out', 'run out', 'running out',
    'not delivered', 'material not', 'cement not', 'sand not', 'steel not',
    'कमी', 'खत्म हो', 'नहीं आया', 'नहीं आई', 'नहीं पहुंचा', 'नहीं पहुंची', 'नहीं मिला', 'नहीं मिली', 'उपलब्ध नहीं',
    'शॉर्टेज', 'स्टॉक खत्म',
    'కొరత*', 'అయిపోయ*', 'షార్టేజ్*', 'అందుబాటులో లేదు', 'స్టాక్ లేదు', 'మెటీరియల్ రాలేదు', 'సిమెంట్ రాలేదు',
    'ఇసుక రాలేదు', 'స్టీల్ రాలేదు', 'ఇటుకలు రాలేదు', 'సరుకు రాలేదు',
  ]),
  'labour shortage': keywords([
    'labour shortage', 'labor shortage', 'less labour', 'less labor', 'short of labour', 'workers absent',
    'did not turn up', 'didn t turn up', 'no show', 'absent',
    'मजदूर नहीं आए', 'मजदूर कम', 'लेबर कम', 'लेबर नहीं', 'लेबर की कमी', 'मजदूरों की कमी',
    'కూలీలు రాలేదు', 'కూలీలు తక్కువ', 'లేబర్ తక్కువ', 'లేబర్ రాలేదు', 'మనుషులు తక్కువ', 'పనివాళ్లు రాలేదు',
  ]),
  'safety concern': keywords([
    'accident', 'injury', 'injured', 'unsafe', 'hazard*', 'near miss', 'no helmet', 'without helmet', 'fell down',
    'fell from', 'safety issue', 'safety concern', 'safety violation', 'without safety', 'no safety',
    'दुर्घटना', 'हादसा', 'चोट', 'घायल', 'गिर गया', 'गिर गई', 'खतरा', 'सेफ्टी नहीं', 'हेलमेट नहीं',
    'ప్రమాదం*', 'ప్రమాద*', 'గాయం*', 'గాయప*', 'గాయాల*', 'గాయమ*', 'దెబ్బ తగిలి*', 'పడిపోయ*', 'హెల్మెట్ లేదు', 'సేఫ్టీ లేదు', 'సేఫ్టీ లేకుండా',
  ]),
  'quality defect': keywords([
    'defect*', 'rework', 'substandard', 'poor quality', 'bad quality', 'low quality', 'not per spec',
    'not as per spec', 'honeycomb*', 'out of plumb', 'not in level', 'uneven',
    'घटिया', 'क्वालिटी खराब', 'खराब क्वालिटी', 'काम खराब', 'खराब काम', 'माल खराब', 'दोबारा करना', 'फिर से करना',
    'నాసిరకం*', 'నాణ్యత లేదు', 'నాణ్యత తక్కువ', 'క్వాలిటీ లేదు', 'రీవర్క్*', 'మళ్ళీ చేయాలి', 'మళ్లీ చేయాలి', 'లోపం*', 'లోపాలు*',
  ]),
  'equipment breakdown': keywords([
    'breakdown', 'broke down', 'broken down', 'not working', 'out of order', 'machine failure', 'engine failure',
    'under repair', 'puncture*',
    'मशीन खराब', 'मिक्सर खराब', 'जेसीबी खराब', 'पंप खराब', 'वाइब्रेटर खराब', 'जनरेटर खराब', 'खराब हो गई', 'खराब हो गया',
    'चल नहीं रहा', 'चल नहीं रही', 'रिपेयर',
    'పాడైపోయ*', 'పాడైంది*', 'రిపేర్*', 'పనిచేయడం లేదు', 'పని చేయడం లేదు', 'బ్రేక్డౌన్*', 'మిషన్ ఆగి*', 'మిషన్ పాడై*',
  ]),
  'labour dispute': keywords([
    'dispute', 'agitation', 'strike', 'union', 'protest', 'quarrel', 'fight',
    'हडताल', 'झगडा', 'विवाद', 'धरना',
    'సమ్మె*', 'గొడవ*', 'వివాదం*', 'ఆందోళన*', 'ధర్నా*',
  ]),
  'weather disruption': keywords([
    'heavy rain', 'heavy rains', 'storm', 'flood', 'flooding', 'flooded', 'waterlogged', 'halted due to weather',
    'stopped due to rain', 'due to rain', 'because of rain', 'rain stopped', 'cyclone',
    'बारिश की वजह', 'बारिश के कारण', 'बारिश से काम', 'बारिश की वजह से', 'तूफान', 'बाढ', 'तेज बारिश', 'भारी बारिश',
    'వర్షం వల్ల', 'వర్షం కారణంగా', 'వర్షంతో పని*', 'వర్షం కారణం*', 'భారీ వర్షం*', 'తుఫాను*', 'తుపాను*', 'వరద*',
  ]),
  'drawing deviation': keywords([
    'deviation', 'not as per drawing', 'changed from drawing', 'variation', 'drawing mismatch', 'drawing issue',
    'drawing not',
    'ड्राइंग के अनुसार नहीं', 'ड्राइंग में बदलाव', 'ड्राइंग नहीं', 'डिविएशन',
    'డ్రాయింగ్ ప్రకారం లేదు', 'డ్రాయింగ్ మార్పు*', 'డ్రాయింగ్ రాలేదు', 'డీవియేషన్*',
  ]),
  'payment issue': keywords([
    'payment pending', 'payment not', 'not paid', 'unpaid', 'wages pending', 'wages not', 'advance not',
    'पेमेंट नहीं', 'पेमेंट बाकी', 'पैसा नहीं', 'पैसे नहीं', 'भुगतान नहीं', 'मजदूरी नहीं',
    'పేమెంట్ రాలేదు', 'పేమెంట్ పెండింగ్', 'డబ్బులు రాలేదు', 'డబ్బు రాలేదు', 'జీతం రాలేదు', 'కూలీ డబ్బులు రాలేదు',
  ]),
  'power or water outage': keywords([
    'power cut', 'no power', 'power failure', 'no electricity', 'power outage', 'no water supply',
    'बिजली नहीं', 'बिजली गई', 'बिजली चली', 'लाइट नहीं', 'पावर कट', 'पानी नहीं',
    'కరెంట్ లేదు', 'కరెంటు లేదు', 'కరెంట్ పోయ*', 'కరెంటు పోయ*', 'పవర్ కట్*', 'నీళ్లు లేవు', 'నీరు లేదు',
  ]),
};

/// Phrases that are themselves negative ("not started", "नहीं आया") and so
/// are never cancelled by a nearby "not".
bool _carriesNegation(Keyword k) => k.parts.any(isNegationWord);

final _delayKeywords = keywords([
  'delay*', 'late', 'behind', 'pending', 'slow', 'slowly', 'slower', 'not started', 'behind schedule', 'deri',
  'देरी', 'देर', 'लेट', 'डिले', 'पीछे', 'धीमा', 'धीमी', 'शुरू नहीं', 'रुका', 'रुकी',
  'ఆలస్యం*', 'ఆలస్యమ*', 'లేట్*', 'డిలే*', 'నెమ్మది*', 'వెనుకబడ*', 'మొదలు కాలేదు', 'పెండింగ్*',
]);

/// Detect the issues implied by a site narrative, in any of the languages
/// above. Issue names stay in English so they print on the PDF report.
List<String> detectIssues(String text) => detectIssueEvidence(text).keys.toList();

/// Like [detectIssues], with the words that raised each issue (as written),
/// so a new issue can say what was reported.
Map<String, String> detectIssueEvidence(String text) {
  final tokens = tokenizeReport(text);
  final clean = stripJoiners(text);
  final found = <String, String>{};
  for (final entry in _issueKeywords.entries) {
    for (var i = 0; i < tokens.length && !found.containsKey(entry.key); i++) {
      for (final kw in entry.value) {
        if (!kw.matchesAt(tokens, i)) continue;
        if (!_carriesNegation(kw) && isNegated(tokens, i, kw.parts.length)) continue;
        found[entry.key] = _quote(clean, tokens, i, kw.parts.length);
        break;
      }
    }
  }
  return found;
}

/// The words around a match, about a short sentence's worth.
String _quote(String text, List<ReportToken> t, int i, int len) {
  final from = (i - 4).clamp(0, t.length - 1);
  final to = (i + len + 3).clamp(0, t.length - 1);
  return text.substring(t[from].start, t[to].end).replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True when the narrative implies the work is off plan / slipping.
bool mentionsDelay(String text) {
  final tokens = tokenizeReport(text);
  for (var i = 0; i < tokens.length; i++) {
    for (final kw in _delayKeywords) {
      if (kw.matchesAt(tokens, i) && (_carriesNegation(kw) || !isNegated(tokens, i, kw.parts.length))) return true;
    }
  }
  return false;
}

/// The issue name as a person would write it: "Water ingress".
String issueLabel(String key) => key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';

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
