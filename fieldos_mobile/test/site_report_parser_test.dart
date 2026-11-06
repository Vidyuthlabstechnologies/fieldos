import 'package:fieldos_mobile/agents/dpr_intake.dart';
import 'package:fieldos_mobile/agents/site_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractManpower', () {
    final cases = <String, int?>{
      // English
      'Plastering on second floor done with 12 masons and 8 helpers.': 20,
      '20 workers today: 12 masons, 8 helpers': 20,
      'Manpower 25 today': 25,
      'Total manpower 30, slab casting done': 30,
      'twenty five workers came today': 25,
      'a dozen labourers on site': 12,
      'masons 5 helpers 10': 15,
      '10 masons, 5 helpers and 3 other workers': 18,
      'We had 12 workers. The 12 workers finished plastering.': 12,
      '2 floors of brickwork done by 2 masons': 2,
      '50 bags of cement used by 6 masons': 6,
      'Worked 8 hours on the 3rd floor': null,
      'Paid 600 per worker': null,
      'Plastering done': null,
      '20 masonry blocks laid by 4 masons': 4,
      'Rs 600 per labourer': null,
      'రోజుకు 500 కూలీ ఇస్తున్నాం': null,
      // Hindi
      'आज बीस मजदूर आए और पाँच मिस्त्री': 25,
      'आज 15 लोगों ने काम किया': 15,
      '१२ मज़दूर काम पर थे': 12,
      'कुल 40 मजदूर': 40,
      // Telugu
      'ఈరోజు 20 మంది కూలీలు వచ్చారు': 20,
      'పది మంది మేస్త్రీలు, ఇరవై ఐదు మంది కూలీలు': 35,
      'ముగ్గురు మేస్త్రీలు పని చేశారు': 3,
      'మొత్తం 25 మంది వచ్చారు': 25,
      '20మంది పని చేశారు': 20,
      // Hinglish typed in English letters
      'aaj 18 mazdoor aaye': 18,
    };
    for (final c in cases.entries) {
      test(c.key, () => expect(extractManpower(c.key), c.value));
    }
  });

  group('extractWeather', () {
    final cases = <String, String?>{
      'Sunny day, plastering done': 'Sunny',
      'It rained in the afternoon': 'Rain',
      'Heavy rain stopped work at noon': 'Heavy rain',
      'No rain today, very hot': 'Hot',
      'The weather was clear': 'Clear',
      'Cold joint formed in the slab': null,
      'Drain work completed': null,
      'Rainwater harvesting pit dug': null,
      'Site cleared of debris': null,
      'आज बारिश हुई': 'Rain',
      'बारिश नहीं हुई, धूप थी': 'Sunny',
      'ఈరోజు వర్షం పడింది': 'Rain',
      'వర్షం పడలేదు, ఎండగా ఉంది': 'Sunny',
      'మబ్బులు ఉన్నాయి, చినుకులు పడ్డాయి': 'Light rain, cloudy',
      'ఎండిన సిమెంట్ తొలగించాం': null,
    };
    for (final c in cases.entries) {
      test(c.key, () => expect(extractWeather(c.key), c.value));
    }
  });

  group('detectIssues in more languages', () {
    test('a drain is not rain, and related is not late', () {
      expect(detectIssues('Drain work completed'), isEmpty);
      expect(detectIssues('Floodlights installed at the gate'), isEmpty);
      expect(mentionsDelay('Related works completed on time'), isFalse);
    });

    test('negated problems are not raised', () {
      expect(mentionsDelay('There was no delay today'), isFalse);
      expect(detectIssues('No accident today'), isNot(contains('safety concern')));
      expect(detectIssues('The safety meeting was held'), isNot(contains('safety concern')));
    });

    test('Hindi', () {
      expect(detectIssues('सीमेंट नहीं आया'), contains('material shortage'));
      expect(detectIssues('काम में देरी हुई'), contains('schedule delay'));
      expect(mentionsDelay('काम में देरी हुई'), isTrue);
      expect(detectIssues('मिक्सर मशीन खराब हो गई'), contains('equipment breakdown'));
      expect(detectIssues('दीवार में दरार है'), contains('cracks observed'));
    });

    test('Telugu', () {
      expect(detectIssues('ఈరోజు సిమెంట్ అయిపోయింది'), contains('material shortage'));
      expect(detectIssues('గోడలో పగుళ్లు కనిపించాయి'), contains('cracks observed'));
      expect(detectIssues('పని ఆలస్యంగా జరుగుతోంది'), contains('schedule delay'));
      expect(detectIssues('మధ్యాహ్నం కరెంట్ లేదు'), contains('power or water outage'));
      expect(detectIssues('కూలీలు రాలేదు'), contains('labour shortage'));
    });

    test('evidence quotes the words that raised the issue', () {
      final e = detectIssueEvidence('Plastering done. There is a leak near the north wall footing today.');
      expect(e['water ingress'], contains('leak near the north'));
    });

    test('issueLabel capitalises', () => expect(issueLabel('water ingress'), 'Water ingress'));
  });

  group('tidySummary and scripts', () {
    test('English gets a capital and a full stop', () {
      expect(tidySummary('  plastering   done on   2nd floor  '), 'Plastering done on 2nd floor.');
      expect(tidySummary('i checked the shuttering'), 'I checked the shuttering.');
    });

    test('Indian scripts are left as spoken', () {
      expect(tidySummary(' आज प्लास्टर का काम हुआ '), 'आज प्लास्टर का काम हुआ');
      expect(isIndicScript('ఈరోజు 20 మంది'), isTrue);
      expect(isIndicScript('20 workers'), isFalse);
    });
  });
}
