import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/release_config.dart';
import 'package:fieldos_mobile/features/subscription/paywall_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

export 'package:fieldos_mobile/features/subscription/paywall_screen.dart';

/// Shows [child] only while this person has a subscription (the 3-day
/// trial counts) or their company has a company plan (sold by invoice, see
/// lib/services/company_plan.dart). Otherwise shows the paywall. Checked on open, every time
/// the app comes back to the foreground, and whenever the store reports a
/// change (a payment that was waiting for approval going through).
class SubscriptionGate extends ConsumerStatefulWidget {
  const SubscriptionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends ConsumerState<SubscriptionGate> with WidgetsBindingObserver {
  Access? _access;
  VoidCallback? _stopListening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!ref.read(billingServiceProvider).setUp) {
      // Development build. A store build without billing never gets here
      // (main.dart shows BrokenBuildApp), and locks if it did.
      _access = storeRelease ? Access.blocked : Access.allowed;
      // Still learn the company plan, for its site limit.
      ref.read(companyPlanServiceProvider).current().catchError((_) => null);
    } else {
      _check(firstTime: true);
      _listen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListening?.call();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _listen() async {
    try {
      final stop = await ref.read(billingServiceProvider).listen((s) {
        if (mounted && s.active && _access != Access.allowed) _set(Access.allowed);
      });
      if (mounted) {
        _stopListening = stop;
      } else {
        stop();
      }
    } catch (_) {
      // The store can't be reached; the checks on open and resume still run.
    }
  }

  void _set(Access access) {
    final wasAllowed = _access == Access.allowed;
    setState(() => _access = access);
    // A subscription that ended while a project was open: bring the person
    // back to the paywall instead of leaving the open screens usable.
    if (wasAllowed && access == Access.blocked) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _check({bool firstTime = false}) async {
    final billing = ref.read(billingServiceProvider);
    final company = ref.read(companyPlanServiceProvider);
    if (!billing.setUp) return;
    // Open straight away for someone who was paid up (or covered by their
    // company) last time, and let the answers catch up in the background.
    if (firstTime && mounted) {
      final now = DateTime.now();
      final remembered = accessFor(
                    billingSetUp: true, live: null, lastPaidUntil: await billing.lastPaidUntil(), now: now) ==
                Access.allowed ||
            await company.access(live: null, now: now) == Access.allowed;
      if (remembered && mounted) _set(Access.allowed);
    }
    // Both asked every time: the company plan's site limit is needed even
    // by someone who also pays in the store.
    final results = await Future.wait<Object?>([billing.current(), company.current()]);
    final now = DateTime.now();
    final store = accessFor(
        billingSetUp: true,
        live: results[0] as SubscriptionState?,
        lastPaidUntil: await billing.lastPaidUntil(),
        now: now);
    final access = store == Access.allowed
        ? Access.allowed
        : await company.access(live: results[1] as List<CompanyPlan>?, now: now);
    if (mounted && access != _access) _set(access);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_access) {
      null => const BrandSplash(),
      Access.allowed => widget.child,
      Access.blocked => PaywallScreen(onUnlocked: () => _set(Access.allowed), onCompanyLinked: _check),
    };
  }
}
