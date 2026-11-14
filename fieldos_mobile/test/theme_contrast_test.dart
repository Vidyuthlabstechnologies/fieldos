// Text must stay readable in sunlight and at night: every text colour the
// theme hands out is checked against the surfaces it sits on, in both the
// light and the dark theme, to WCAG AA (4.5:1 for body text).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    test('text contrast, ${brightness.name} theme', () {
      final t = buildFieldOsTheme(brightness);
      final s = t.colorScheme;
      final surfaces = <String, Color>{
        'scaffold': t.scaffoldBackgroundColor,
        'surface': s.surface,
        'card': t.cardTheme.color!,
        'input': t.inputDecorationTheme.fillColor!,
        'surfaceContainerLow': s.surfaceContainerLow,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHigh': s.surfaceContainerHigh,
        'surfaceContainerHighest': s.surfaceContainerHighest,
      };
      final failures = <String>[];
      void check(String name, Color fg, Color bg, [double min = 4.5]) {
        final r = _contrast(fg, bg);
        if (r < min) failures.add('$name ${r.toStringAsFixed(2)}');
      }

      for (final e in surfaces.entries) {
        check('onSurface on ${e.key}', s.onSurface, e.value);
        check('onSurfaceVariant on ${e.key}', s.onSurfaceVariant, e.value);
        check('primary on ${e.key}', s.primary, e.value);
        check('error on ${e.key}', s.error, e.value);
      }
      check('onPrimary on primary', s.onPrimary, s.primary);
      check('onSecondary on secondary', s.onSecondary, s.secondary);
      check('onPrimaryContainer', s.onPrimaryContainer, s.primaryContainer);
      check('onSecondaryContainer', s.onSecondaryContainer, s.secondaryContainer);
      check('onErrorContainer', s.onErrorContainer, s.errorContainer);
      check('app bar title', t.appBarTheme.foregroundColor!, t.appBarTheme.backgroundColor!);
      check('snack bar text', Colors.white, t.snackBarTheme.backgroundColor!);
      check('snack bar action', t.snackBarTheme.actionTextColor!, t.snackBarTheme.backgroundColor!);
      check('FAB', t.floatingActionButtonTheme.foregroundColor!, t.floatingActionButtonTheme.backgroundColor!);
      if (brightness == Brightness.light) {
        // Status words (paid, late, overdue) on the page and on their soft pills.
        for (final (n, fg, bg) in [
          ('ok', Brand.ok, Brand.okSoft),
          ('warn', Brand.warn, Brand.warnSoft),
          ('danger', Brand.danger, Brand.dangerSoft),
        ]) {
          check('$n on paper', fg, Brand.paper);
          check('$n on its pill', fg, bg);
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  }
}
