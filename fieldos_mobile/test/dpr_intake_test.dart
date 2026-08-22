import 'package:fieldos_mobile/agents/dpr_intake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detectIssues maps keywords to curated issue phrases', () {
    final issues = detectIssues('There is a leak and some cracking in the wall, plus a material shortage.');
    expect(issues, contains('water ingress'));
    expect(issues, contains('cracks observed'));
    expect(issues, contains('material shortage'));
  });

  test('mentionsDelay catches schedule slippage language', () {
    expect(mentionsDelay('The slab is behind schedule due to rain.'), isTrue);
    expect(mentionsDelay('Foundation work completed as planned.'), isFalse);
  });

  test('linkCostHeads associates narrative with BOQ lines', () {
    final linked = linkCostHeads(
      'Poured concrete for the foundation and did earthwork.',
      [
        {'id': 'ch1', 'name': 'Concrete'},
        {'id': 'ch2', 'name': 'Earthwork'},
        {'id': 'ch3', 'name': 'Steel'},
      ],
    );
    expect(linked.map((l) => l['id']), containsAll(['ch1', 'ch2']));
    expect(linked.map((l) => l['id']), isNot(contains('ch3')));
  });

  test('DprIntakeAgent enriches a transcript end to end', () async {
    final result = await DprIntakeAgent().run({
      'transcript': 'Work is behind schedule and we found waterlogging near the footing.',
      'work_summary': 'Footing excavation',
      'cost_heads': [
        {'id': 'ch1', 'name': 'Earthwork'},
      ],
    });
    expect(result.ok, isTrue);
    expect(result.data['detected_issues'], contains('water ingress'));
    expect(result.data['delay_flagged'], isTrue);
    expect(result.data['work_summary'], 'Footing excavation');
  });
}
