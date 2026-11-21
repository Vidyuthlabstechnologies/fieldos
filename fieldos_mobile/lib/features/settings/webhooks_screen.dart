/// Settings > Webhooks (owner only, online): FieldOS calls the company's
/// own address (Zapier, Make, an ERP) whenever a site record changes, signed
/// with a secret shown once. Queued and retried on the server
/// (20261121190000_open_api_writes_webhooks.sql), sent by the
/// webhook-dispatch edge function. See docs/OPEN_API.md, Webhooks.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// The resources a webhook can follow (api_resources() on the server). They
/// are the API's own names, shown as they are, since whoever sets up a
/// webhook reads them in the API guide too.
const webhookResources = [
  'projects', 'tasks', 'issues', 'daily_reports', 'inspections', 'approvals', 'rfis', 'submittals', 'defects',
  'drawings', 'drawing_revisions', 'hold_points', 'handover_units', 'constraints', 'attendance',
  'material_receipts', 'purchase_orders', 'expenses', 'client_bills', 'supplier_invoices', 'payments_received',
];

class Webhook {
  const Webhook({
    required this.id,
    required this.url,
    required this.events,
    required this.enabled,
    required this.createdAt,
    this.description,
    this.disabledReason,
    this.failingSince,
    this.lastSuccessAt,
  });
  final String id;
  final String url;
  final List<String> events;
  final bool enabled;
  final DateTime createdAt;
  final String? description;
  final String? disabledReason;
  final DateTime? failingSince;
  final DateTime? lastSuccessAt;

  bool get everything => events.contains('*');

  static DateTime? _ts(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  static Webhook fromRow(Map<String, dynamic> r) => Webhook(
        id: r['id'] as String,
        url: r['url'] as String,
        events: [for (final e in (r['events'] as List? ?? const ['*'])) '$e'],
        enabled: r['enabled'] as bool? ?? true,
        createdAt: _ts(r['created_at'])!,
        description: r['description'] as String?,
        disabledReason: r['disabled_reason'] as String?,
        failingSince: _ts(r['failing_since']),
        lastSuccessAt: _ts(r['last_success_at']),
      );
}

class WebhookDelivery {
  const WebhookDelivery({required this.eventType, required this.status, required this.attempts, required this.createdAt, this.lastError});
  final String eventType;
  final String status;
  final int attempts;
  final DateTime createdAt;
  final String? lastError;

  static WebhookDelivery fromRow(Map<String, dynamic> r) => WebhookDelivery(
        eventType: r['event_type'] as String,
        status: r['status'] as String,
        attempts: (r['attempts'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        lastError: r['last_error'] as String?,
      );
}

class WebhooksService {
  WebhooksService(this.client);
  final SupabaseClient client;

  Future<List<Webhook>> list(String companyId) async {
    final rows = await client
        .from('company_webhooks')
        .select('id, url, events, description, enabled, disabled_reason, failing_since, last_success_at, created_at')
        .eq('company_id', companyId)
        .order('created_at');
    return [for (final r in rows) Webhook.fromRow(r)];
  }

  /// Returns the signing secret, shown once.
  Future<String> create(String companyId, {required String url, required List<String> events, String? description}) async {
    final r = await client.rpc('create_company_webhook', params: {
      'p_company_id': companyId,
      'p_url': url.trim(),
      'p_events': events.isEmpty ? ['*'] : events,
      'p_description': description,
    });
    return (r as Map<String, dynamic>)['secret'] as String;
  }

  Future<void> setEnabled(String id, bool enabled) =>
      client.rpc('set_company_webhook_enabled', params: {'p_webhook_id': id, 'p_enabled': enabled});

  Future<String> rotateSecret(String id) async =>
      await client.rpc('rotate_company_webhook_secret', params: {'p_webhook_id': id}) as String;

  Future<void> delete(String id) => client.rpc('delete_company_webhook', params: {'p_webhook_id': id});

  /// Queues a ping and asks the server to send it now.
  Future<void> sendTest(String id) async {
    await client.rpc('send_company_webhook_test', params: {'p_webhook_id': id});
    try {
      await client.functions.invoke('webhook-dispatch', body: const {});
    } catch (_) {
      // The every-minute run sends it anyway.
    }
  }

  Future<List<WebhookDelivery>> deliveries(String id) async {
    final rows = await client
        .from('company_webhook_deliveries')
        .select('event_type, status, attempts, created_at, last_error')
        .eq('webhook_id', id)
        .order('created_at', ascending: false)
        .limit(20);
    return [for (final r in rows) WebhookDelivery.fromRow(r)];
  }
}

final webhooksServiceProvider = Provider<WebhooksService>((ref) => WebhooksService(ref.watch(cloudSyncClientProvider)));

final webhooksProvider = FutureProvider.autoDispose
    .family<List<Webhook>, String>((ref, companyId) => ref.watch(webhooksServiceProvider).list(companyId));

/// Same rules the server applies; checked here so the owner hears it before saving.
bool webhookAddressLooksRight(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.scheme != 'https' || u.host.isEmpty || u.userInfo.isNotEmpty) return false;
  if (u.hasPort && u.port != 443) return false;
  final host = u.host.toLowerCase();
  if (!host.contains('.') || RegExp(r'^[0-9.]+$').hasMatch(host) || host.contains(':')) return false;
  return !RegExp(r'\.(localhost|local|internal|intranet|lan|home|corp|private|arpa|test|invalid|example)$').hasMatch(host);
}

class WebhooksScreen extends ConsumerWidget {
  const WebhooksScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hooks = ref.watch(webhooksProvider(companyId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Webhooks'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('webhook-new'),
        icon: const Icon(Icons.add),
        label: Text(tr('Add webhook')),
        onPressed: () => _create(context, ref),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          Text(
            tr('FieldOS calls your address the moment a site record changes, so Zapier, Make or your ERP can act on it straight away. Each call is signed with a secret only you and the other software know.'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          ...switch (hooks) {
            AsyncData(:final value) when value.isEmpty => [Text(tr('No webhooks yet'), style: theme.textTheme.titleSmall)],
            AsyncData(:final value) => [for (final w in value) _tile(context, ref, w)],
            AsyncError(:final error) => [Text(trf('Could not load the webhooks: {error}', {'error': '$error'}))],
            _ => [const Center(child: CircularProgressIndicator())],
          },
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, Webhook w) {
    final state = !w.enabled
        // Switched off by the server after 3 days of failures keeps failing_since.
        ? (w.failingSince != null ? tr('Off: it kept failing for 3 days') : tr('Off'))
        : w.failingSince != null
            ? trf('Failing since {day}', {'day': fmtDate(w.failingSince!, short: true)})
            : w.lastSuccessAt != null
                ? trf('last delivered {day}', {'day': fmtDate(w.lastSuccessAt!, short: true)})
                : tr('nothing sent yet');
    return Card(
      key: Key('webhook-${w.id}'),
      child: ListTile(
        leading: Icon(w.enabled ? Icons.webhook : Icons.pause_circle_outline,
            color: w.enabled && w.failingSince == null ? null : Theme.of(context).colorScheme.error),
        title: Text(w.description ?? Uri.parse(w.url).host, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          w.everything ? tr('Every change') : w.events.join(', '),
          state,
        ].join(' · ')),
        trailing: PopupMenuButton<String>(
          key: Key('webhook-menu-${w.id}'),
          onSelected: (v) => _act(context, ref, w, v),
          itemBuilder: (_) => [
            if (w.enabled) PopupMenuItem(value: 'test', child: Text(tr('Send a test'))),
            PopupMenuItem(value: 'log', child: Text(tr('Recent deliveries'))),
            PopupMenuItem(value: 'toggle', child: Text(w.enabled ? tr('Switch off') : tr('Switch on'))),
            PopupMenuItem(value: 'secret', child: Text(tr('New secret'))),
            PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
          ],
        ),
      ),
    );
  }

  Future<void> _act(BuildContext context, WidgetRef ref, Webhook w, String action) async {
    final svc = ref.read(webhooksServiceProvider);
    try {
      switch (action) {
        case 'test':
          await svc.sendTest(w.id);
          if (context.mounted) showSnack(context, 'Test sent. Check the other software.');
        case 'log':
          final list = await svc.deliveries(w.id);
          if (context.mounted) await _showLog(context, list);
        case 'toggle':
          await svc.setEnabled(w.id, !w.enabled);
        case 'secret':
          final ok = await _confirm(context, tr('Make a new secret?'),
              tr('The old one stops working at once. Put the new one in the other software straight away.'));
          if (ok != true) return;
          final secret = await svc.rotateSecret(w.id);
          if (context.mounted) await _showSecret(context, secret);
        case 'delete':
          final ok = await _confirm(context, trf('Delete {name}?', {'name': w.description ?? Uri.parse(w.url).host}),
              tr('FieldOS stops calling this address. This cannot be undone.'));
          if (ok != true) return;
          await svc.delete(w.id);
      }
      ref.invalidate(webhooksProvider(companyId));
    } on PostgrestException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(key: const Key('webhook-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Yes'))),
          ],
        ),
      );

  Future<void> _showLog(BuildContext context, List<WebhookDelivery> list) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (list.isEmpty) Text(tr('Nothing sent yet.')),
            for (final d in list)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (d.status) {
                  'delivered' => Icons.check_circle_outline,
                  'failed' => Icons.error_outline,
                  _ => Icons.schedule,
                }),
                title: Text(d.eventType),
                subtitle: Text([
                  fmtDate(d.createdAt, short: true),
                  switch (d.status) {
                    'delivered' => tr('delivered'),
                    'failed' => tr('gave up'),
                    _ => trf('trying again, {n} tries so far', {'n': '${d.attempts}'}),
                  },
                  if (d.lastError != null && d.status != 'delivered') d.lastError!,
                ].join(' · ')),
              ),
          ],
        ),
      );

  Future<void> _showSecret(BuildContext context, String secret) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Copy the secret now')),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('It is shown only this once. The other software uses it to check that each call really came from FieldOS.')),
            const SizedBox(height: 12),
            SelectableText(secret, key: const Key('webhook-secret')),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: secret));
                showSnack(ctx, tr('Copied'));
              },
              child: Text(tr('Copy')),
            ),
            FilledButton(key: const Key('webhook-done'), onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
          ],
        ),
      );

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final url = TextEditingController();
    final name = TextEditingController();
    var everything = true;
    final picked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final urlOk = webhookAddressLooksRight(url.text);
          return AlertDialog(
            title: Text(tr('Add webhook')),
            scrollable: true,
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                key: const Key('webhook-url'),
                controller: url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr('Address to call'),
                  hintText: 'https://hooks.zapier.com/…',
                  errorText: url.text.isEmpty || urlOk ? null : tr('Use a public https:// address'),
                ),
              ),
              TextField(
                key: const Key('webhook-name'),
                controller: name,
                maxLength: 60,
                decoration: InputDecoration(labelText: tr('What it is for'), hintText: tr('e.g. Zapier')),
              ),
              SwitchListTile(
                key: const Key('webhook-everything'),
                contentPadding: EdgeInsets.zero,
                value: everything,
                onChanged: (v) => setState(() => everything = v),
                title: Text(tr('Every change')),
              ),
              if (!everything)
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final r in webhookResources)
                    FilterChip(
                      key: Key('webhook-event-$r'),
                      label: Text(r),
                      selected: picked.contains(r),
                      onSelected: (v) => setState(() => v ? picked.add(r) : picked.remove(r)),
                    ),
                ]),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
              FilledButton(
                key: const Key('webhook-create'),
                onPressed: urlOk && (everything || picked.isNotEmpty) ? () => Navigator.pop(ctx, true) : null,
                child: Text(tr('Add')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final secret = await ref.read(webhooksServiceProvider).create(companyId,
          url: url.text,
          events: everything ? const ['*'] : (picked.toList()..sort()),
          description: name.text.trim().isEmpty ? null : name.text.trim());
      ref.invalidate(webhooksProvider(companyId));
      if (context.mounted) await _showSecret(context, secret);
    } on PostgrestException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }
}
