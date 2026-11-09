/// The site's notebook: what was agreed with the client, sizes to check,
/// numbers to call. Onsite's reviews ask for "a notes section in each
/// project" and "notepad for site". Notes sync to the whole site team.
library;

import 'package:fieldos_mobile/data/app_database.dart';

/// The first line, which the list shows bold.
String noteTitle(String body) {
  final first = body.trim().split('\n').first.trim();
  return first.length > 80 ? '${first.substring(0, 79)}…' : first;
}

/// Everything after the first line, for the list's second line.
String? noteRest(String body) {
  final lines = body.trim().split('\n');
  if (lines.length < 2) return null;
  final rest = lines.skip(1).map((l) => l.trim()).where((l) => l.isNotEmpty).join(' ');
  return rest.isEmpty ? null : rest;
}

/// Notes whose words hold every word of [query], in any case.
List<ProjectNote> searchNotes(List<ProjectNote> notes, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return notes;
  return [
    for (final n in notes)
      if (words.every(n.body.toLowerCase().contains)) n,
  ];
}

/// Who may change or remove a note: whoever wrote it, an owner or a PM.
bool canChangeNote(ProjectNote n, {required String userId, required bool isManager}) =>
    isManager || n.createdBy == userId;

/// A note as text to send on WhatsApp.
String noteShareText(ProjectNote n, {String? siteName}) =>
    [if (siteName != null && siteName.isNotEmpty) siteName, n.body.trim()].join('\n');
