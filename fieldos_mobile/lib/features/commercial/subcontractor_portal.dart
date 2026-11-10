/// The subcontractor's own FieldOS: free, and restricted to their firm's
/// work orders. They claim completed quantities with photos and see what
/// the site engineer accepted, rejected or sent to a variation. Nothing
/// else of the builder's sites reaches this phone: the server only shares
/// their own work orders, claims and certificates with them
/// (20261110100000_commercial_controls.sql).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/commercial/commercial_data.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/commercial/commercial_screens.dart' show recordClaim;
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

String subcontractorLinkKey(String companyId) => 'subcontractor_link:$companyId';

/// This phone's subcontractor firm within [companyId], if it joined as one.
final subcontractorLinkProvider = FutureProvider.autoDispose.family<String?, String>(
    (ref, companyId) => ref.watch(appDatabaseProvider).settingsDao.get(subcontractorLinkKey(companyId)));

/// Every work order of the firm, by site.
final _portalProvider = FutureProvider.autoDispose
    .family<List<({Project site, CommercialData data, List<WorkOrder> orders})>, String>((ref, companyId) async {
  final db = ref.watch(appDatabaseProvider);
  final subId = await ref.watch(subcontractorLinkProvider(companyId).future);
  if (subId == null) return const [];
  final out = <({Project site, CommercialData data, List<WorkOrder> orders})>[];
  for (final p in await db.projectDao.forCompany(companyId)) {
    final d = await loadCommercialData(db, p.id);
    final mine = d.workOrders.where((o) => o.subcontractorId == subId).toList();
    if (mine.isNotEmpty) out.add((site: p, data: d, orders: mine));
  }
  return out;
});

class SubcontractorHomeScreen extends ConsumerStatefulWidget {
  const SubcontractorHomeScreen({super.key});

  @override
  ConsumerState<SubcontractorHomeScreen> createState() => _HomeState();
}

class _HomeState extends ConsumerState<SubcontractorHomeScreen> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final service = ref.read(cloudSyncServiceProvider);
      if (!service.isSignedIn) await service.restoreSession();
      final r = await service.syncNow();
      if (mounted) {
        showSnack(context, r.failed == 0 ? tr('Up to date.') : trf('{n} waiting to send. They will retry.', {'n': r.failed}),
            error: r.failed > 0);
      }
    } catch (e, st) {
      if (mounted) showSnack(context, friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
      final company = ref.read(sessionProvider).activeCompany;
      if (company != null) ref.invalidate(_portalProvider(company.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final company = session.activeCompany!;
    final async = ref.watch(_portalProvider(company.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(trf('My work for {company}', {'company': company.name})),
        actions: [
          IconButton(
            tooltip: tr('Sync now'),
            icon: _syncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            onPressed: _syncing ? null : _sync,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') {
                ref.read(cloudSyncBootstrapProvider).stop();
                ref.read(sessionProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'logout', child: ListTile(leading: const Icon(Icons.logout), title: Text(tr('Log out')))),
            ],
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (sites) => RefreshIndicator(
          onRefresh: _sync,
          child: sites.isEmpty
              ? ListView(children: [
                  EmptyState(
                    icon: Icons.handshake_outlined,
                    title: tr('No work orders yet'),
                    message: tr('When the builder gives your firm a work order, it appears here after a sync. '
                        'Then you can claim the work you finish.'),
                  ),
                ])
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final s in sites) ...[
                    SectionHeader(s.site.name),
                    for (final o in s.orders) _PortalOrderCard(data: s.data, order: o, onChanged: () => ref.invalidate(_portalProvider(company.id))),
                  ],
                ]),
        ),
      ),
    );
  }
}

class _PortalOrderCard extends ConsumerWidget {
  const _PortalOrderCard({required this.data, required this.order, required this.onChanged});
  final CommercialData data;
  final WorkOrder order;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pos = data.position(order);
    final claims = data.claims.where((c) => c.workOrderId == order.id).toList().reversed.toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(order.description, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          KeyValue(tr('Agreed'), '${qtyUnit(pos.baselineQty, order.unit)} · ${rupees(pos.rate, paise: true)}/${order.unit ?? ''}'),
          KeyValue(tr('Certified to date'), '${qtyUnit(pos.certifiedQty, order.unit)} · ${rupees(pos.certifiedValue)}', strong: true),
          for (final c in claims) ...[
            const Divider(),
            Row(children: [
              Expanded(child: Text('${fmtDate(c.createdAt)} · ${qtyUnit(c.qty, order.unit)}')),
              StatusPill(claimPill(data.claim(c)).$1, tone: claimPill(data.claim(c)).$2),
            ]),
            if (data.photosOf(c.id).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: PhotoStrip(paths: data.photosOf(c.id).map((a) => a.filePath).toList(), size: 48),
              ),
            for (final cert in data.claim(c).certifications)
              if ((cert.note ?? '').isNotEmpty) Text('"${cert.note}"', style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.playlist_add),
            label: Text(tr('Claim completed work')),
            onPressed: () async {
              await recordClaim(context, ref, order, by: ref.read(sessionProvider).user!.id);
              onChanged();
            },
          ),
        ]),
      ),
    );
  }
}

/// A subcontractor's first step: sign in to the cloud and enter the code
/// the builder gave them. Free; no subscription.
class SubcontractorJoinScreen extends ConsumerStatefulWidget {
  const SubcontractorJoinScreen({super.key});

  @override
  ConsumerState<SubcontractorJoinScreen> createState() => _JoinState();
}

class _JoinState extends ConsumerState<SubcontractorJoinScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _emailCode = TextEditingController();
  bool _busy = false;
  bool _needsEmailCode = false;
  String? _message;
  bool _error = false;

  void _say(String m, {bool error = false}) => setState(() {
        _message = m;
        _error = error;
      });

  Future<void> _join() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (code.isEmpty) return _say(tr('Enter the code the builder gave you.'), error: true);
    setState(() => _busy = true);
    try {
      final service = ref.read(cloudSyncServiceProvider);
      if (_needsEmailCode) {
        await service.confirmSignUp(email: email, code: _emailCode.text);
      } else if (!service.isSignedIn) {
        if (!email.contains('@') || _password.text.length < 6) {
          return _say(tr('Enter your email and a password of at least 6 characters.'), error: true);
        }
        final r = await service.enableSync(email: email, password: _password.text);
        switch (r.outcome) {
          case CloudSyncOutcome.signedIn || CloudSyncOutcome.signedUp:
            break;
          case CloudSyncOutcome.needsEmailConfirmation:
            setState(() => _needsEmailCode = true);
            return _say(trf('We sent a code to {email}. Type it below, then tap Join.', {'email': email}));
          case CloudSyncOutcome.wrongPassword:
            return _say(tr('That password is not right for this email.'), error: true);
          case CloudSyncOutcome.failed:
            return _say(r.cause == null ? tr('Could not sign in. Try again.') : friendlyError(r.cause!, r.stack), error: true);
        }
      }
      final link = await service.joinAsSubcontractor(code);
      final db = ref.read(appDatabaseProvider);
      await db.settingsDao.set(subcontractorLinkKey(link.companyId), link.subcontractorId);
      await ref
          .read(sessionProvider.notifier)
          .adoptCloudCompany(id: link.companyId, name: link.companyName, role: Roles.subcontractor);
      await ref.read(cloudLinksProvider).link(link.companyId);
      await service.syncNow();
      await ref.read(cloudSyncBootstrapProvider).ensureRunning();
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e, st) {
      _say(friendlyError(e, st), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(cloudSyncServiceProvider).isSignedIn;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Join as a subcontractor'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Free for subcontractors. You will see only your own work orders, claim the work you finish with '
            'photos, and see what the site accepted.')),
        const SizedBox(height: 16),
        if (!signedIn) ...[
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: tr('Email'))),
          TextField(controller: _password, obscureText: true, decoration: InputDecoration(labelText: tr('Password'))),
        ],
        if (_needsEmailCode)
          TextField(controller: _emailCode, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Code from the email'))),
        TextField(
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr('Code from the builder')),
        ),
        const SizedBox(height: 16),
        if (_message != null) FormMessage(_message!, error: _error),
        FilledButton(onPressed: _busy ? null : _join, child: Text(_busy ? tr('Joining...') : tr('Join'))),
      ]),
    );
  }
}
