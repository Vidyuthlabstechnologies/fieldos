import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/features/commercial/subcontractor_portal.dart';
import 'package:fieldos_mobile/features/auth/login_screen.dart';
import 'package:fieldos_mobile/features/company/company_setup_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/subscription/subscription_gate.dart';
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
    if (session.restoring) return const BrandSplash();
    if (!session.isAuthenticated) return const LoginScreen();
    // Subcontractors use FieldOS free, restricted to their own claims
    // (owner's decision, 10 Nov 2026); everyone else needs a subscription
    // (the 3-day store trial counts) past login.
    if (session.role == Roles.subcontractor && session.activeCompany != null) return const SubcontractorHomeScreen();
    return SubscriptionGate(child: session.needsCompany ? const CompanySetupScreen() : const HomeScreen());
  }
}
