import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/features/subscription/paywall_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';

export 'package:fieldos_mobile/features/subscription/paywall_screen.dart';

/// Shows [child] only while this person has a subscription (the 3-day
/// trial counts). Otherwise shows the paywall. Checked on open, every time
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
      _access = Access.allowed; // development build, or payments not configured yet
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
    if (!billing.setUp) return;
    final paidUntil = await billing.lastPaidUntil();
    // Open straight away for someone who was paid up last time, and let
    // the store's answer catch up in the background.
    if (firstTime && mounted) {
      final remembered = accessFor(billingSetUp: true, live: null, lastPaidUntil: paidUntil, now: DateTime.now());
      if (remembered == Access.allowed) _set(Access.allowed);
    }
    final live = await billing.current();
    final access =
        accessFor(billingSetUp: true, live: live, lastPaidUntil: await billing.lastPaidUntil(), now: DateTime.now());
    if (mounted && access != _access) _set(access);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_access) {
      null => const BrandSplash(),
      Access.allowed => widget.child,
      Access.blocked => PaywallScreen(onUnlocked: () => _set(Access.allowed)),
    };
  }
}
