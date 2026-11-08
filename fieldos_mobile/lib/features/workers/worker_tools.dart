/// Worker list helpers: search and filter, catching the same person added
/// twice, and adding a whole gang at once from a pasted list.
library;

import 'package:fieldos_mobile/data/app_database.dart';

/// The last 10 digits, so "+91 98480 12345", "098480-12345" and
/// "9848012345" are the same phone.
String normalizePhone(String? phone) {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
}

String _normName(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// An existing worker who looks like the one being added: same phone
/// (when one was given), else the same name.
Worker? findDuplicate(Iterable<Worker> existing, {required String name, String? phone}) {
  final p = normalizePhone(phone);
  if (p.length >= 10) {
    for (final w in existing) {
      if (normalizePhone(w.phone) == p) return w;
    }
  }
  final n = _normName(name);
  if (n.isEmpty) return null;
  for (final w in existing) {
    if (_normName(w.name) == n) return w;
  }
  return null;
}

List<Worker> filterWorkers(Iterable<Worker> workers, {String query = '', String? role, bool activeOnly = false}) {
  final q = _normName(query);
  final qPhone = normalizePhone(query);
  return [
    for (final w in workers)
      if ((!activeOnly || w.status == 'active') &&
          (role == null || _normName(w.role ?? '') == _normName(role)) &&
          (q.isEmpty ||
              _normName(w.name).contains(q) ||
              _normName(w.role ?? '').contains(q) ||
              (qPhone.length >= 3 && normalizePhone(w.phone).contains(qPhone))))
        w,
  ];
}

/// Distinct roles in the list, as typed the first time, sorted.
List<String> rolesOf(Iterable<Worker> workers) {
  final seen = <String, String>{};
  for (final w in workers) {
    final r = (w.role ?? '').trim();
    if (r.isNotEmpty) seen.putIfAbsent(_normName(r), () => r);
  }
  return seen.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

class NewWorker {
  const NewWorker({required this.name, this.role, this.phone, this.dailyWage});
  final String name;
  final String? role;
  final String? phone;
  final double? dailyWage;
}

/// One worker per line: "Name, role, phone, wage". Only the name is
/// needed, and the other parts can come in any order: a number of 6+
/// digits is the phone, a smaller number the wage, words the role.
/// Tabs work too, so a column pasted from Excel or WhatsApp is fine.
List<NewWorker> parseWorkerLines(String text) {
  final out = <NewWorker>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim().replaceFirst(RegExp(r'^(\d+[.)]\s+|[-•*]\s*)'), '');
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'[,\t;]')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    String? role;
    String? phone;
    double? wage;
    for (final p in parts.skip(1)) {
      final digits = p.replaceAll(RegExp(r'[\s+\-()]'), '');
      final cleanWage = p.replaceAll(RegExp(r'[₹,\s]|rs\.?|/-|a day|per day', caseSensitive: false), '');
      if (RegExp(r'^\d{6,}$').hasMatch(digits)) {
        phone ??= p;
      } else if (double.tryParse(cleanWage) != null) {
        wage ??= double.parse(cleanWage);
      } else {
        role ??= p;
      }
    }
    final name = parts.first;
    if (name.length > 120) continue;
    out.add(NewWorker(name: name, role: role, phone: phone, dailyWage: wage));
  }
  return out;
}
