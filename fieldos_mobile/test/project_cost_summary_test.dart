import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/estimation/project_boq.dart';
import 'package:fieldos_mobile/features/dashboard/project_cost_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

void main() {
  test('full pipeline: estimation -> BOQ -> actuals -> dashboard summary', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'Demo Tower',
      status: const Value('planning'),
    ));
    final est = await db.estimationDao.create(EstimationsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'BOQ 1',
      createdBy: 'u1',
      status: const Value('draft'),
    ));
    final head = await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
      id: _uuid.v4(),
      estimationId: est.id,
      name: 'Earthwork',
      calculationType: 'volume',
      rawUnit: 'ft',
      billingUnit: 'cum',
      conversionFactor: const Value(1.0),
      ratePerUnit: const Value(100.0),
    ));
    await db.estimationDao.addMeasurement(MeasurementEntriesCompanion.insert(
      id: _uuid.v4(),
      costHeadId: head.id,
      description: 'test pit',
      length: const Value(10.0),
      width: const Value(10.0),
      depth: const Value(10.0),
      nos: const Value(1.0),
    ));

    // 10*10*10 = 1000 cft -> ~28.3168 cum * 100 = ~2831.68 budget.
    final boq = await buildProjectBoq(db.estimationDao, project.id);
    expect(boq.grandTotal, greaterThan(Decimal.fromInt(2800)));

    await db.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      costHeadId: const Value(null),
      category: 'materials',
      amount: 500.0,
      incurredOn: '2026-01-01',
      recordedBy: 'u1',
    ));

    final summary = await ProjectCostSummary.forProject(db, project);
    expect(summary.budget, greaterThan(2800));
    expect(summary.actual, 500.0);
    expect(summary.status, 'ok');
    expect(summary.openIssues, 0);
    expect(summary.dprCount, 0);
  });

  test('overrun flips the dashboard status to over', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'Demo Tower',
      status: const Value('planning'),
    ));
    final est = await db.estimationDao.create(EstimationsCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      name: 'BOQ 1',
      createdBy: 'u1',
      status: const Value('draft'),
    ));
    final head = await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
      id: _uuid.v4(),
      estimationId: est.id,
      name: 'Earthwork',
      calculationType: 'volume',
      rawUnit: 'ft',
      billingUnit: 'cum',
      conversionFactor: const Value(1.0),
      ratePerUnit: const Value(1.0),
    ));
    await db.estimationDao.addMeasurement(MeasurementEntriesCompanion.insert(
      id: _uuid.v4(),
      costHeadId: head.id,
      description: 'test pit',
      length: const Value(10.0),
      width: const Value(10.0),
      depth: const Value(10.0),
      nos: const Value(1.0),
    ));

    final summaryBefore = await ProjectCostSummary.forProject(db, project);
    expect(summaryBefore.budget, greaterThan(20));

    await db.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      costHeadId: const Value(null),
      category: 'materials',
      amount: 1e6,
      incurredOn: '2026-01-01',
      recordedBy: 'u1',
    ));

    final summary = await ProjectCostSummary.forProject(db, project);
    expect(summary.actual, 1e6);
    expect(summary.status, 'over');
  });
}

