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

  test('a new project with no priced BOQ is "no budget", not over budget', () async {
    final db = AppDatabase.memory();
    final project = await db.projectDao.create(ProjectsCompanion.insert(
      id: _uuid.v4(),
      companyId: 'c1',
      name: 'Fresh site',
    ));
    await db.expenseDao.create(SiteExpensesCompanion.insert(
      id: _uuid.v4(),
      projectId: project.id,
      category: 'materials',
      amount: 1200,
      incurredOn: '2026-11-01',
      recordedBy: 'u1',
    ));
    final summary = await ProjectCostSummary.forProject(db, project);
    expect(summary.status, 'no_budget');
    expect(summary.actual, 1200);
    expect(summary.alerts, isEmpty);
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

  // Audit 2026-11-14: a site with two estimates (civil at 10% profit, an
  // electrical one at none) had the civil 10% put on the electrical work
  // too, and with two different percentages whichever row came last won.
  test('each estimation profit applies to its own work only', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final project = await db.projectDao.create(ProjectsCompanion.insert(id: _uuid.v4(), companyId: 'c1', name: 'Two BOQs'));
    Future<void> estimate(String name, double? profitPct, double nos) async {
      final est = await db.estimationDao.create(EstimationsCompanion.insert(
          id: _uuid.v4(), projectId: project.id, name: name, createdBy: 'u1', contractorProfitPercent: Value(profitPct)));
      final head = await db.estimationDao.addCostHead(CostHeadsCompanion.insert(
          id: _uuid.v4(),
          estimationId: est.id,
          name: '$name items',
          calculationType: 'count',
          rawUnit: 'nos',
          billingUnit: 'nos',
          ratePerUnit: const Value(1000.0)));
      await db.estimationDao.addMeasurement(MeasurementEntriesCompanion.insert(
          id: _uuid.v4(), costHeadId: head.id, description: name, nos: Value(nos)));
    }

    await estimate('Civil', 10, 100); // 1,00,000 + 10,000 profit
    await estimate('Electrical', null, 50); // 50,000, no profit
    await estimate('Plumbing', 20, 10); // 10,000 + 2,000 profit

    final boq = await buildProjectBoq(db.estimationDao, project.id);
    expect(boq.subtotal, Decimal.fromInt(160000));
    expect(boq.contractorProfitAmount, Decimal.fromInt(12000));
    expect(boq.grandTotal, Decimal.fromInt(172000));
    expect(boq.lines, hasLength(3));
  });
}

