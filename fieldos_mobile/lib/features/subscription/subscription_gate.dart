import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

/// Shows [child] only while this person has a subscription (the 3-day
/// trial counts). Otherwise shows the paywall. Checked on open and every
/// time the app comes back to the foreground.
class SubscriptionGate extends ConsumerStatefulWidget {
  const SubscriptionGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends ConsumerState<SubscriptionGate> with WidgetsBindingObserver {
  Access? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!ref.read(billingServiceProvider).setUp) {
      _access = Access.allowed; // development build, or payments not configured yet
    } else {
      _check(firstTime: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check({bool firstTime = false}) async {
    final billing = ref.read(billingServiceProvider);
    if (!billing.setUp) return;
    final paidUntil = await billing.lastPaidUntil();
    // Open straight away for someone who was paid up last time, and let
    // the store's answer catch up in the background.
    if (firstTime && mounted) {
      final remembered = accessFor(billingSetUp: true, live: null, lastPaidUntil: paidUntil, now: DateTime.now());
      if (remembered == Access.allowed) setState(() => _access = Access.allowed);
    }
    final live = await billing.current();
    final access =
        accessFor(billingSetUp: true, live: live, lastPaidUntil: await billing.lastPaidUntil(), now: DateTime.now());
    if (mounted) setState(() => _access = access);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_access) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      Access.allowed => widget.child,
      Access.blocked => PaywallScreen(onUnlocked: () => setState(() => _access = Access.allowed)),
    };
  }
}

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  List<Package>? _packages;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await ref.read(billingServiceProvider).packages();
      if (mounted) setState(() => _packages = p);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach the store. Check your internet and try again.');
    }
  }

  Future<void> _do(Future<SubscriptionState?> Function() action, {required String notFound}) async {
    setState(() => _busy = true);
    try {
      final s = await action();
      if (!mounted) return;
      if (s != null && s.active) {
        widget.onUnlocked();
      } else if (s != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notFound)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('The store could not complete that. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _period(Package p) => switch (p.packageType) {
        PackageType.annual => 'year',
        PackageType.sixMonth => '6 months',
        PackageType.threeMonth => '3 months',
        PackageType.twoMonth => '2 months',
        PackageType.weekly => 'week',
        _ => 'month',
      };

  static String _label(Package p) => switch (p.packageType) {
        PackageType.annual => 'Yearly',
        PackageType.weekly => 'Weekly',
        PackageType.monthly => 'Monthly',
        _ => p.storeProduct.title,
      };

  @override
  Widget build(BuildContext context) {
    final billing = ref.read(billingServiceProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FieldOS'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'bug') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
              } else if (v == 'logout') {
                ref.read(cloudSyncBootstrapProvider).stop();
                ref.read(sessionProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bug', child: ListTile(leading: Icon(Icons.bug_report), title: Text('Report a bug'))),
              PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Log out'))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(Icons.workspace_premium, size: 56, color: Colors.amber.shade800),
            const SizedBox(height: 12),
            Text('Try FieldOS free for 3 days',
                textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Daily reports, labour, materials, photos, team chat and the site map, on and offline. '
              'After the trial your subscription continues automatically. Cancel anytime before it ends and you pay nothing.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ] else if (_packages == null)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_packages!.isEmpty)
              const Text('Subscriptions are not available in the store yet. Please try again later.',
                  textAlign: TextAlign.center)
            else
              for (final p in _packages!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FilledButton(
                    key: Key('buy-${p.identifier}'),
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy
                        ? null
                        : () => _do(() => billing.buy(p), notFound: 'The purchase did not go through.'),
                    child: Column(children: [
                      Text('${_label(p)}: ${p.storeProduct.priceString} a ${_period(p)}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Text('Start 3-day free trial', style: TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _do(billing.restore,
                      notFound: 'No subscription found on this Google Play or Apple account.'),
              child: const Text('I already subscribed (restore)'),
            ),
            const SizedBox(height: 12),
            Text(
              'Payment is taken by Google Play or the App Store when the trial ends, and renews until you cancel '
              'in your store account. The free trial is for new subscribers only.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
