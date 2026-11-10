/// Material check: what the site should have used for the work approved,
/// against what it says it used. Each kind of work has a norm (cement bags,
/// sand, aggregate, bricks or steel per unit of work); the approved
/// measurements times the norms give "should have used", and the site's
/// usage entries give "used". A big gap is wastage, pilferage or usage not
/// recorded.
///
/// The norms are starting figures for nominal mixes, kept per company on
/// this phone and editable: every builder's mix and wastage differ.
library;

import 'dart:convert';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/warehouse/warehouse_rules.dart' show normMaterial;

String materialNormsKey(String companyId) => 'material_norms:$companyId';

/// One material a unit of work takes.
class NormMaterial {
  const NormMaterial(this.name, this.unit, this.perUnit, {this.aliases = const []});
  final String name;

  /// bag | cum | nos | kg (a base unit, see [baseQty]).
  final String unit;
  final double perUnit;

  /// Other names sites use for it in their usage entries ("jelly" for
  /// aggregate, "TMT" for steel). The name itself always matches.
  final List<String> aliases;

  NormMaterial withPerUnit(double v) => NormMaterial(name, unit, v, aliases: aliases);

  bool matches(String usageName) {
    final n = normMaterial(usageName);
    return [name, ...aliases].any((a) => n.contains(normMaterial(a)));
  }

  Map<String, dynamic> toJson() => {'name': name, 'unit': unit, 'perUnit': perUnit, 'aliases': aliases};
  factory NormMaterial.fromJson(Map<String, dynamic> j) => NormMaterial(
        j['name'] as String,
        j['unit'] as String,
        (j['perUnit'] as num).toDouble(),
        aliases: [for (final a in (j['aliases'] as List? ?? const [])) a as String],
      );
}

/// A kind of work: which measurements it covers and what a unit takes.
class MaterialNorm {
  const MaterialNorm({
    required this.key,
    required this.label,
    required this.keywords,
    required this.workUnit,
    required this.materials,
  });
  final String key;
  final String label;

  /// A measurement is this work when its description has one of these.
  final List<String> keywords;

  /// cum | sqm | kg (base units).
  final String workUnit;
  final List<NormMaterial> materials;

  bool covers(WorkMeasurement m) {
    final base = baseQty(1, m.unit);
    if (base == null || base.unit != workUnit) return false;
    final d = m.description.toLowerCase();
    return keywords.any((k) => d.contains(k));
  }

  MaterialNorm withMaterials(List<NormMaterial> ms) =>
      MaterialNorm(key: key, label: label, keywords: keywords, workUnit: workUnit, materials: ms);

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'keywords': keywords,
        'workUnit': workUnit,
        'materials': [for (final m in materials) m.toJson()],
      };
  factory MaterialNorm.fromJson(Map<String, dynamic> j) => MaterialNorm(
        key: j['key'] as String,
        label: j['label'] as String,
        keywords: [for (final k in j['keywords'] as List) k as String],
        workUnit: j['workUnit'] as String,
        materials: [for (final m in j['materials'] as List) NormMaterial.fromJson(m as Map<String, dynamic>)],
      );
}

const _cement = ['opc', 'ppc'];
const _sand = ['m sand', 'msand', 'p sand'];
const _aggregate = ['jelly', 'metal', 'coarse', 'kankar', '20mm', '40mm', '20 mm', '40 mm'];
const _bricks = ['brick'];
const _steel = ['tmt', 'rebar', 'reinforcement'];

/// Starting figures: nominal mixes, dry volume 1.54 times wet for concrete,
/// a 50 kg cement bag. More specific work comes first: the first norm that
/// covers a measurement is the one used.
const defaultMaterialNorms = [
  MaterialNorm(
    key: 'pcc',
    label: 'PCC 1:4:8',
    keywords: ['pcc', '1:4:8', 'm7.5', 'm10'],
    workUnit: 'cum',
    materials: [
      NormMaterial('Cement', 'bag', 3.4, aliases: _cement),
      NormMaterial('Sand', 'cum', 0.47, aliases: _sand),
      NormMaterial('Aggregate', 'cum', 0.94, aliases: _aggregate),
    ],
  ),
  MaterialNorm(
    key: 'rcc',
    label: 'RCC M20 (1:1.5:3)',
    keywords: ['rcc', 'm20', 'm25', 'concrete', 'slab', 'column', 'beam', 'footing', 'lintel'],
    workUnit: 'cum',
    materials: [
      NormMaterial('Cement', 'bag', 8.06, aliases: _cement),
      NormMaterial('Sand', 'cum', 0.42, aliases: _sand),
      NormMaterial('Aggregate', 'cum', 0.84, aliases: _aggregate),
    ],
  ),
  MaterialNorm(
    key: 'brickwork',
    label: 'Brickwork in 1:6 mortar',
    keywords: ['brick'],
    workUnit: 'cum',
    materials: [
      NormMaterial('Bricks', 'nos', 500, aliases: _bricks),
      NormMaterial('Cement', 'bag', 1.25, aliases: _cement),
      NormMaterial('Sand', 'cum', 0.26, aliases: _sand),
    ],
  ),
  MaterialNorm(
    key: 'plaster',
    label: 'Plastering 12 mm, 1:6',
    keywords: ['plaster'],
    workUnit: 'sqm',
    materials: [
      NormMaterial('Cement', 'bag', 0.065, aliases: _cement),
      NormMaterial('Sand', 'cum', 0.014, aliases: _sand),
    ],
  ),
  MaterialNorm(
    key: 'steel',
    label: 'Reinforcement steel',
    keywords: ['steel', 'reinforcement', 'tmt', 'rebar', 'bar bending'],
    workUnit: 'kg',
    materials: [NormMaterial('Steel', 'kg', 1.0, aliases: _steel)],
  ),
];

/// Above this share over "should have used", a material is flagged.
const defaultTolerancePct = 5.0;

class MaterialNormSettings {
  const MaterialNormSettings({this.norms = defaultMaterialNorms, this.tolerancePct = defaultTolerancePct});
  final List<MaterialNorm> norms;
  final double tolerancePct;

  String toJson() => jsonEncode({'tolerancePct': tolerancePct, 'norms': [for (final n in norms) n.toJson()]});

  /// Broken or missing settings fall back to the starting figures.
  factory MaterialNormSettings.fromJson(String? s) {
    if (s == null || s.isEmpty) return const MaterialNormSettings();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      final norms = [for (final n in j['norms'] as List) MaterialNorm.fromJson(n as Map<String, dynamic>)];
      final tol = (j['tolerancePct'] as num?)?.toDouble() ?? defaultTolerancePct;
      return MaterialNormSettings(norms: norms.isEmpty ? defaultMaterialNorms : norms, tolerancePct: tol.clamp(0, 50));
    } catch (_) {
      return const MaterialNormSettings();
    }
  }
}

Future<MaterialNormSettings> loadMaterialNorms(AppDatabase db, String companyId) async =>
    MaterialNormSettings.fromJson(await db.settingsDao.get(materialNormsKey(companyId)));

Future<void> saveMaterialNorms(AppDatabase db, String companyId, MaterialNormSettings s) =>
    db.settingsDao.set(materialNormsKey(companyId), s.toJson());

/// [qty] of [unit] in a base unit (cum, sqm, kg, bag, nos), or null for a
/// unit not known. Indian sites often count in cft, sft and brass.
({double qty, String unit})? baseQty(double qty, String? unit) {
  final u = (unit ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s.]+'), '');
  return switch (u) {
    'cum' || 'm3' || 'm³' || 'cbm' || 'cubicmetre' || 'cubicmeter' || 'cumt' => (qty: qty, unit: 'cum'),
    'cft' || 'cuft' || 'ft3' || 'cubicfeet' || 'cubicfoot' => (qty: qty / 35.3147, unit: 'cum'),
    'brass' => (qty: qty * 2.83168, unit: 'cum'),
    'sqm' || 'm2' || 'm²' || 'sqmt' || 'squaremetre' || 'squaremeter' => (qty: qty, unit: 'sqm'),
    'sft' || 'sqft' || 'ft2' || 'squarefeet' => (qty: qty / 10.7639, unit: 'sqm'),
    'kg' || 'kgs' || 'kilogram' || 'kilograms' => (qty: qty, unit: 'kg'),
    't' || 'mt' || 'tonne' || 'tonnes' || 'ton' || 'tons' => (qty: qty * 1000, unit: 'kg'),
    'quintal' || 'qtl' => (qty: qty * 100, unit: 'kg'),
    'bag' || 'bags' => (qty: qty, unit: 'bag'),
    'nos' || 'no' || 'number' || 'numbers' || 'pcs' || 'pc' || 'pieces' => (qty: qty, unit: 'nos'),
    _ => null,
  };
}

enum CheckStatus { ok, over, under }

class MaterialCheckLine {
  MaterialCheckLine(this.name, this.unit);
  final String name;
  final String unit;
  double shouldHaveUsed = 0;
  double used = 0;

  /// Usage of this material in a unit that can't be compared (kept apart).
  double otherUnits = 0;

  /// The work that drove [shouldHaveUsed], by norm label.
  final Map<String, double> byWork = {};

  double get gap => used - shouldHaveUsed;
  double? get gapPct => shouldHaveUsed > 0 ? gap / shouldHaveUsed * 100 : null;

  CheckStatus status(double tolerancePct) {
    final p = gapPct;
    if (p == null) return used > 0 ? CheckStatus.over : CheckStatus.ok;
    if (p > tolerancePct) return CheckStatus.over;
    if (p < -tolerancePct) return CheckStatus.under;
    return CheckStatus.ok;
  }
}

class MaterialCheck {
  const MaterialCheck({
    required this.lines,
    required this.tolerancePct,
    required this.checkedWork,
    required this.notChecked,
  });
  final List<MaterialCheckLine> lines;
  final double tolerancePct;

  /// Approved measurements a norm covered.
  final int checkedWork;

  /// Approved measurements no norm covers (other work, or a unit not known).
  final List<WorkMeasurement> notChecked;

  List<MaterialCheckLine> get flagged => [for (final l in lines) if (l.status(tolerancePct) != CheckStatus.ok) l];
}

/// The check over approved measurements and usage entries. Only approved
/// work counts (at the approved quantity); rejected and waiting
/// measurements don't. [from] and [to] (inclusive days) limit both.
MaterialCheck buildMaterialCheck({
  required List<WorkMeasurement> measurements,
  required Map<String, WorkMeasurementDecision> decisions,
  required List<MaterialUsageData> usage,
  MaterialNormSettings settings = const MaterialNormSettings(),
  DateTime? from,
  DateTime? to,
}) {
  bool inRange(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return (from == null || !d.isBefore(DateTime(from.year, from.month, from.day))) &&
        (to == null || !d.isAfter(DateTime(to.year, to.month, to.day)));
  }

  final lines = <String, MaterialCheckLine>{};
  MaterialCheckLine line(NormMaterial m) =>
      lines.putIfAbsent('${normMaterial(m.name)}|${m.unit}', () => MaterialCheckLine(m.name, m.unit));

  var checked = 0;
  final notChecked = <WorkMeasurement>[];
  for (final m in measurements) {
    final d = decisions[m.id];
    if (d == null || d.decision != 'approved' || !inRange(m.measuredOn)) continue;
    final norm = settings.norms.where((n) => n.covers(m)).firstOrNull;
    if (norm == null) {
      notChecked.add(m);
      continue;
    }
    checked++;
    final work = baseQty(d.approvedQty ?? m.qty, m.unit)!.qty;
    for (final nm in norm.materials) {
      final l = line(nm);
      final q = work * nm.perUnit;
      l.shouldHaveUsed += q;
      l.byWork[norm.label] = (l.byWork[norm.label] ?? 0) + q;
    }
  }

  // Every material any norm names, so usage of one the work didn't need
  // still shows as used.
  final known = <String, NormMaterial>{};
  for (final n in settings.norms) {
    for (final m in n.materials) {
      known.putIfAbsent('${normMaterial(m.name)}|${m.unit}', () => m);
    }
  }
  for (final u in usage) {
    if (!inRange(u.usedOn)) continue;
    final candidates = known.values.where((m) => m.matches(u.materialName)).toList();
    if (candidates.isEmpty) continue;
    final b = baseQty(u.quantity, u.unit);
    final same = b == null ? null : candidates.where((m) => m.unit == b.unit).firstOrNull;
    if (same != null) {
      line(same).used += b!.qty;
    } else {
      line(candidates.first).otherUnits += u.quantity;
    }
  }

  // Over first, then under, then fine.
  final out = lines.values.toList()..sort((a, b) {
    int rank(MaterialCheckLine l) => switch (l.status(settings.tolerancePct)) {
          CheckStatus.over => 0,
          CheckStatus.under => 1,
          CheckStatus.ok => 2,
        };
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.compareTo(b.name);
  });
  return MaterialCheck(
      lines: out, tolerancePct: settings.tolerancePct, checkedWork: checked, notChecked: notChecked);
}

Future<MaterialCheck> loadMaterialCheck(AppDatabase db, Project site, {DateTime? from, DateTime? to}) async {
  return buildMaterialCheck(
    measurements: await db.billingRecordsDao.measurementsFor(site.id),
    decisions: await db.billingRecordsDao.decisionsFor(site.id),
    usage: await db.materialDao.usageForProject(site.id),
    settings: await loadMaterialNorms(db, site.companyId),
    from: from,
    to: to,
  );
}
