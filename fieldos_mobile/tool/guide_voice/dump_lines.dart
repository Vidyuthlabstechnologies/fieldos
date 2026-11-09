// ignore_for_file: avoid_print
// Prints Mitra's guide lines and voices as JSON, for make_clips.py.
// Run from fieldos_mobile/: dart run tool/guide_voice/dump_lines.dart
import 'dart:convert';

import 'package:fieldos_mobile/features/tour/guide_lines.dart';

void main() => print(jsonEncode({'lines': guideLines, 'voices': guideVoices}));
