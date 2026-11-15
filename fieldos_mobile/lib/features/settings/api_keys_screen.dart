/// Settings > API keys (owner only, online): keys that let the company's
/// ERP, BI tool, Zapier or Make read its site records through the open API
/// (docs/OPEN_API.md). A key is shown once; the server keeps only its hash
/// (20261115000000_open_api.sql).
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
  const ApiKey({required this.id, required this.name, required this.prefix, required this.createdAt, this.lastUsedAt, this.revokedAt});
  final String id;
  final String name;
  final String prefix;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  static ApiKey fromRow(Map<String, dynamic> r) => ApiKey(
        id: r['id'] as String,
        name: r['name'] as String,
        prefix: r['key_prefix'] as String,
        createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
        lastUsedAt: r['last_used_at'] == null ? null : DateTime.parse(r['last_used_at'] as String).toLocal(),
        revokedAt: r['revoked_at'] == null ? null : DateTime.parse(r['revoked_at'] as String).toLocal(),
      );
}

class ApiKeysService {
  ApiKeysService(this.client);
  final SupabaseClient client;

  Future<List<ApiKey>> list(String companyId) async {
    final rows = await client
        .from('company_api_keys')
        .select('id, name, key_prefix, created_at, last_used_at, revoked_at')
        .eq('company_id', companyId)
        .order('created_at', ascending: false);
    return [for (final r in rows) ApiKey.fromRow(r)];
  }

  /// The new key, shown once.
  Future<String> create(String companyId, String name) async {
    final r = await client.rpc('create_company_api_key', params: {'p_company_id': companyId, 'p_name': name});
    return (r as Map<String, dynamic>)['key'] as String;
  }

  Future<void> revoke(String keyId) => client.rpc('revoke_company_api_key', params: {'p_key_id': keyId});
}

final apiKeysServiceProvider = Provider<ApiKeysService>((ref) => ApiKeysService(ref.watch(cloudSyncClientProvider)));

final apiKeysProvider =
    FutureProvider.autoDispose.family<List<ApiKey>, String>((ref, companyId) => ref.watch(apiKeysServiceProvider).list(companyId));

class ApiKeysScreen extends ConsumerWidget {
  const ApiKeysScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(apiKeysProvider(companyId));
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
            tr('Let your accounts software, a BI dashboard, Zapier or Make read this company\'s sites, tasks, reports, RFIs, defects and bills. Read only: a key cannot change anything.'),
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
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('New key')),
        content: TextField(
          key: const Key('api-key-name'),
          controller: name,
          maxLength: 60,
          decoration: InputDecoration(labelText: tr('What it is for'), hintText: tr('e.g. Accounts software')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('api-key-create'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Make key'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final key = await ref.read(apiKeysServiceProvider).create(companyId, name.text);
      ref.invalidate(apiKeysProvider(companyId));
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Copy the key now')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('It is shown only this once. Anyone with it can read this company\'s records, so keep it in the other software only.')),
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
