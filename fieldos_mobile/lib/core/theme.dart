/// FieldOS's look: navy app bars, an amber main action, Inter type, roomy
/// touch targets for gloved or dusty hands, and a dark theme for night shifts.
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'package:fieldos_mobile/core/brand.dart';

ThemeData buildFieldOsTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.navy,
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFFA9C4EC) : Brand.navy,
    onPrimary: dark ? Brand.navyDeep : Colors.white,
    primaryContainer: dark ? Brand.navySoft : const Color(0xFFDCE7F7),
    onPrimaryContainer: dark ? Colors.white : Brand.navyDeep,
    secondary: Brand.amber,
    onSecondary: Brand.navyDeep,
    secondaryContainer: dark ? const Color(0xFF5A3D05) : Brand.amberSoft,
    onSecondaryContainer: dark ? Brand.amberSoft : const Color(0xFF4A3000),
    error: dark ? const Color(0xFFF0A08F) : Brand.danger,
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF3B231D) : Brand.dangerSoft,
    onErrorContainer: dark ? const Color(0xFFF6CFC5) : const Color(0xFF6E2618),
    tertiary: dark ? const Color(0xFF9CC9AE) : Brand.ok,
    surface: dark ? const Color(0xFF0F1B2D) : Colors.white,
    onSurface: dark ? const Color(0xFFE6ECF4) : Brand.ink,
    onSurfaceVariant: dark ? const Color(0xFFB4C0D0) : Brand.inkMuted,
    outline: dark ? const Color(0xFF55657B) : const Color(0xFFB9C3D0),
    outlineVariant: dark ? const Color(0xFF2A3A52) : Brand.line,
    surfaceContainerLowest: dark ? const Color(0xFF0A1424) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xFF132238) : const Color(0xFFF8FAFC),
    surfaceContainer: dark ? const Color(0xFF17283F) : const Color(0xFFF1F4F8),
    surfaceContainerHigh: dark ? const Color(0xFF1C2F49) : const Color(0xFFEBEFF5),
    surfaceContainerHighest: dark ? const Color(0xFF223754) : const Color(0xFFE4E9F0),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: Brand.fontFamily,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    // A plain ripple: Material 3's sparkle reads as a gimmick on a work tool.
    splashFactory: InkRipple.splashFactory,
  );

  final text = base.textTheme.copyWith(
    headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
    titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0),
    labelMedium: base.textTheme.labelMedium?.copyWith(letterSpacing: 0.1),
    labelSmall: base.textTheme.labelSmall?.copyWith(letterSpacing: 0.1),
    // Material's default tracking (0.25-0.5) is set for Roboto; on Inter it
    // spreads every line apart and reads machine-made. Inter is drawn to sit
    // at 0.
    bodyLarge: base.textTheme.bodyLarge?.copyWith(letterSpacing: 0, height: 1.45),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(letterSpacing: 0, height: 1.45),
    bodySmall: base.textTheme.bodySmall?.copyWith(letterSpacing: 0, height: 1.4),
  );

  final radius12 = BorderRadius.circular(12);
  final appBarBg = dark ? const Color(0xFF0B1626) : Brand.navy;

  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0A1424) : Brand.paper,
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: appBarBg,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // No shadow pops in when a list scrolls under the bar.
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontFamily: Brand.fontFamily,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        letterSpacing: -0.2,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
    ),
    // Tab bars that sit on the page (the Money and Procurement sub-tabs).
    // The project screen's tabs sit on the navy app bar and set their own.
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: Brand.amber,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
      labelStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w500, fontSize: 14),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Brand.amber,
      foregroundColor: Brand.navyDeep,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w700, fontSize: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        side: BorderSide(color: scheme.outline),
        textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        shape: RoundedRectangleBorder(borderRadius: radius12),
        textStyle: const TextStyle(fontFamily: Brand.fontFamily, fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF132238) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.error, width: 2)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF132238) : Colors.white,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      // A colour is required here: without one the label inherits white
      // and vanishes on the light chips (it did, on every filter chip row).
      labelStyle: TextStyle(
          fontFamily: Brand.fontFamily, fontWeight: FontWeight.w500, fontSize: 13, color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(
          fontFamily: Brand.fontFamily, fontWeight: FontWeight.w600, fontSize: 13, color: scheme.onSecondaryContainer),
      selectedColor: scheme.secondaryContainer,
      checkmarkColor: scheme.onSecondaryContainer,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF132238) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        fontFamily: Brand.fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? const Color(0xFF132238) : Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF223754) : Brand.navyDeep,
      contentTextStyle: const TextStyle(fontFamily: Brand.fontFamily, color: Colors.white, fontSize: 14),
      actionTextColor: Brand.amber,
      shape: RoundedRectangleBorder(borderRadius: radius12),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      surfaceTintColor: Colors.transparent,
      color: dark ? const Color(0xFF17283F) : Colors.white,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: dark ? Brand.amber : Brand.navy,
      linearTrackColor: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(3),
    ),
    // One calm motion everywhere: the next page fades and slides in a
    // little, the way Android's own screens move; iOS keeps its swipe.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius12)),
      ),
    ),
  );
}
