import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/app.dart';
import 'package:fieldos_mobile/core/theme.dart';
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

class AppWithMaterial extends StatelessWidget {
  const AppWithMaterial({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldOS',
      debugShowCheckedModeBanner: false,
      theme: buildFieldOsTheme(Brightness.light),
      darkTheme: buildFieldOsTheme(Brightness.dark),
      home: const App(),
    );
  }
}
