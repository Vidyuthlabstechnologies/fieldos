/// The builder's side of the free portals: share a supplier's or a site
/// client's code, and ask suppliers for a price in the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/portals/portal_service.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Signed in, and what is on this phone is on the server too.
Future<bool> _ready(BuildContext context, WidgetRef ref) async {
  final service = ref.read(cloudSyncServiceProvider);
  if (!service.isSignedIn) await service.restoreSession();
  if (!service.isSignedIn) {
    if (context.mounted) showSnack(context, tr('Turn on Team & sync first.'), error: true);
    return false;
  }
  await service.syncNow();
  return context.mounted;
}

Future<void> _showCode(BuildContext context, {required String title, required String code, required String about, required String share}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          SelectableText(code, key: const Key('portal-code-shown'), style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(about),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close'))),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: Text(tr('Share')),
            onPressed: () => SharePlus.instance.share(ShareParams(text: share)),
          ),
        ],
      ),
    );

Future<void> shareSupplierAccess(BuildContext context, WidgetRef ref, Supplier s) async {
  try {
    if (!await _ready(context, ref)) return;
    final code = await ref.read(portalServiceProvider).supplierCode(s.id);
    if (!context.mounted) return;
    await _showCode(
      context,
      title: trf('App access for {name}', {'name': s.name}),
      code: code,
      about: tr('Free for them. They see only the price requests you send them and their own orders.'),
      share: trf(
          '{name}: install FieldOS, tap "Supplier or client? Join free with the builder\'s code" and enter {code}. '
          'You can send your prices and tell us when an order is on its way.',
          {'name': s.name, 'code': code}),
    );
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}

Future<void> shareClientAccess(BuildContext context, WidgetRef ref, Project p) async {
  try {
    if (!await _ready(context, ref)) return;
    final code = await ref.read(portalServiceProvider).clientCode(p.id);
    if (!context.mounted) return;
    await _showCode(
      context,
      title: trf('Share {site} with the client', {'site': p.name}),
      code: code,
      about: tr('Free for them. They see this site\'s progress, daily updates with photos, bills and payments. '
          'Not costs, suppliers or other sites.'),
      share: trf(
          'Follow {site} on FieldOS: install it, tap "Supplier or client? Join free with the builder\'s code" and '
          'enter {code}. You will see the progress, photos, bills and payments.',
          {'site': p.name, 'code': code}),
    );
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}

/// Ticks the suppliers to ask for a price on [request]; they see it in
/// their free FieldOS once they have joined with their code.
Future<void> askSuppliersInApp(BuildContext context, WidgetRef ref,
    {required PurchaseRequest request, required List<Supplier> suppliers}) async {
  if (suppliers.isEmpty) {
    showSnack(context, tr('Add your suppliers first.'), error: true);
    return;
  }
  final picked = <String>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Ask for a price in the app')),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            Text(trf('{item}: they send their rate, and it shows here to compare.', {'item': request.materialName})),
            for (final s in suppliers)
              CheckboxListTile(
                key: Key('ask-${s.id}'),
                dense: true,
                value: picked.contains(s.id),
                title: Text(s.name),
                onChanged: (v) => set(() {
                  v == true ? picked.add(s.id) : picked.remove(s.id);
                }),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('ask-send'), onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Ask'))),
        ],
      ),
    ),
  );
  if (ok != true || picked.isEmpty || !context.mounted) return;
  try {
    if (!await _ready(context, ref)) return;
    final n = await ref.read(portalServiceProvider).inviteSuppliers(request.id, picked.toList());
    if (!context.mounted) return;
    showSnack(
        context,
        n == picked.length
            ? tr('Asked. They can send their price now.')
            : trf('Asked. {n} of them have the app; share the app code with the others from their supplier page.',
                {'n': n}));
  } catch (e, st) {
    if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
  }
}
