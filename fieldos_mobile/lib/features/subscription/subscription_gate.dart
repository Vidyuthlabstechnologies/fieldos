import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/release_config.dart';
import 'package:fieldos_mobile/data/app_database.dart';
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
///
/// A company plan offline for over 7 days opens read-only instead
/// ([Access.readOnly]): the app opens, the database refuses changes
/// (lib/data/write_guard.dart), and [ReadOnlyBanner] says why on every
/// screen. Checked again every minute until the server answers.
class SubscriptionGate extends ConsumerStatefulWidget {
  const SubscriptionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends ConsumerState<SubscriptionGate> with WidgetsBindingObserver {
  Access? _access;
  VoidCallback? _stopListening;
  Timer? _recheck;
  late final WriteGuard _guard;

  /// How often a read-only phone asks the server again.
  static const recheckEvery = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    _guard = ref.read(appDatabaseProvider).writeGuard;
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
    _recheck?.cancel();
    // Signed out, or another kind of account: read-only belonged to this
    // gate's company plan. Just after (the banner can't rebuild while
    // the tree is being torn down), unless a new gate has set it since.
    final guard = _guard;
    final changes = guard.changes;
    if (guard.readOnly) {
      scheduleMicrotask(() {
        if (guard.changes == changes) guard.reason = null;
      });
    }
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

  void _set(Access access, {ReadOnlyReason reason = ReadOnlyReason.offlineTooLong}) {
    final wasAllowed = _access == Access.allowed || _access == Access.readOnly;
    _guard.reason = access == Access.readOnly ? reason : null;
    _recheck?.cancel();
    _recheck = access == Access.readOnly ? Timer.periodic(recheckEvery, (_) => _check()) : null;
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
      final store =
          accessFor(billingSetUp: true, live: null, lastPaidUntil: await billing.lastPaidUntil(), latestSeen: await billing.latestSeen(now), now: now);
      final remembered = store == Access.allowed ? Access.allowed : await company.access(live: null, now: now);
      if (remembered != Access.blocked && mounted) {
        _set(remembered, reason: await company.readOnlyReason(now));
      }
    }
    // Both asked every time: the company plan's site limit is needed even
    // by someone who also pays in the store.
    final results = await Future.wait<Object?>([billing.current(), company.current()]);
    final now = DateTime.now();
    final store = accessFor(
        billingSetUp: true,
        live: results[0] as SubscriptionState?,
        lastPaidUntil: await billing.lastPaidUntil(),
        latestSeen: await billing.latestSeen(now),
        now: now);
    final access = store == Access.allowed
        ? Access.allowed
        : await company.access(live: results[1] as List<CompanyPlan>?, now: now);
    final reason = await company.readOnlyReason(now);
    if (mounted && (access != _access || (access == Access.readOnly && _guard.state.value != reason))) {
      _set(access, reason: reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_access) {
      null => const BrandSplash(),
      Access.allowed || Access.readOnly => widget.child,
      Access.blocked => PaywallScreen(onUnlocked: () => _set(Access.allowed), onCompanyLinked: _check),
    };
  }
}

/// The read-only notice, above every screen while the phone is read-only
/// (see [SubscriptionGate]). Put in MaterialApp.builder so pushed screens
/// show it too.
class ReadOnlyBanner extends ConsumerWidget {
  const ReadOnlyBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guard = ref.watch(appDatabaseProvider).writeGuard;
    return ValueListenableBuilder<ReadOnlyReason?>(
      valueListenable: guard.state,
      child: child,
      builder: (context, reason, child) {
        if (reason == null) return child!;
        final scheme = Theme.of(context).colorScheme;
        return Column(children: [
          Material(
            key: const ValueKey('read-only-banner'),
            color: scheme.tertiaryContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Icon(Icons.cloud_off, size: 20, color: scheme.onTertiaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(readOnlyMessage(reason),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer)),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child!)),
        ]);
      },
    );
  }
}
