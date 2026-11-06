import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/app.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';

void main() {
  // Keep the last few errors so a bug report can carry them.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    RecentErrors.record(details.exception, details.stack);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    RecentErrors.record(error, stack);
    return false;
  };
  // The brand font's licence, listed with the packages' licences.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Inter (font)'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  runApp(const ProviderScope(child: AppWithMaterial()));
}

class AppWithMaterial extends ConsumerWidget {
  const AppWithMaterial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return MaterialApp(
      title: 'FieldOS',
      // Date pickers, dialogs' OK/Cancel and the like in the same language.
      locale: language.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: buildFieldOsTheme(Brightness.light),
      darkTheme: buildFieldOsTheme(Brightness.dark),
      home: const App(),
    );
  }
}
