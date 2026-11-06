/// The subscription screen: what FieldOS Pro gives, the plans with the
/// store's own prices, and everything both stores ask a paywall to say
/// (price, renewal, when the trial is charged, how to cancel, restore,
/// terms and privacy).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/branded_page.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/legal/legal_screen.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/services/bug_report_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  List<PlanOffer>? _plans;
  String? _selected;
  String? _loadError;
  String? _error;
  bool _pending = false;
  bool _busy = false;

  BillingService get _billing => ref.read(billingServiceProvider);

  static final _linkStyle = TextButton.styleFrom(
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _plans = null;
    });
    try {
      final plans = await _billing.plans();
      if (!mounted) return;
      setState(() {
        _plans = plans;
        _selected = defaultPlan(plans)?.id;
      });
    } catch (e, st) {
      RecentErrors.record(e, st);
      if (mounted) {
        setState(() => _loadError =
            'Could not load the plans from ${_billing.storeName}. Check your internet connection and try again.');
      }
    }
  }

  Future<void> _act(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await body();
    } on BillingException catch (e) {
      if (mounted) {
        setState(() {
          _pending = e.pending;
          _error = e.pending ? null : e.message;
        });
      }
    } catch (e, st) {
      if (mounted) setState(() => _error = friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy() => _act(() async {
        final id = _selected;
        if (id == null) return;
        final s = await _billing.buy(id);
        if (!mounted || s == null) return; // backed out of the store sheet
        if (s.active) {
          widget.onUnlocked();
        } else {
          setState(() => _error = 'The purchase did not finish. Please try again.');
        }
      });

  Future<void> _restore() => _act(() async {
        final s = await _billing.restore();
        if (!mounted) return;
        if (s.active) {
          widget.onUnlocked();
        } else {
          final store = _billing.storeName;
          setState(() => _error = 'No FieldOS subscription was found on this $store account. If you subscribed '
              'with another account, switch to it in $store and try again.');
        }
      });

  Future<void> _checkAgain() => _act(() async {
        final s = await _billing.current(fresh: true);
        if (!mounted) return;
        if (s?.active ?? false) {
          widget.onUnlocked();
        } else {
          setState(() => _error = s == null
              ? 'No internet connection. Connect and check again.'
              : 'Still waiting for the payment. It can take a few minutes after you approve it.');
        }
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plans = _plans;
    final trial = plans == null ? null : bestTrial(plans);
    final selected = plans?.where((p) => p.id == _selected).firstOrNull;
    final compact = BrandedSheetPage.isCompact(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4);
    return BrandedSheetPage(
      trailing: _Menu(busy: _busy),
      header: [
        SizedBox(height: compact ? 8 : 28),
        BrandMark(size: compact ? 44 : 68, onDark: true),
        const SizedBox(height: 4),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Wordmark(fontSize: 28, onDark: true), SizedBox(width: 8), _ProBadge()],
        ),
        SizedBox(height: compact ? 8 : 12),
        Text(
          trial != null ? 'Try it free for ${trial.length}' : 'Keep every site on track',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white),
        ),
        SizedBox(height: compact ? 8 : 14),
        // On a small phone two lines are enough, so the plan and its button
        // show without scrolling.
        _Benefits(count: compact ? 2 : 4),
      ],
      sheet: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loadError != null) ...[
            FormMessage(_loadError!),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ] else if (plans == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (plans.isEmpty) ...[
            const FormMessage('The subscription is not on sale yet. Please try again later.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ] else ...[
            Text(plans.length > 1 ? 'Choose your plan' : 'Your plan', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final p in plans) ...[
              _PlanCard(
                plan: p,
                selected: p.id == _selected,
                onTap: _busy ? null : () => setState(() => _selected = p.id),
              ),
              const SizedBox(height: 10),
            ],
            if (_pending) ...[
              _PendingCard(onCheck: _busy ? null : _checkAgain, store: _billing.storeName),
              const SizedBox(height: 10),
            ],
            if (_error != null) ...[
              FormMessage(_error!),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            FilledButton(
              key: const Key('paywall-buy'),
              onPressed: _busy || selected == null ? null : _buy,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              child: _busy
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(selected?.buttonLabel ?? 'Choose a plan'),
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Text(
                selected.disclosure(store: _billing.storeName, cancelIn: _billing.cancelPath),
                textAlign: TextAlign.center,
                style: muted,
              ),
            ],
          ],
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(style: _linkStyle, onPressed: _busy ? null : _restore, child: const Text('Restore purchase')),
              TextButton(style: _linkStyle, onPressed: () => openTerms(context), child: const Text('Terms')),
              TextButton(
                  style: _linkStyle, onPressed: () => openPrivacyPolicy(context), child: const Text('Privacy policy')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: Brand.amber, borderRadius: BorderRadius.circular(6)),
      child: const Text(
        'PRO',
        style: TextStyle(
          fontFamily: Brand.fontFamily,
          color: Brand.navy,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits({required this.count});

  final int count;

  static const _items = [
    (Icons.mic_none_rounded, 'Speak daily reports in your own language'),
    (Icons.groups_outlined, 'Labour, wages and materials in one place'),
    (Icons.photo_camera_outlined, 'Photos, issues and team chat for every site'),
    (Icons.cloud_off_outlined, 'Works offline, syncs when you are back online'),
  ];

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, text) in _items.take(count))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(icon, size: 20, color: Brand.amber),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: style)),
              ]),
            ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  final PlanOffer plan;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = theme.brightness == Brightness.dark ? Brand.amber : Brand.navy;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.06) : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? accent : scheme.outlineVariant, width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? accent : scheme.outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plan.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(plan.priceLine, style: theme.textTheme.bodyMedium),
                      if (plan.pricePerMonth != null)
                        Text('Works out to ${plan.pricePerMonth} a month',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (plan.trial != null) ...[
                  const SizedBox(width: 8),
                  StatusPill('${plan.trial!.length} free', tone: PillTone.ok),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.onCheck, required this.store});

  final VoidCallback? onCheck;
  final String store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF4A3305) : Brand.warnSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.hourglass_top_rounded, color: dark ? Brand.amber : Brand.warn, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Payment waiting for approval', style: theme.textTheme.titleSmall)),
          ]),
          const SizedBox(height: 6),
          Text(
            'Approve it in your UPI or bank app. FieldOS opens by itself once $store confirms the payment, '
            'usually within a few minutes.',
            style: theme.textTheme.bodyMedium,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onCheck, child: const Text('Check again')),
          ),
        ],
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.busy});

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      enabled: !busy,
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (v) {
        switch (v) {
          case 'bug':
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen()));
          case 'email':
            emailSupport(subject: 'FieldOS: subscription');
          case 'logout':
            ref.read(cloudSyncBootstrapProvider).stop();
            ref.read(sessionProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'email', child: ListTile(leading: Icon(Icons.mail_outline), title: Text('Email support'))),
        PopupMenuItem(value: 'bug', child: ListTile(leading: Icon(Icons.bug_report_outlined), title: Text('Report a bug'))),
        PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Log out'))),
      ],
    );
  }
}
