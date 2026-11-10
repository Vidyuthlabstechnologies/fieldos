/// The material check: approved work times the norms against the site's
/// usage, units Indian sites use, and the company's own norms.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/procurement/material_check.dart';

late AppDatabase db;
late Project site;

Future<void> _measure(String description, String unit, double qty, {bool? approve = true, double? approvedQty, int day = 5}) async {
  final m = await db.billingRecordsDao.measure(
      projectId: site.id, description: description, unit: unit, qty: qty, on: DateTime(2026, 11, day), by: 'sup');
  if (approve != null) await db.billingRecordsDao.decide(m.id, approve: approve, approvedQty: approvedQty, by: 'o');
}

var _n = 0;
Future<void> _use(String name, double qty, String unit, {int day = 6}) => db.materialDao.recordUsage(
    MaterialUsageCompanion.insert(
        id: 'u${_n++}',
        projectId: site.id, materialName: name, quantity: qty, unit: Value(unit), recordedBy: 'sup', usedOn: DateTime(2026, 11, day)));

MaterialCheckLine _line(MaterialCheck c, String name) => c.lines.singleWhere((l) => l.name == name);

void main() {
  setUp(() async {
    db = AppDatabase.memory();
    final c = await db.companyDao.create('Sai Constructions');
    site = await db.projectDao.create(ProjectsCompanion.insert(id: 'site-1', companyId: c.id, name: 'Kompally Villas'));
  });
  tearDown(() => db.close());

  test('units Indian sites count in', () {
    expect(baseQty(100, 'cft')!.qty, closeTo(2.832, 0.001));
    expect(baseQty(1, 'Brass')!.unit, 'cum');
    expect(baseQty(1, 'brass')!.qty, closeTo(2.832, 0.001));
    expect(baseQty(1076.39, 'sft')!.qty, closeTo(100, 0.01));
    expect(baseQty(2, 'MT')!.qty, 2000);
    expect(baseQty(3, 'Cu.M')!.unit, 'cum');
    expect(baseQty(1, 'trips'), isNull);
  });

  test('approved work against what was used, with the gaps flagged', () async {
    await _measure('RCC slab, first floor', 'cum', 10); // 80.6 bags, 4.2 sand, 8.4 aggregate
    await _measure('Brickwork 9 inch walls', 'cum', 4, approvedQty: 3.5); // 1750 bricks, 4.375 bags, 0.91 sand
    await _measure('RCC columns', 'cum', 5, approve: false); // rejected: not counted
    await _measure('RCC beams', 'cum', 5, approve: null); // waiting: not counted
    await _measure('Waterproofing', 'sqm', 50); // no norm
    await _use('Cement OPC 53', 100, 'bags');
    await _use('M Sand', 1.8, 'brass'); // 5.1 cum
    await _use('20mm jelly', 8.4, 'cum');
    await _use('Red bricks', 1000, 'nos');
    await _use('Cement', 2, 'kg'); // other units: kept apart

    final c = await loadMaterialCheck(db, site);
    expect(c.checkedWork, 2);
    expect(c.notChecked.map((m) => m.description), ['Waterproofing']);

    final cement = _line(c, 'Cement');
    expect(cement.shouldHaveUsed, closeTo(80.6 + 4.375, 0.001));
    expect(cement.used, 100);
    expect(cement.otherUnits, 2);
    expect(cement.status(c.tolerancePct), CheckStatus.over);

    expect(_line(c, 'Aggregate').status(c.tolerancePct), CheckStatus.ok);
    final bricks = _line(c, 'Bricks');
    expect(bricks.shouldHaveUsed, 1750);
    expect(bricks.status(c.tolerancePct), CheckStatus.under);
    expect(_line(c, 'Sand').used, closeTo(5.097, 0.001));

    // Over first, then under.
    expect(c.lines.first.status(c.tolerancePct), CheckStatus.over);
    expect(c.flagged.map((l) => l.name), containsAll(['Cement', 'Bricks']));
  });

  test('a date range limits both the work and the usage', () async {
    await _measure('RCC footing', 'cum', 10, day: 2);
    await _measure('RCC slab', 'cum', 10, day: 20);
    await _use('Cement', 80.6, 'bag', day: 21);
    final c = await loadMaterialCheck(db, site, from: DateTime(2026, 11, 15), to: DateTime(2026, 11, 30));
    expect(_line(c, 'Cement').shouldHaveUsed, closeTo(80.6, 0.001));
    expect(_line(c, 'Cement').status(c.tolerancePct), CheckStatus.ok);
  });

  test('the company sets its own norms and tolerance, kept per company', () async {
    final mine = MaterialNormSettings(
      norms: [
        for (final n in defaultMaterialNorms)
          n.key == 'rcc' ? n.withMaterials([for (final m in n.materials) m.name == 'Cement' ? m.withPerUnit(9) : m]) : n,
      ],
      tolerancePct: 10,
    );
    await saveMaterialNorms(db, site.companyId, mine);
    final back = await loadMaterialNorms(db, site.companyId);
    expect(back.tolerancePct, 10);
    expect(back.norms.firstWhere((n) => n.key == 'rcc').materials.first.perUnit, 9);
    expect((await loadMaterialNorms(db, 'other-company')).tolerancePct, defaultTolerancePct);
    expect(MaterialNormSettings.fromJson('not json').norms, hasLength(defaultMaterialNorms.length));

    await _measure('RCC slab', 'cum', 10);
    await _use('Cement', 95, 'bags');
    final c = await loadMaterialCheck(db, site);
    expect(_line(c, 'Cement').shouldHaveUsed, 90);
    expect(_line(c, 'Cement').status(c.tolerancePct), CheckStatus.ok); // 5.6% over, under the 10% set
  });

  test('PCC is not read as RCC, and usage of a material no work needed shows as over', () async {
    await _measure('PCC 1:4:8 below footings', 'cum', 10);
    await _use('TMT steel 12mm', 50, 'kg');
    final c = await loadMaterialCheck(db, site);
    expect(_line(c, 'Cement').shouldHaveUsed, closeTo(34, 0.001));
    final steel = _line(c, 'Steel');
    expect(steel.shouldHaveUsed, 0);
    expect(steel.status(c.tolerancePct), CheckStatus.over);
  });
}
