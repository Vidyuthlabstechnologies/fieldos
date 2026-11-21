/// Settings > API keys (owner only, online): keys that let the company's
/// ERP, BI tool, Zapier or Make read its site records through the open API
/// (docs/OPEN_API.md), and, when the owner allows it, add and change tasks
/// and issues. A key is shown once; the server keeps only its hash
/// (20261115000000_open_api.sql, 20261121170000_open_api_writes_webhooks.sql).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase/supabase.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

class ApiKey {
  const ApiKey({
    required this.id,
    required this.name,
    required this.prefix,
    required this.createdAt,
    this.lastUsedAt,
    this.revokedAt,
    this.canWrite = false,
  });
  final String id;
  final String name;
  final String prefix;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  /// Can also create and update tasks and issues, and manage webhooks.
  final bool canWrite;

  static ApiKey fromRow(Map<String, dynamic> r) => ApiKey(
        id: r['id'] as String,
        name: r['name'] as String,
        prefix: r['key_prefix'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        lastUsedAt: r['last_used_at'] == null ? null : DateTime.parse(r['last_used_at'] as String).toLocal(),
        revokedAt: r['revoked_at'] == null ? null : DateTime.parse(r['revoked_at'] as String).toLocal(),
        canWrite: (r['scopes'] as List?)?.contains('write') ?? false,
      );
}

/// One change made through the API (api_audit_log).
class ApiChange {
  const ApiChange({required this.keyName, required this.action, required this.resource, required this.at});
  final String keyName;
  final String action;
  final String resource;
  final DateTime at;

  static ApiChange fromRow(Map<String, dynamic> r) => ApiChange(
        keyName: r['key_name'] as String,
        action: r['action'] as String,
        resource: r['resource'] as String,
        at: DateTime.parse(r['at'] as String).toLocal(),
      );
}

class ApiKeysService {
  ApiKeysService(this.client);
  final SupabaseClient client;

  Future<List<ApiKey>> list(String companyId) async {
    final rows = await client
        .from('company_api_keys')
        .select('id, name, key_prefix, created_at, last_used_at, revoked_at, scopes')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);
    return [for (final r in rows) ApiKey.fromRow(r)];
  }

  /// The new key, shown once. [write]: it may also add and change tasks and
  /// issues, and manage webhooks.
  Future<String> create(String companyId, String name, {bool write = false}) async {
    final r = await client.rpc('create_company_api_key', params: {
      'p_company_id': companyId,
      'p_name': name,
      'p_scopes': write ? ['read', 'write'] : ['read'],
    });
    return (r as Map<String, dynamic>)['key'] as String;
  }

  /// The latest changes made through keys, newest first.
  Future<List<ApiChange>> recentChanges(String companyId) async {
    final rows = await client
        .from('api_audit_log')
        .select('key_name, action, resource, at')
        .eq('company_id', companyId)
        .order('at', ascending: false)
        .limit(20);
    return [for (final r in rows) ApiChange.fromRow(r)];
  }

  Future<void> revoke(String keyId) => client.rpc('revoke_company_api_key', params: {'p_key_id': keyId});
}

final apiKeysServiceProvider = Provider<ApiKeysService>((ref) => ApiKeysService(ref.watch(cloudSyncClientProvider)));

final apiKeysProvider =
    FutureProvider.autoDispose.family<List<ApiKey>, String>((ref, companyId) => ref.watch(apiKeysServiceProvider).list(companyId));

final apiChangesProvider = FutureProvider.autoDispose
    .family<List<ApiChange>, String>((ref, companyId) => ref.watch(apiKeysServiceProvider).recentChanges(companyId));

String _changeLabel(ApiChange c) {
  final k = {'key': c.keyName};
  return switch ((c.action, c.resource)) {
    ('create', 'tasks') => trf('{key} added a task', k),
    ('update', 'tasks') => trf('{key} changed a task', k),
    ('create', 'issues') => trf('{key} added an issue', k),
    ('update', 'issues') => trf('{key} changed an issue', k),
    ('webhook_create', _) => trf('{key} added a webhook', k),
    ('webhook_delete', _) => trf('{key} deleted a webhook', k),
    _ => '${c.keyName}: ${c.action} ${c.resource}',
  };
}

class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(apiKeysProvider(companyId));
    final changes = ref.watch(apiChangesProvider(companyId));
    final base = ref.watch(openApiBaseUrlProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(tr('API keys'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('api-key-new'),
        icon: const Icon(Icons.add),
        label: Text(tr('New key')),
        onPressed: () => _create(context, ref),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
        children: [
          Text(
            tr('Let your accounts software, a BI dashboard, Zapier or Make read this company\'s sites, tasks, reports, RFIs, defects and bills. A key reads only, unless you let it add and change tasks and issues.'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          SelectableText(base, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          ...switch (keys) {
            AsyncData(:final value) when value.isEmpty => [Text(tr('No keys yet'), style: theme.textTheme.titleSmall)],
            AsyncData(:final value) => [
                for (final k in value)
                  Card(
                    key: Key('api-key-${k.id}'),
                    child: ListTile(
                      title: Text(k.name),
                      subtitle: Text([
                        '${k.prefix}…',
                        if (k.canWrite) tr('reads and writes') else tr('read only'),
                        if (k.revokedAt != null)
                          trf('revoked {day}', {'day': fmtDate(k.revokedAt!, short: true)})
                        else if (k.lastUsedAt != null)
                          trf('last used {day}', {'day': fmtDate(k.lastUsedAt!, short: true)})
                        else
                          tr('not used yet'),
                      ].join(' · ')),
                      trailing: k.revokedAt != null
                          ? null
                          : TextButton(
                              key: Key('api-key-revoke-${k.id}'),
                              onPressed: () => _revoke(context, ref, k),
                              child: Text(tr('Revoke')),
                            ),
                    ),
                  ),
              ],
            AsyncError(:final error) => [Text(trf('Could not load the keys: {error}', {'error': '$error'}))],
            _ => [const Center(child: CircularProgressIndicator())],
          },
          if (changes case AsyncData(:final value) when value.isNotEmpty) ...[
            const SectionHeader('Changed through the API', padding: EdgeInsets.fromLTRB(0, 20, 0, 4)),
            for (final c in value)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 20),
                title: Text(_changeLabel(c)),
                subtitle: Text(fmtDate(c.at, short: true)),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    var write = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('New key')),
        scrollable: true,
        content: StatefulBuilder(
          builder: (ctx, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('api-key-name'),
              controller: name,
              maxLength: 60,
              decoration: InputDecoration(labelText: tr('What it is for'), hintText: tr('e.g. Accounts software')),
            ),
            SwitchListTile(
              key: const Key('api-key-write'),
              contentPadding: EdgeInsets.zero,
              value: write,
              onChanged: (v) => setState(() => write = v),
              title: Text(tr('Can also add and change tasks and issues')),
              subtitle: Text(tr('Needed for Zapier or Make to send records in, or to set up webhooks')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('api-key-create'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Make key'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final key = await ref.read(apiKeysServiceProvider).create(companyId, name.text, write: write);
      ref.invalidate(apiKeysProvider(companyId));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Copy the key now')),
          scrollable: true,
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(write
                ? tr('It is shown only this once. Anyone with it can read this company\'s records and add or change tasks and issues, so keep it in the other software only.')
                : tr('It is shown only this once. Anyone with it can read this company\'s records, so keep it in the other software only.')),
            const SizedBox(height: 12),
            SelectableText(key, key: const Key('api-key-plain')),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: key));
                showSnack(ctx, tr('Copied'));
              },
              child: Text(tr('Copy')),
            ),
            FilledButton(key: const Key('api-key-done'), onPressed: () => Navigator.pop(ctx), child: Text(tr('Done'))),
          ],
        ),
      );
    } on PostgrestException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, ApiKey k) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trf('Revoke {name}?', {'name': k.name})),
        content: Text(tr('Software using this key stops getting data straight away. This cannot be undone.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('api-key-revoke-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Revoke'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(apiKeysServiceProvider).revoke(k.id);
      ref.invalidate(apiKeysProvider(companyId));
    } catch (e) {
      if (context.mounted) showSnack(context, trf('Could not save: {error}', {'error': '$e'}), error: true);
    }
  }
}
