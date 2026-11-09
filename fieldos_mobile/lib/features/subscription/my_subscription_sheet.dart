/// "My subscription": the plan's state in plain words, and the ways to
/// manage, cancel or restore it. A company plan (sold by invoice) shows
/// here too, with its active-site count; never its price (store rules).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/billing_service.dart';
import 'package:fieldos_mobile/services/company_plan.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

Future<void> showMySubscription(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const MySubscriptionSheet(),
    );

class MySubscriptionSheet extends ConsumerStatefulWidget {
  const MySubscriptionSheet({super.key});

  @override
  ConsumerState<MySubscriptionSheet> createState() => _MySubscriptionSheetState();
}

class _MySubscriptionSheetState extends ConsumerState<MySubscriptionSheet> {
  SubscriptionState? _state;
  CompanyPlan? _companyPlan;
  int _openSites = 0;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  BillingService get _billing => ref.read(billingServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyPlans = ref.read(companyPlanServiceProvider);
    final results = await Future.wait<Object?>([_billing.current(), companyPlans.current()]);
    final companyId = ref.read(sessionProvider).activeCompany?.id;
    final plans = results[1] as List<CompanyPlan>? ?? await companyPlans.remembered();
    final plan = planForCompany(plans, companyId);
    final open = companyId == null
        ? 0
        : (await ref.read(appDatabaseProvider).projectDao.forCompany(companyId))
            .where((p) => countsAsActiveSite(p.status))
            .length;
    if (mounted) {
      setState(() {
        _state = results[0] as SubscriptionState?;
        _companyPlan = plan;
        _openSites = open;
        _loading = false;
      });
    }
  }

  Future<void> _manage() async {
    final uri = await _billing.managementUrl();
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && mounted) {
      setState(() {
        _message = 'Could not open ${_billing.storeName}. Open ${_billing.cancelPath} yourself.';
        _messageIsError = true;
      });
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final s = await _billing.restore();
      if (!mounted) return;
      setState(() {
        _state = s;
        _messageIsError = !s.active;
        _message = s.active
            ? 'Your subscription is on this phone.'
            : 'No FieldOS subscription was found on this ${_billing.storeName} account.';
      });
    } catch (e, st) {
      if (mounted) {
        setState(() {
          _message = e is BillingException ? e.message : friendlyError(e, st);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4);
    final s = _state;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const BrandTile(size: 44),
              const SizedBox(width: 12),
              Expanded(child: Text('FieldOS Pro', style: theme.textTheme.titleLarge)),
            ]),
            const SizedBox(height: 20),
            if (!_loading && _companyPlan != null) ...[
              _CompanyPlanTile(plan: _companyPlan!, openSites: _openSites),
              const SizedBox(height: 16),
            ],
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_companyPlan != null && !(s?.active ?? false))
              Text('You do not need a subscription of your own while your company plan covers you.', style: muted)
            else if (s == null)
              FormMessage('Could not check your subscription with ${_billing.storeName} right now. Please try again in a minute.')
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                  !s.active || s.billingIssue ? Icons.warning_amber_rounded : Icons.verified_outlined,
                  color: !s.active || s.billingIssue ? theme.colorScheme.error : Brand.ok,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(s.describe(), style: theme.textTheme.bodyLarge)),
              ]),
            if (_message != null) ...[
              const SizedBox(height: 12),
              FormMessage(_message!, error: _messageIsError),
            ],
            const SizedBox(height: 20),
            // Free access from the team: there is no store purchase to
            // manage, and Restore would swap the access for this phone's
            // own store account.
            if (s?.complimentary ?? false)
              Text(
                'The FieldOS team gave you this access, so there is nothing to pay or cancel. When it ends, FieldOS '
                'asks you to choose a plan, and your records stay on this phone.',
                style: muted,
              )
            else if (_companyPlan != null && !(s?.active ?? false))
              const SizedBox.shrink()
            else ...[
              FilledButton.icon(
                onPressed: _busy ? null : _manage,
                icon: const Icon(Icons.open_in_new),
                label: Text(s?.billingIssue ?? false ? 'Update payment method' : 'Manage or cancel'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _restore,
                child: _busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Restore purchase'),
              ),
              const SizedBox(height: 16),
              Text(
                'To cancel, open ${_billing.cancelPath}. You keep FieldOS Pro until the end of the period you have '
                'paid for, and your records stay on this phone.',
                style: muted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompanyPlanTile extends StatelessWidget {
  const _CompanyPlanTile({required this.plan, required this.openSites});

  final CompanyPlan plan;
  final int openSites;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limit = plan.siteLimit;
    return Card(
      key: const Key('company-plan-tile'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.apartment_outlined, color: Brand.ok),
            const SizedBox(width: 10),
            Expanded(child: Text(plan.name, style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 6),
          Text(plan.describe(), style: theme.textTheme.bodyMedium),
          if (limit != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: (openSites / limit).clamp(0, 1).toDouble()),
            const SizedBox(height: 6),
            Text('$openSites of $limit active sites in use', style: theme.textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}
