/// The free supplier and client apps: join with the builder's code, then a
/// supplier answers price requests and says when an order is on its way,
/// and a client follows their site's progress, bills and payments. Online
/// only; nothing of the builder's company is kept on these phones.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

String _error(Object e, StackTrace st) => e is PortalJoinError
    ? (e.code == 'too_many_attempts'
        ? tr('Too many wrong codes. Try again in an hour.')
        : tr('That code is not right. Check it with the builder.'))
    : friendlyError(e, st);

/// "Supplier or site owner? Join free with the builder's code."
class PortalJoinScreen extends ConsumerStatefulWidget {
  const PortalJoinScreen({super.key});

  @override
  ConsumerState<PortalJoinScreen> createState() => _PortalJoinScreenState();
}

class _PortalJoinScreenState extends ConsumerState<PortalJoinScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _emailCode = TextEditingController();
  bool _busy = false;
  bool _needsEmailCode = false;
  String? _message;
  bool _isError = false;

  void _say(String m, {bool error = false}) => setState(() {
        _message = m;
        _isError = error;
      });

  Future<void> _join() async {
    final email = _email.text.trim();
    final code = _code.text.trim();
    if (code.isEmpty) return _say(tr('Enter the code the builder gave you.'), error: true);
    setState(() {
      _busy = true;
    });
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
            setState(() {
              _needsEmailCode = true;
            });
            return _say(trf('We sent a code to {email}. Type it below, then tap Join.', {'email': email}));
          case CloudSyncOutcome.wrongPassword:
            return _say(tr('That password is not right for this email.'), error: true);
          case CloudSyncOutcome.failed:
            return _say(r.cause == null ? tr('Could not sign in. Try again.') : friendlyError(r.cause!, r.stack), error: true);
        }
      }
      final link = await ref.read(portalServiceProvider).join(code);
      await ref.read(sessionProvider.notifier).adoptCloudCompany(
          id: link.companyId,
          name: link.companyName,
          role: link.kind == PortalKind.supplier ? Roles.supplier : Roles.client);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e, st) {
      _say(_error(e, st), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(cloudSyncServiceProvider).isSignedIn;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Join as a supplier or client'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(tr('Free for the builder\'s suppliers and clients. Suppliers answer price requests and say when an '
            'order is on its way. Clients see their site\'s progress, photos, bills and payments.')),
        const SizedBox(height: 16),
        if (!signedIn) ...[
          TextField(
              key: const Key('portal-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('Email'))),
          TextField(
              key: const Key('portal-password'),
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Password'))),
        ],
        if (_needsEmailCode)
          TextField(
              controller: _emailCode,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Code from the email'))),
        TextField(
          key: const Key('portal-code'),
          controller: _code,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: tr('Code from the builder')),
        ),
        const SizedBox(height: 16),
        if (_message != null) FormMessage(_message!, error: _isError),
        FilledButton(
            key: const Key('portal-join'),
            onPressed: _busy ? null : _join,
            child: Text(_busy ? tr('Joining...') : tr('Join'))),
      ]),
    );
  }
}

/// Log out, the one menu item a portal needs.
Widget _portalMenu(WidgetRef ref) => PopupMenuButton<String>(
      onSelected: (v) {
        if (v == 'logout') {
          ref.read(cloudSyncBootstrapProvider).stop();
          ref.read(sessionProvider.notifier).logout();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'logout', child: ListTile(leading: const Icon(Icons.logout), title: Text(tr('Log out')))),
      ],
    );

/// Signs back in if the phone was restarted, then loads.
Future<T> _online<T>(Ref ref, Future<T> Function(PortalService) load) async {
  final service = ref.read(cloudSyncServiceProvider);
  if (!service.isSignedIn) await service.restoreSession();
  return load(ref.read(portalServiceProvider));
}

final supplierPortalProvider =
    FutureProvider.autoDispose<SupplierPortalData>((ref) => _online(ref, (s) => s.supplierPortal()));

final clientPortalProvider = FutureProvider.autoDispose<List<ClientSite>>((ref) => _online(ref, (s) => s.clientPortal()));

String supplierOrderStatus(String s) => switch (s) {
      'issued' => tr('New order'),
      'acknowledged' => tr('On the way'),
      'delivered' => tr('Received at site'),
      _ => s,
    };

String supplierQuoteStatus(String s) => switch (s) {
      'accepted' => tr('You got the order'),
      'rejected' => tr('Not chosen this time'),
      _ => tr('Price sent'),
    };

class SupplierHomeScreen extends ConsumerWidget {
  const SupplierHomeScreen({super.key});

  Future<void> _quote(BuildContext context, WidgetRef ref, PriceRequest r) async {
    final q = r.quote;
    final rate = TextEditingController(text: q == null ? '' : fmtQty(q.rate));
    final gst = TextEditingController(text: fmtQty(q?.gstPct ?? 18));
    final transport = TextEditingController(text: q == null || q.transport == 0 ? '' : fmtQty(q.transport));
    final days = TextEditingController(text: q?.deliveryDays?.toString() ?? '');
    final terms = TextEditingController(text: q?.paymentTerms ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('Your price for {item}', {'item': r.item})),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${fmtQty(r.quantity)} ${r.unit} · ${r.site}', style: Theme.of(ctx).textTheme.bodySmall),
          TextField(
              key: const Key('quote-rate'),
              controller: rate,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: trf('Rate a {unit}, before GST (₹)', {'unit': r.unit}))),
          TextField(
              key: const Key('quote-gst'),
              controller: gst,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('GST %'))),
          TextField(
              key: const Key('quote-transport'),
              controller: transport,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Transport (₹)'))),
          TextField(
              key: const Key('quote-days'),
              controller: days,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Delivery in (days)'))),
          TextField(
              controller: terms,
              maxLength: 120,
              decoration: InputDecoration(labelText: tr('Payment terms (e.g. 30 days credit)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('quote-send'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Send price'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final rateV = double.tryParse(rate.text.trim());
    if (rateV == null || rateV <= 0) {
      showSnack(context, tr('Enter the rate a unit.'), error: true);
      return;
    }
    try {
      await ref.read(portalServiceProvider).sendQuote(r,
          rate: rateV,
          gstPct: double.tryParse(gst.text.trim()) ?? 18,
          transport: double.tryParse(transport.text.trim()) ?? 0,
          deliveryDays: int.tryParse(days.text.trim()),
          paymentTerms: terms.text);
      ref.invalidate(supplierPortalProvider);
      if (context.mounted) showSnack(context, tr('Price sent. The site compares it with the others.'));
    } catch (e, st) {
      if (context.mounted) showSnack(context, _error(e, st), error: true);
    }
  }

  Future<void> _dispatch(BuildContext context, WidgetRef ref, SupplierOrder o) async {
    final vehicle = TextEditingController(text: o.vehicle ?? '');
    final note = TextEditingController(text: o.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('On the way')),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              key: const Key('dispatch-vehicle'),
              controller: vehicle,
              textCapitalization: TextCapitalization.characters,
              maxLength: 40,
              decoration: InputDecoration(labelText: tr('Vehicle number'))),
          TextField(
              key: const Key('dispatch-note'),
              controller: note,
              maxLength: 300,
              decoration: InputDecoration(labelText: tr('Note for the site (driver, time)'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('dispatch-save'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tell the site'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(portalServiceProvider).dispatch(o.id, vehicle: vehicle.text, note: note.text);
      ref.invalidate(supplierPortalProvider);
      if (context.mounted) showSnack(context, tr('The site knows it is on the way.'));
    } catch (e, st) {
      if (context.mounted) showSnack(context, _error(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(sessionProvider).activeCompany;
    final async = ref.watch(supplierPortalProvider);
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(company == null ? tr('Supplier') : trf('Supplying {company}', {'company': company.name})),
          actions: [
            IconButton(
                tooltip: tr('Refresh'),
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(supplierPortalProvider)),
            _portalMenu(ref),
          ],
          bottom: TabBar(tabs: [Tab(text: tr('Price requests')), Tab(text: tr('Orders'))]),
        ),
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
          data: (d) {
            Widget refreshable(Widget child) =>
                RefreshIndicator(onRefresh: () => ref.refresh(supplierPortalProvider.future), child: child);
            return TabBarView(children: [
              refreshable(d.requests.isEmpty
                  ? ListView(children: [
                      EmptyState(
                          icon: Icons.request_quote_outlined,
                          title: tr('No price requests yet'),
                          message: tr('When the site asks you for a price, it shows here. Send your rate in a minute.')),
                    ])
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final r in d.requests)
                        Card(
                          key: Key('rfq-${r.id}'),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Text(r.item, style: theme.textTheme.titleMedium),
                              Text('${fmtQty(r.quantity)} ${r.unit} · ${r.site} · ${r.companyName}',
                                  style: theme.textTheme.bodySmall),
                              if (r.notes != null && r.notes!.isNotEmpty) Text(r.notes!, style: theme.textTheme.bodySmall),
                              if (r.quote case final q?)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                      '${supplierQuoteStatus(q.status)}: ${rupees(q.rate, paise: true)} / ${r.unit} + ${fmtQty(q.gstPct)}% GST',
                                      style: theme.textTheme.bodyMedium),
                                ),
                              if (r.open && (r.quote == null || r.quote!.status == 'received'))
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.tonal(
                                    key: Key('price-${r.id}'),
                                    onPressed: () => _quote(context, ref, r),
                                    child: Text(r.quote == null ? tr('Send price') : tr('Change price')),
                                  ),
                                )
                              else if (!r.open && r.quote == null)
                                Text(tr('Closed'), style: theme.textTheme.bodySmall),
                            ]),
                          ),
                        ),
                    ])),
              refreshable(d.orders.isEmpty
                  ? ListView(children: [
                      EmptyState(
                          icon: Icons.local_shipping_outlined,
                          title: tr('No orders yet'),
                          message: tr('Orders the builder gives you show here, with what the site received.')),
                    ])
                  : ListView(padding: const EdgeInsets.all(12), children: [
                      for (final o in d.orders)
                        Card(
                          key: Key('order-${o.id}'),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Expanded(
                                  child: Text(o.poNumber ?? o.item ?? tr('Order'), style: theme.textTheme.titleMedium),
                                ),
                                Text(supplierOrderStatus(o.status), style: theme.textTheme.labelLarge),
                              ]),
                              Text(
                                  [
                                    ?o.item,
                                    o.site,
                                    if (o.total != null) rupees(o.total!),
                                    if (o.deliveryDate != null) trf('by {date}', {'date': fmtDate(o.deliveryDate!, short: true)}),
                                  ].join(' · '),
                                  style: theme.textTheme.bodySmall),
                              if (o.vehicle != null) Text(trf('Vehicle {v}', {'v': o.vehicle!}), style: theme.textTheme.bodySmall),
                              if (o.open)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.tonal(
                                    key: Key('dispatch-${o.id}'),
                                    onPressed: () => _dispatch(context, ref, o),
                                    child: Text(o.status == 'acknowledged' ? tr('Change vehicle') : tr('On the way')),
                                  ),
                                ),
                            ]),
                          ),
                        ),
                    ])),
            ]);
          },
        ),
      ),
    );
  }
}

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(clientPortalProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('My site')),
        actions: [
          IconButton(tooltip: tr('Refresh'), icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(clientPortalProvider)),
          _portalMenu(ref),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (sites) => RefreshIndicator(
          onRefresh: () => ref.refresh(clientPortalProvider.future),
          child: sites.isEmpty
              ? ListView(children: [
                  EmptyState(
                      icon: Icons.home_work_outlined,
                      title: tr('No site yet'),
                      message: tr('Ask the builder for your site\'s code.')),
                ])
              : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final s in sites) ...[
                    Card(
                      key: Key('client-site-${s.id}'),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(s.name, style: theme.textTheme.titleLarge),
                          Text(trf('Built by {company}', {'company': s.companyName}), style: theme.textTheme.bodySmall),
                          const SizedBox(height: 10),
                          if (s.progress case final p?) ...[
                            LinearProgressIndicator(value: p, minHeight: 8, borderRadius: BorderRadius.circular(4)),
                            const SizedBox(height: 4),
                            Text(trf('{done} of {total} jobs done', {'done': s.tasksDone, 'total': s.tasksTotal}),
                                key: const Key('client-progress'), style: theme.textTheme.bodySmall),
                          ],
                          const SizedBox(height: 10),
                          Wrap(spacing: 16, runSpacing: 8, children: [
                            _Figure(tr('Billed'), rupees(s.billed)),
                            _Figure(tr('Paid'), rupees(s.paid)),
                            _Figure(tr('Balance'), rupees(s.balance), key: const Key('client-balance')),
                          ]),
                        ]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                      child: Text(tr('Daily updates'), style: theme.textTheme.titleMedium),
                    ),
                    if (s.updates.isEmpty)
                      Padding(padding: const EdgeInsets.all(8), child: Text(tr('No updates yet.'))),
                    for (final u in s.updates) _UpdateCard(update: u),
                    if (s.bills.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Text(tr('Bills'), style: theme.textTheme.titleMedium),
                      ),
                      for (final b in s.bills)
                        ListTile(
                          dense: true,
                          title: Text('${b.number} · ${fmtDate(b.date, short: true)}'),
                          trailing: Text(rupees(b.amount)),
                          subtitle: Text(b.status == 'paid' ? tr('Paid') : tr('To pay')),
                        ),
                    ],
                    if (s.payments.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Text(tr('Payments'), style: theme.textTheme.titleMedium),
                      ),
                      for (final p in s.payments)
                        ListTile(
                          dense: true,
                          title: Text(fmtDate(p.date, short: true)),
                          trailing: Text(rupees(p.amount)),
                          subtitle: Text(p.mode.toUpperCase()),
                        ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ]),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ]);
}

final _photoUrlProvider = FutureProvider.autoDispose.family<String, String>((ref, path) =>
    _online(ref, (s) => s.photoUrl(path)));

class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.update});
  final SiteUpdate update;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(fmtDate(update.date), style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(update.summary),
          if (update.manpower > 0)
            Text(trf('{n} people on site', {'n': update.manpower}), style: theme.textTheme.bodySmall),
          if (update.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 84,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final p in update.photos)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 84,
                        height: 84,
                        child: ref.watch(_photoUrlProvider(p)).when(
                              data: (url) => Image.network(url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                              loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              error: (_, _) => const Icon(Icons.image_not_supported_outlined),
                            ),
                      ),
                    ),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
