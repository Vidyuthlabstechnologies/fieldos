import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/app.dart';
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
  runApp(const ProviderScope(child: AppWithMaterial()));
}

class AppWithMaterial extends StatelessWidget {
  const AppWithMaterial({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1B5E20),
        scaffoldBackgroundColor: const Color(0xFFF6F7F6),
      ),
      home: const App(),
    );
  }
}
