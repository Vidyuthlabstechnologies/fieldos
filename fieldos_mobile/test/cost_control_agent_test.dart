import 'package:decimal/decimal.dart';
import 'package:fieldos_mobile/agents/cost_control_agent.dart';
import 'package:fieldos_mobile/estimation/estimation_calc.dart';
import 'package:flutter_test/flutter_test.dart';

BOQResult _boq() => BOQResult(
      lines: [
        CostHeadLine(
          costHeadId: 'ch1',
          name: 'Earthwork',
          billingUnit: 'cum',
          rawQuantity: Decimal.fromInt(100),
          billingQuantity: Decimal.fromInt(100),
          ratePerUnit: Decimal.fromInt(10),
          amount: Decimal.fromInt(1000),
        ),
        CostHeadLine(
          costHeadId: 'ch2',
          name: 'Concrete',
          billingUnit: 'cum',
          rawQuantity: Decimal.fromInt(500),
          billingQuantity: Decimal.fromInt(500),
          ratePerUnit: Decimal.fromInt(10),
          amount: Decimal.fromInt(5000),
        ),
      ],
      subtotal: Decimal.fromInt(6000),
      contractorProfitAmount: Decimal.zero,
      grandTotal: Decimal.fromInt(6000),
    );

void main() {
  test('flags at_risk and over lines, computes project overrun', () async {
    final agent = CostControlAgent();
    final result = await agent.run({
      'budget': _boq(),
      'actuals': [
        {'costHeadId': 'ch1', 'amount': 950}, // 95% -> at_risk
        {'costHeadId': 'ch2', 'amount': 5500}, // ch2 over
        {'costHeadId': null, 'amount': 200}, // unallocated
      ],
    });

    expect(result.ok, isTrue);
    final lines = result.data['lines'] as List;
    expect(lines[0]['status'], 'at_risk');
    expect(lines[1]['status'], 'over');

    expect(result.data['project_budget'], 6000.0);
    expect(result.data['project_actual'], 6650.0);
    expect(result.data['project_variance'], -650.0);
    expect(result.data['project_status'], 'over');
    expect(result.data['unallocated_actual'], 200.0);

    final alerts = result.data['alerts'] as List;
    expect(alerts.length, 3);
  });

  test('healthy budget yields ok status and no alerts', () async {
    final agent = CostControlAgent();
    final result = await agent.run({
      'budget': _boq(),
      'actuals': [
        {'costHeadId': 'ch1', 'amount': 100},
        {'costHeadId': 'ch2', 'amount': 1000},
      ],
    });

    expect(result.data['project_status'], 'ok');
    expect(result.data['alerts'], isEmpty);
  });

  test('agent metadata is discoverable', () {
    final agent = CostControlAgent();
    expect(agent.name, 'cost_control');
    expect(agent.tools.single.name, 'reconcile');
  });
}
