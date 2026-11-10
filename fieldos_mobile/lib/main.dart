import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/app.dart';
import 'package:fieldos_mobile/core/release_config.dart';
import 'package:fieldos_mobile/core/text_size.dart';
import 'package:fieldos_mobile/core/theme.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/services/billing_service.dart' show BillingConfig;
import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/services/notification_service.dart' show appNavigatorKey;
import 'package:fieldos_mobile/sync/sync_config.dart';

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
  final problems =
      storeRelease ? storeReleaseProblems(cloud: SyncConfig.production, billingKey: BillingConfig.keyForThisDevice) : const <String>[];
  if (problems.isNotEmpty) {
    runApp(BrokenBuildApp(problems: problems));
    return;
  }
  runApp(const ProviderScope(retry: noProviderRetry, child: AppWithMaterial()));
}

/// Shown instead of FieldOS by a store build that is missing its cloud or
/// payment setup (see release_config.dart): never run such a copy offline
/// only, or with everything free. English only on purpose: it is for the
/// FieldOS team, and should never reach a customer.
class BrokenBuildApp extends StatelessWidget {
  const BrokenBuildApp({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
              const Text('This copy of FieldOS was built without its setup',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('Please install FieldOS again from the Play Store or App Store. '
                  'If it keeps happening, write to info@mldynamic.com.'),
              const SizedBox(height: 16),
              for (final p in problems) Text('• $p', style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      );
}

/// Riverpod 3 retries a failed provider on its own, with backoff. FieldOS
/// screens already show the error with a way to try again, and a silent
/// retry would repeat paid or rate-limited calls (store plans, cloud), so
/// a failure stays a failure until the person or the code asks again.
Duration? noProviderRetry(int retryCount, Object error) => null;

class AppWithMaterial extends ConsumerWidget {
  const AppWithMaterial({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    return MaterialApp(
      title: 'FieldOS',
      navigatorKey: appNavigatorKey,
      // Date pickers, dialogs' OK/Cancel and the like in the same language.
      locale: language.locale,
      supportedLocales: [for (final l in AppLanguage.values) l.locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final size = ref.watch(textSizeProvider);
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: combinedTextScaler(media.textScaler, size)),
          child: SystemNavBarSafeArea(child: AppLockGate(child: child ?? const SizedBox.shrink())),
        );
      },
      debugShowCheckedModeBanner: false,
      theme: buildFieldOsTheme(Brightness.light),
      darkTheme: buildFieldOsTheme(Brightness.dark),
      home: const App(),
    );
  }
}
