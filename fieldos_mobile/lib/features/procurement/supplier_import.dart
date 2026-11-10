/// Many suppliers at once, pasted from Excel, Tally or WhatsApp, with what
/// the company owed each one on the day it started using FieldOS.
///
/// One supplier per line: "Name, phone, GSTIN, opening balance". Only the
/// name is needed; the rest can come in any order. A 15-character GSTIN is
/// the GSTIN, a number of 10+ digits the phone, an email the email, any
/// other number the opening balance (what you owe them, "Cr" in Tally;
/// "advance", "Dr" or a minus sign for money they hold of yours), and
/// words the category.
library;

import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import 'package:fieldos_mobile/data/app_database.dart';

class NewSupplier {
  const NewSupplier({required this.name, this.phone, this.email, this.gstin, this.category, this.openingBalance});
  final String name;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? category;
  final double? openingBalance;
}

final _gstin = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
// In Tally a supplier's Cr balance is what you owe them, Dr an advance.
final _advance = RegExp(r'\b(adv|advance|dr)\b\.?', caseSensitive: false);

/// Splits one line into its fields. Tabs (a column copied from Excel) win,
/// then semicolons, then commas; with commas, "1,25,000" stays one amount.
List<String> _fields(String line) {
  final List<String> raw;
  if (line.contains('\t')) {
    raw = line.split('\t');
  } else if (line.contains(';')) {
    raw = line.split(';');
  } else {
    raw = [];
    final group = RegExp(r'^\d{2,3}(\.\d+)?(\s*(adv|advance|cr|dr)\.?)?(\s*/-)?$', caseSensitive: false);
    final head = RegExp(r'^-?\s*(₹|rs\.?)?\s*-?\d{1,3}(,\d{2,3})*$', caseSensitive: false);
    for (final p in line.split(',')) {
      final t = p.trim();
      if (raw.isNotEmpty && group.hasMatch(t) && head.hasMatch(raw.last.trim())) {
        raw[raw.length - 1] = '${raw.last.trim()},$t';
      } else {
        raw.add(p);
      }
    }
  }
  return raw.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
}

/// The amount in [p], or null when it isn't one. Advances come back below
/// zero.
double? _amount(String p) {
  final advance = _advance.hasMatch(p) || p.trim().startsWith('-');
  final clean = p
      .replaceAll(_advance, '')
      .replaceAll(RegExp(r'\bcr\b\.?', caseSensitive: false), '')
      .replaceAll(RegExp(r'[₹,\s]|rs\.?|/-', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^-'), '');
  final v = double.tryParse(clean);
  if (v == null) return null;
  return advance ? -v : v;
}

List<NewSupplier> parseSupplierLines(String text) {
  final out = <NewSupplier>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim().replaceFirst(RegExp(r'^(\d+[.)]\s+|[-•*]\s*)'), '');
    if (line.isEmpty) continue;
    final parts = _fields(line);
    if (parts.isEmpty) continue;
    final name = parts.first.replaceAll(RegExp(r'\s+'), ' ');
    if (name.length > 200 || _amount(name) != null) continue;
    String? phone, email, gstin, category;
    double? opening;
    for (final p in parts.skip(1)) {
      final upper = p.toUpperCase().replaceAll(' ', '');
      final digits = p.replaceAll(RegExp(r'[\s+\-()]'), '');
      if (_gstin.hasMatch(upper)) {
        gstin ??= upper;
      } else if (_email.hasMatch(p)) {
        email ??= p;
      } else if (RegExp(r'^\d{10,13}$').hasMatch(digits)) {
        phone ??= p;
      } else if (_amount(p) case final v?) {
        opening ??= v;
      } else {
        category ??= p.length > 100 ? p.substring(0, 100) : p;
      }
    }
    out.add(NewSupplier(
        name: name, phone: phone, email: email, gstin: gstin, category: category, openingBalance: opening));
  }
  return out;
}

class SupplierImportResult {
  const SupplierImportResult({required this.added, required this.skipped});
  final List<Supplier> added;

  /// Names already in the company's supplier list, left as they were.
  final List<String> skipped;
}

/// Adds [rows] to the company's suppliers in one transaction, each queued
/// for sync. A name the company already has (or that comes twice in the
/// list) is skipped, not doubled.
Future<SupplierImportResult> importSuppliers(AppDatabase db, String companyId, List<NewSupplier> rows) {
  return db.transaction(() async {
    final have = {for (final s in await db.supplierDao.forCompany(companyId)) _key(s.name)};
    final added = <Supplier>[];
    final skipped = <String>[];
    for (final r in rows) {
      if (!have.add(_key(r.name))) {
        skipped.add(r.name);
        continue;
      }
      added.add(await db.supplierDao.create(SuppliersCompanion.insert(
        id: const Uuid().v4(),
        companyId: companyId,
        name: r.name,
        contactPhone: Value(r.phone),
        email: Value(r.email),
        gstNumber: Value(r.gstin),
        category: Value(r.category),
        openingBalance: Value(r.openingBalance),
      )));
    }
    return SupplierImportResult(added: added, skipped: skipped);
  });
}

String _key(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
