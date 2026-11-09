import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/subscription/subscription_gate.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/language_welcome.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Root widget: routes to the right screen based on session state, and
/// keeps cloud sync running for a linked company (on login/launch, company
/// switch, and every return to the foreground).
class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.read(bugReportServiceProvider).flush().catchError((_) => 0);
    Future.microtask(() => ref.read(reminderSchedulerProvider).refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(cloudSyncBootstrapProvider).onResume().catchError((_) {});
      ref.read(bugReportServiceProvider).flush().catchError((_) => 0);
      ref.read(reminderSchedulerProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionProvider, (prev, next) {
      if (next.activeCompany != null && next.activeCompany?.id != prev?.activeCompany?.id) {
        ref.read(cloudSyncBootstrapProvider).ensureRunning().catchError((_) {});
      }
      if (next.activeCompany?.id != prev?.activeCompany?.id) ref.read(reminderSchedulerProvider).refresh();
    });
    final session = ref.watch(sessionProvider);
    // First launch: ask which language the person speaks before anything else.
    final languageChosen = ref.watch(languageChosenProvider);
    if (session.restoring || languageChosen.isLoading) return const BrandSplash();
    if (languageChosen.value == false) return const LanguageWelcomeScreen();
    if (!session.isAuthenticated) return const LoginScreen();
    // Everyone needs a subscription (the 3-day store trial counts) past login.
    return SubscriptionGate(child: session.needsCompany ? const CompanySetupScreen() : const HomeScreen());
  }
}
