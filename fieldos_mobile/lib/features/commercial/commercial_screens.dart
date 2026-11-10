/// One site's commercial controls: work orders and the certification of
/// subcontractor claims (FOS-201), the variation register (FOS-202) and
/// budget lines with commitments and cost to complete (FOS-203).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/commercial/commercial_data.dart';
import 'package:fieldos_mobile/features/commercial/commercial_pack.dart';
import 'package:fieldos_mobile/features/commercial/commercial_rules.dart';
import 'package:fieldos_mobile/features/commercial/commercial_widgets.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/shared/photo_capture.dart';
import 'package:fieldos_mobile/features/shared/photo_viewer.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Who is using the screen, and what they may do.
class _Me {
  _Me(this.userId, this.role);
  final String userId;
  final String? role;
  bool get canDecide => Roles.canApprove(role);
  bool get canWrite => role != null && Roles.canWrite(role!);
}

_Me _me(WidgetRef ref) {
  final s = ref.read(sessionProvider);
  return _Me(s.user!.id, s.role);
}

Map<String, String> _names(WidgetRef ref, String companyId) =>
    ref.watch(closeNamesProvider(companyId)).value ?? const {};

String _who(Map<String, String> names, String? id) =>
    id == null ? tr('Someone on the team') : names[id] ?? tr('Someone on the team');

void _refresh(WidgetRef ref, String projectId) => ref.invalidate(commercialDataProvider(projectId));

// ---------------------------------------------------------------------------
// The site's commercial screen: three tabs
// ---------------------------------------------------------------------------

class CommercialScreen extends ConsumerWidget {
  const CommercialScreen({super.key, required this.project, this.initialTab = 0});
  final Project project;
  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(commercialDataProvider(project.id));
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(trf('{site}: contracts and cost', {'site': project.name})),
          bottom: TabBar(isScrollable: true, tabs: [
            Tab(text: tr('Work orders')),
            Tab(text: tr('Variations')),
            Tab(text: tr('Cost to complete')),
          ]),
        ),
        body: data.when(
          data: (d) => TabBarView(children: [
            _WorkOrdersTab(project: project, data: d),
            _VariationsTab(project: project, data: d),
            _CostTab(project: project, data: d),
          ]),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => ErrorState(error: e, stack: st),
        ),
      ),
    );
  }
}

// --- Work orders -------------------------------------------------------------

class _WorkOrdersTab extends ConsumerWidget {
  const _WorkOrdersTab({required this.project, required this.data});
  final Project project;
  final CommercialData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = _me(ref);
    final orders = data.workOrders;
    return Scaffold(
      body: orders.isEmpty
          ? EmptyState(
              icon: Icons.handshake_outlined,
              title: tr('No work orders yet'),
              message: tr('A work order is what you agreed with a subcontractor: the work, the quantity and the rate. '
                  'Claims and certificates are checked against it.'),
              actionLabel: me.canDecide ? tr('New work order') : null,
              onAction: me.canDecide ? () => _newWorkOrder(context, ref) : null,
            )
          : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
              for (final o in orders) _WorkOrderCard(project: project, data: data, order: o),
            ]),
      floatingActionButton: me.canDecide && orders.isNotEmpty
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(tr('New work order')),
              onPressed: () => _newWorkOrder(context, ref),
            )
          : null,
    );
  }

  Future<void> _newWorkOrder(BuildContext context, WidgetRef ref) async {
    final db = ref.read(appDatabaseProvider);
    final subs = await db.subcontractorDao.forCompany(project.companyId);
    if (!context.mounted) return;
    if (subs.isEmpty) {
      showSnack(context, tr('Add the subcontractor first, from Home > Subcontractors.'), error: true);
      return;
    }
    final desc = TextEditingController();
    final unit = TextEditingController(text: 'm²');
    final qty = TextEditingController();
    final rate = TextEditingController();
    String sub = subs.first.id;
    String? code;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('New work order')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: sub,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Subcontractor')),
                items: [for (final s in subs) DropdownMenuItem(value: s.id, child: Text(s.name))],
                onChanged: (v) => set(() => sub = v ?? sub),
              ),
              TextField(controller: desc, decoration: InputDecoration(labelText: tr('Work (e.g. Internal plaster, Block A)'))),
              Row(children: [
                Expanded(child: NumField(controller: qty, label: tr('Agreed quantity'))),
                const SizedBox(width: 8),
                SizedBox(width: 80, child: TextField(controller: unit, decoration: InputDecoration(labelText: tr('Unit')))),
              ]),
              NumField(controller: rate, label: tr('Rate per unit'), suffix: '₹'),
              CostCodePicker(codes: data.costCodes, value: code, onChanged: (v) => set(() => code = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final q = parseNum(qty.text), r = parseNum(rate.text);
    if (desc.text.trim().isEmpty || q == null || q <= 0 || r == null || r < 0 || unit.text.trim().isEmpty) {
      showSnack(context, tr('Enter the work, the agreed quantity, the unit and the rate.'), error: true);
      return;
    }
    await db.commercialDao.createWorkOrder(
        projectId: project.id, subcontractorId: sub, description: desc.text, unit: unit.text, qty: q, rate: r, costCodeId: code);
    _refresh(ref, project.id);
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({required this.project, required this.data, required this.order});
  final Project project;
  final CommercialData data;
  final WorkOrder order;

  @override
  Widget build(BuildContext context) {
    final pos = data.position(order);
    final claims = data.claims.where((c) => c.workOrderId == order.id).map(data.claim).toList();
    final toDo = claims.where((c) => !c.settled && !c.heldForVariation).length;
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => WorkOrderScreen(project: project, orderId: order.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(order.description, style: theme.textTheme.titleSmall)),
              if (toDo > 0) StatusPill(trf('{n} to certify', {'n': toDo}), tone: PillTone.warn),
            ]),
            Text(data.subcontractorNames[order.subcontractorId] ?? '', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            if (!pos.hasBaseline)
              Text(tr('No agreed quantity yet (an older work order).'), style: theme.textTheme.bodySmall)
            else ...[
              LinearProgressIndicator(value: pos.currentQty == 0 ? 0 : (pos.certifiedQty / pos.currentQty).clamp(0, 1)),
              const SizedBox(height: 6),
              Text(
                trf('{done} of {total} certified · {money} of {value}', {
                  'done': fmtQty(pos.certifiedQty),
                  'total': qtyUnit(pos.currentQty, order.unit),
                  'money': rupees(pos.certifiedValue),
                  'value': rupees(pos.currentValue),
                }),
                style: theme.textTheme.bodySmall,
              ),
              if (pos.approvedVariationQty > 0)
                Text(trf('Agreed {base}, plus {extra} by approved variations',
                        {'base': qtyUnit(pos.baselineQty, order.unit), 'extra': qtyUnit(pos.approvedVariationQty, order.unit)}),
                    style: theme.textTheme.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }
}

/// One work order: the agreement, the claims against it and the
/// certificates, with what is left.
class WorkOrderScreen extends ConsumerWidget {
  const WorkOrderScreen({super.key, required this.project, required this.orderId, this.openClaimId});
  final Project project;
  final String orderId;

  /// Opens the certification sheet for this claim (from the inbox).
  final String? openClaimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commercialDataProvider(project.id));
    final names = _names(ref, project.companyId);
    return async.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: ErrorState(error: e, stack: st)),
      data: (d) {
        final order = d.orderById(orderId);
        if (order == null) return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('This work order is no longer on the phone.'))));
        final pos = d.position(order);
        final claims = d.claims.where((c) => c.workOrderId == order.id).toList().reversed.toList();
        final me = _me(ref);
        return Scaffold(
          appBar: AppBar(
            title: Text(order.description),
            actions: [
              IconButton(
                tooltip: tr('Share statement'),
                icon: const Icon(Icons.ios_share),
                onPressed: () => _share(context, ref, d, order, names),
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 88), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.subcontractorNames[order.subcontractorId] ?? '', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  KeyValue(tr('Agreed (baseline)'), '${qtyUnit(pos.baselineQty, order.unit)} · ${rupees(pos.baselineValue)}'),
                  KeyValue(tr('Approved variations'),
                      '${qtyUnit(pos.approvedVariationQty, order.unit)} · ${rupees(pos.approvedVariationValue)}'),
                  KeyValue(tr('Current order'), '${qtyUnit(pos.currentQty, order.unit)} · ${rupees(pos.currentValue)}', strong: true),
                  KeyValue(tr('Rate'), rupees(pos.rate, paise: true)),
                  const Divider(),
                  KeyValue(tr('Certified to date'), '${qtyUnit(pos.certifiedQty, order.unit)} · ${rupees(pos.certifiedValue)}',
                      strong: true),
                  KeyValue(tr('Left on the order'), '${qtyUnit(pos.remainingQty, order.unit)} · ${rupees(pos.openCommitment)}'),
                  if (pos.pendingVariationQty > 0)
                    KeyValue(tr('Waiting in variations'), qtyUnit(pos.pendingVariationQty, order.unit)),
                ]),
              ),
            ),
            SectionHeader(tr('Claims and certificates')),
            if (claims.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(tr('No claims yet.'))),
            for (final c in claims) _ClaimCard(project: project, data: d, claim: c, names: names, canCertify: me.canWrite),
          ]),
          floatingActionButton: me.canWrite
              ? FloatingActionButton.extended(
                  icon: const Icon(Icons.playlist_add),
                  label: Text(tr('Record a claim')),
                  onPressed: () => recordClaim(context, ref, order, by: me.userId),
                )
              : null,
        );
      },
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref, CommercialData d, WorkOrder order, Map<String, String> names) async {
    try {
      final company = ref.read(sessionProvider).activeCompany;
      final branding = await loadBranding(ref.read(appDatabaseProvider), project.companyId);
      final pdf = await buildWorkOrderStatement(
          data: d, order: order, companyName: company?.name ?? '', siteName: project.name, names: names, branding: branding);
      final dir = await getTemporaryDirectory();
      final safe = order.description.replaceAll(RegExp(r'[^\w]+'), '_');
      final pdfFile = File('${dir.path}/work_order_$safe.pdf')..writeAsBytesSync(pdf);
      final csvFile = File('${dir.path}/work_order_$safe.csv')..writeAsStringSync(workOrderStatementCsv(d, order, names: names));
      await SharePlus.instance.share(ShareParams(
        files: [XFile(pdfFile.path), XFile(csvFile.path)],
        text: trf('{site}: work order statement, {work}', {'site': project.name, 'work': order.description}),
      ));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }
}

/// Claim completed work against [order] (the subcontractor, or the
/// engineer on their behalf), with photos.
Future<void> recordClaim(BuildContext context, WidgetRef ref, WorkOrder order, {required String by}) async {
  final qty = TextEditingController();
  final where = TextEditingController();
  final note = TextEditingController();
  final photos = <String>[];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: Text(tr('Claim completed work')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(order.description),
            NumField(controller: qty, label: tr('Quantity completed'), suffix: order.unit),
            TextField(controller: where, decoration: InputDecoration(labelText: tr('Where (block, floor, grid)'))),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
            const SizedBox(height: 8),
            if (photos.isNotEmpty) PhotoStrip(paths: photos, size: 64),
            TextButton.icon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(photos.isEmpty ? tr('Add a photo of the work') : tr('Add another photo')),
              onPressed: () async {
                final p = await captureCameraFirst(ctx, prefix: 'claim', place: order.description);
                if (p != null) set(() => photos.add(p));
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Submit claim'))),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final q = parseNum(qty.text);
  if (q == null || q <= 0) {
    showSnack(context, tr('Enter the quantity completed.'), error: true);
    return;
  }
  await ref
      .read(appDatabaseProvider)
      .commercialDao
      .submitClaim(workOrderId: order.id, qty: q, by: by, location: where.text, note: note.text, photos: photos);
  _refresh(ref, order.projectId);
  if (context.mounted) showSnack(context, tr('Claim submitted. The site engineer will certify it.'));
}

class _ClaimCard extends ConsumerWidget {
  const _ClaimCard({required this.project, required this.data, required this.claim, required this.names, required this.canCertify});
  final Project project;
  final CommercialData data;
  final WorkClaim claim;
  final Map<String, String> names;
  final bool canCertify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = data.orderById(claim.workOrderId)!;
    final c = data.claim(claim);
    final (label, tone) = claimPill(c);
    final photos = data.photosOf(claim.id).map((a) => a.filePath).toList();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(trf('Claimed {qty}', {'qty': qtyUnit(claim.qty, order.unit)}), style: theme.textTheme.titleSmall),
            ),
            StatusPill(label, tone: tone),
          ]),
          Text('${_who(names, claim.submittedBy)} · ${fmtDateTime(claim.createdAt)}'
              '${claim.location == null ? '' : ' · ${claim.location}'}', style: theme.textTheme.bodySmall),
          if ((claim.note ?? '').isNotEmpty) Text('"${claim.note}"', style: theme.textTheme.bodySmall),
          if (photos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: PhotoStrip(paths: photos, size: 56)),
          for (final cert in c.certifications)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${data.certificateNo(cert)}: ${[
                  if (cert.acceptedQty > 0) trf('accepted {q}', {'q': qtyUnit(cert.acceptedQty, order.unit)}),
                  if (cert.rejectedQty > 0) trf('rejected {q}', {'q': qtyUnit(cert.rejectedQty, order.unit)}),
                  if (data.variationById(cert.variationId) != null) data.variationNo(data.variationById(cert.variationId)!),
                ].join(', ')} · ${_who(names, cert.certifiedBy)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Wrap(spacing: 8, children: [
            TextButton.icon(
              icon: const Icon(Icons.timeline),
              label: Text(tr('Trace')),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ClaimTraceScreen(project: project, claimId: claim.id))),
            ),
            if (canCertify && !c.settled && !c.heldForVariation)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.verified_outlined),
                label: Text(c.eligibleAfterApproval ? tr('Certify the approved quantity') : tr('Certify')),
                onPressed: () => certifyClaim(context, ref, data, claim),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// The engineer's certification: accepted, rejected, and (by default)
/// what is beyond the order sent to the variation register.
Future<void> certifyClaim(BuildContext context, WidgetRef ref, CommercialData d, WorkClaim claim) async {
  final order = d.orderById(claim.workOrderId)!;
  final pos = d.position(order);
  final cp = d.claim(claim);
  final split = suggestedSplit(pos, cp);
  final accepted = TextEditingController(text: fmtQty(split.accept));
  final rejected = TextEditingController(text: '0');
  final note = TextEditingController();
  final photos = <String>[];
  var toVariation = split.hold > 0 && !cp.eligibleAfterApproval;
  final me = _me(ref);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final a = parseNum(accepted.text) ?? 0, r = parseNum(rejected.text) ?? 0;
      final rest = (cp.open - a - r);
      return AlertDialog(
        title: Text(tr('Certify claim')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            KeyValue(tr('Claimed'), qtyUnit(claim.qty, order.unit)),
            KeyValue(tr('Still to decide on this claim'), qtyUnit(cp.open, order.unit)),
            KeyValue(tr('Left on the order'), qtyUnit(pos.remainingQty, order.unit), strong: true),
            NumField(controller: accepted, label: tr('Accepted'), suffix: order.unit, onChanged: (_) => set(() {})),
            NumField(controller: rejected, label: tr('Rejected'), suffix: order.unit, onChanged: (_) => set(() {})),
            if (rest > 0.0005)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: toVariation,
                onChanged: cp.eligibleAfterApproval ? null : (v) => set(() => toVariation = v),
                title: Text(trf('Send the other {q} to the variation register', {'q': qtyUnit(rest, order.unit)})),
                subtitle: Text(toVariation
                    ? tr('It waits there for the project manager. If approved, it can be certified.')
                    : tr('It stays on the claim, to decide later.')),
              ),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Reason or note'))),
            const SizedBox(height: 8),
            if (photos.isNotEmpty) PhotoStrip(paths: photos, size: 56),
            TextButton.icon(
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(tr('Add evidence photo')),
              onPressed: () async {
                final p = await captureCameraFirst(ctx, prefix: 'certification', place: order.description);
                if (p != null) set(() => photos.add(p));
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Certify'))),
        ],
      );
    }),
  );
  if (ok != true || !context.mounted) return;
  final a = parseNum(accepted.text) ?? 0, r = parseNum(rejected.text) ?? 0;
  try {
    await ref.read(appDatabaseProvider).commercialDao.certify(
          claimId: claim.id,
          accepted: a,
          rejected: r,
          by: me.userId,
          note: note.text,
          raiseVariation: toVariation,
          againstVariationId: cp.eligibleAfterApproval ? cp.variation!.id : null,
          photos: photos,
        );
    _refresh(ref, order.projectId);
    if (context.mounted) {
      showSnack(context, toVariation ? tr('Certified. The rest is in the variation register.') : tr('Certified.'));
    }
  } on CertificationRefused catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  }
}

/// From the agreement to the payment, with the site evidence.
class ClaimTraceScreen extends ConsumerWidget {
  const ClaimTraceScreen({super.key, required this.project, required this.claimId});
  final Project project;
  final String claimId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commercialDataProvider(project.id));
    final names = _names(ref, project.companyId);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Trace'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (d) {
          final claim = d.claimById(claimId);
          if (claim == null) return Center(child: Text(tr('This claim is no longer on the phone.')));
          final steps = traceClaim(d, claim);
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final s in steps)
              Card(
                child: ListTile(
                  leading: Icon(switch (s.kind) {
                    TraceKind.agreed => Icons.handshake_outlined,
                    TraceKind.claimed => Icons.engineering_outlined,
                    TraceKind.certified => Icons.verified_outlined,
                    TraceKind.variationRaised => Icons.call_split,
                    TraceKind.variationDecided => Icons.gavel_outlined,
                  }),
                  title: Text(_traceTitle(s.kind)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.english),
                    Text('${s.who == null ? '' : '${_who(names, s.who)} · '}${fmtDateTime(s.at)}'),
                    if ((s.note ?? '').isNotEmpty) Text('"${s.note}"'),
                    if (s.photoParentId != null && d.photosOf(s.photoParentId!).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: PhotoStrip(paths: d.photosOf(s.photoParentId!).map((a) => a.filePath).toList(), size: 56),
                      ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

String _traceTitle(TraceKind k) => switch (k) {
      TraceKind.agreed => tr('Agreed'),
      TraceKind.claimed => tr('Claimed by the subcontractor'),
      TraceKind.certified => tr('Certified by the site'),
      TraceKind.variationRaised => tr('Sent to the variation register'),
      TraceKind.variationDecided => tr('Variation decided'),
    };

// --- Variations ----------------------------------------------------------------

class _VariationsTab extends ConsumerStatefulWidget {
  const _VariationsTab({required this.project, required this.data});
  final Project project;
  final CommercialData data;

  @override
  ConsumerState<_VariationsTab> createState() => _VariationsTabState();
}

class _VariationsTabState extends ConsumerState<_VariationsTab> {
  VariationState _show = VariationState.pending;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final me = _me(ref);
    final list = d.variations.where((v) => variationState(v, d.decisionByVariation) == _show).toList().reversed.toList();
    return Scaffold(
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        SegmentedButton<VariationState>(
          segments: [
            for (final s in VariationState.values)
              ButtonSegment(
                value: s,
                label: Text('${variationPill(s).$1} (${d.variations.where((v) => variationState(v, d.decisionByVariation) == s).length})'),
              ),
          ],
          selected: {_show},
          onSelectionChanged: (s) => setState(() => _show = s.first),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_show == VariationState.pending
                ? tr('No variations waiting. A claim beyond its order, a client instruction or a design change goes here.')
                : tr('None yet.')),
          ),
        for (final v in list)
          Card(
            child: ListTile(
              title: Text('${d.variationNo(v)} ${v.title}'),
              subtitle: Text([
                originLabel(v.origin),
                rupees(d.decisionByVariation[v.id]?.approvedCost ?? v.estimatedCost),
                if (v.scheduleDays != 0) trf('{n} days', {'n': v.scheduleDays}),
              ].join(' · ')),
              trailing: StatusPill(variationPill(variationState(v, d.decisionByVariation)).$1,
                  tone: variationPill(variationState(v, d.decisionByVariation)).$2),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VariationScreen(project: widget.project, variationId: v.id))),
            ),
          ),
      ]),
      floatingActionButton: me.canWrite
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(tr('Raise variation')),
              onPressed: () => _raise(context),
            )
          : null,
    );
  }

  Future<void> _raise(BuildContext context) async {
    final d = widget.data;
    final title = TextEditingController();
    final qty = TextEditingController();
    final cost = TextEditingController();
    final days = TextEditingController(text: '0');
    final note = TextEditingController();
    String origin = 'client_instruction';
    String? order;
    String? code;
    final photos = <String>[];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Raise variation')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: InputDecoration(labelText: tr('What changed'))),
              DropdownButtonFormField<String>(
                initialValue: origin,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Where it came from')),
                items: [for (final o in variationOrigins) DropdownMenuItem(value: o, child: Text(originLabel(o)))],
                onChanged: (v) => set(() => origin = v ?? origin),
              ),
              DropdownButtonFormField<String?>(
                initialValue: order,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('Work order it changes')),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('None (budget only)'))),
                  for (final o in d.workOrders) DropdownMenuItem(value: o.id, child: Text(o.description, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => set(() {
                  order = v;
                  final wo = d.orderById(v);
                  if (wo != null) code = wo.costCodeId;
                }),
              ),
              if (order != null)
                NumField(
                  controller: qty,
                  label: tr('Quantity'),
                  suffix: d.orderById(order)?.unit,
                  onChanged: (s) {
                    final rate = workOrderRate(d.orderById(order)!);
                    final q = parseNum(s);
                    if (rate != null && q != null) cost.text = (q * rate).toStringAsFixed(0);
                  },
                ),
              NumField(controller: cost, label: tr('Estimated cost'), suffix: '₹'),
              NumField(controller: days, label: tr('Effect on programme (days)')),
              if (order == null) CostCodePicker(codes: d.costCodes, value: code, onChanged: (v) => set(() => code = v)),
              TextField(controller: note, decoration: InputDecoration(labelText: tr('Note (optional)'))),
              if (photos.isNotEmpty) PhotoStrip(paths: photos, size: 56),
              TextButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(tr('Add evidence photo')),
                onPressed: () async {
                  final p = await captureCameraFirst(ctx, prefix: 'variation');
                  if (p != null) set(() => photos.add(p));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (title.text.trim().isEmpty) {
      showSnack(context, tr('Say what changed.'), error: true);
      return;
    }
    final me = _me(ref);
    await ref.read(appDatabaseProvider).commercialDao.raiseVariationRow(
          projectId: widget.project.id,
          title: title.text,
          origin: origin,
          by: me.userId,
          ownerId: me.userId,
          workOrderId: order,
          costCodeId: code,
          qty: order == null ? null : parseNum(qty.text),
          unit: d.orderById(order)?.unit,
          estimatedCost: parseNum(cost.text) ?? 0,
          scheduleDays: int.tryParse(days.text.trim()) ?? 0,
          note: note.text,
          photos: photos,
        );
    _refresh(ref, widget.project.id);
  }
}

/// One variation: where it came from, the evidence, the forecast impact,
/// and the decision.
class VariationScreen extends ConsumerWidget {
  const VariationScreen({super.key, required this.project, required this.variationId});
  final Project project;
  final String variationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commercialDataProvider(project.id));
    final names = _names(ref, project.companyId);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Variation'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (d) {
          final v = d.variationById(variationId);
          if (v == null) return Center(child: Text(tr('This variation is no longer on the phone.')));
          final state = variationState(v, d.decisionByVariation);
          final dec = d.decisionByVariation[v.id];
          final order = d.orderById(v.workOrderId);
          final claim = d.claimById(v.sourceClaimId);
          final codeId = d.variationCostCode(v);
          final line = d.costReport().lines.where((l) => l.costCode?.id == codeId).firstOrNull;
          final me = _me(ref);
          final photos = [
            ...d.photosOf(v.id),
            if (claim != null) ...d.photosOf(claim.id),
          ].map((a) => a.filePath).toList();
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${d.variationNo(v)} ${v.title}', style: Theme.of(context).textTheme.titleMedium)),
                    StatusPill(variationPill(state).$1, tone: variationPill(state).$2),
                  ]),
                  const SizedBox(height: 6),
                  KeyValue(tr('Where it came from'), originLabel(v.origin)),
                  KeyValue(tr('Raised by'), '${_who(names, v.raisedBy)} · ${fmtDate(v.createdAt)}'),
                  KeyValue(tr('Owner'), _who(names, v.ownerId ?? v.raisedBy)),
                  if (order != null) KeyValue(tr('Work order'), order.description),
                  if (v.qty != null) KeyValue(tr('Quantity'), qtyUnit(v.qty!, v.unit)),
                  KeyValue(tr('Estimated cost'), rupees(v.estimatedCost)),
                  KeyValue(tr('Effect on programme'), trf('{n} days', {'n': v.scheduleDays})),
                  if ((v.note ?? '').isNotEmpty) Text('"${v.note}"'),
                ]),
              ),
            ),
            if (photos.isNotEmpty) ...[
              SectionHeader(tr('Site evidence')),
              PhotoStrip(paths: photos),
            ],
            if (line != null) ...[
              SectionHeader(tr('Forecast impact')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    KeyValue(tr('Budget line'), line.costCode == null ? tr('Not on a budget line') : '${line.costCode!.code} ${line.costCode!.name}'),
                    KeyValue(tr('Budget (with approved changes)'), rupees(line.revisedBudget)),
                    KeyValue(tr('Projected final cost'), rupees(line.projectedFinal), strong: true),
                    if (state == VariationState.pending)
                      KeyValue(tr('If this is approved'), rupees(line.projectedFinal + v.estimatedCost)),
                  ]),
                ),
              ),
            ],
            if (claim != null)
              ListTile(
                leading: const Icon(Icons.timeline),
                title: Text(tr('Trace back to the claim')),
                subtitle: Text(trf('Claimed {qty} on {date}', {'qty': qtyUnit(claim.qty, order?.unit), 'date': fmtDate(claim.createdAt)})),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ClaimTraceScreen(project: project, claimId: claim.id))),
              ),
            if (dec != null) ...[
              SectionHeader(tr('Decision')),
              Card(
                child: ListTile(
                  title: Text(dec.decision == 'approved'
                      ? trf('Approved: {qty}, {money}', {'qty': qtyUnit(dec.approvedQty ?? 0, v.unit), 'money': rupees(dec.approvedCost ?? 0)})
                      : tr('Rejected')),
                  subtitle: Text('${_who(names, dec.decidedBy)} · ${fmtDateTime(dec.createdAt)}'
                      '${(dec.note ?? '').isEmpty ? '' : '\n"${dec.note}"'}'),
                ),
              ),
            ] else if (me.canDecide) ...[
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => _decide(context, ref, v, approve: false), child: Text(tr('Reject'))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: () => _decide(context, ref, v, approve: true), child: Text(tr('Approve'))),
                ),
              ]),
            ] else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(tr('Waiting for the owner or a project manager to decide.')),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Variation v, {required bool approve}) async {
    final qty = TextEditingController(text: v.qty == null ? '' : fmtQty(v.qty!));
    final cost = TextEditingController(text: v.estimatedCost.toStringAsFixed(0));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? tr('Approve variation') : tr('Reject variation')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (approve && v.qty != null) NumField(controller: qty, label: tr('Approved quantity'), suffix: v.unit),
            if (approve) NumField(controller: cost, label: tr('Approved amount'), suffix: '₹'),
            TextField(controller: note, decoration: InputDecoration(labelText: tr('Reason or note'))),
            const SizedBox(height: 8),
            Text(tr('A decision cannot be changed afterwards.'), style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? tr('Approve') : tr('Reject'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(appDatabaseProvider).commercialDao.decideVariation(
            variationId: v.id,
            approve: approve,
            by: _me(ref).userId,
            approvedQty: approve ? parseNum(qty.text) : null,
            approvedCost: approve ? parseNum(cost.text) : null,
            note: note.text,
          );
      _refresh(ref, v.projectId);
    } on CertificationRefused catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }
}

// --- Cost to complete ------------------------------------------------------

class _CostTab extends ConsumerWidget {
  const _CostTab({required this.project, required this.data});
  final Project project;
  final CommercialData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = data.costReport();
    final total = report.total;
    final me = _me(ref);
    return Scaffold(
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        _CostCard(line: total, title: tr('Whole site'), onTap: null),
        if (report.lines.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('Add budget lines (cost codes) with their original budget. Work orders, purchase orders and '
                'expenses put on a line show what is committed, what is spent and what the line will cost to finish.')),
          ),
        for (final l in report.lines)
          _CostCard(
            line: l,
            title: l.costCode == null ? tr('Not on a budget line') : '${l.costCode!.code} ${l.costCode!.name}',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CostLineScreen(project: project, costCodeId: l.costCode?.id))),
          ),
      ]),
      floatingActionButton: me.canDecide
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: Text(tr('Budget line')),
              onPressed: () => _addLine(context, ref),
            )
          : null,
    );
  }

  Future<void> _addLine(BuildContext context, WidgetRef ref) async {
    final code = TextEditingController();
    final name = TextEditingController();
    final budget = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('New budget line')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, decoration: InputDecoration(labelText: tr('Code (e.g. 04-PL)'))),
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Name (e.g. Internal plaster)'))),
          NumField(controller: budget, label: tr('Original budget'), suffix: '₹'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
      showSnack(context, tr('Enter a code and a name.'), error: true);
      return;
    }
    await ref.read(appDatabaseProvider).commercialDao.addCostCode(
        projectId: project.id, code: code.text, name: name.text, originalBudget: parseNum(budget.text) ?? 0);
    _refresh(ref, project.id);
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({required this.line, required this.title, required this.onTap});
  final CostLine line;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              if (line.revisedBudget > 0 || line.projectedFinal > 0)
                StatusPill(
                  line.isOver ? trf('{money} over', {'money': rupees(line.overrun)}) : tr('Within budget'),
                  tone: line.isOver ? PillTone.danger : PillTone.ok,
                ),
            ]),
            const SizedBox(height: 6),
            KeyValue(tr('Original budget'), rupees(line.originalBudget)),
            KeyValue(tr('Approved changes'), rupees(line.approvedChanges)),
            KeyValue(tr('Open commitments (POs and work orders)'), rupees(line.openCommitments)),
            KeyValue(tr('Actual cost'), rupees(line.actual)),
            KeyValue(tr('Estimated remaining'), rupees(line.estimatedRemaining)),
            KeyValue(tr('Projected final cost'), rupees(line.projectedFinal), strong: true),
            if (line.pendingChanges > 0)
              KeyValue(tr('Pending variations'), rupees(line.pendingChanges), color: toneColor(context, PillTone.warn)),
          ]),
        ),
      ),
    );
  }
}

/// One budget line, down to the records behind it.
class CostLineScreen extends ConsumerWidget {
  const CostLineScreen({super.key, required this.project, required this.costCodeId});
  final Project project;
  final String? costCodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(commercialDataProvider(project.id));
    final me = _me(ref);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Budget line'))),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (d) {
          final line = d.costReport().lines.where((l) => l.costCode?.id == costCodeId).firstOrNull;
          if (line == null) return Center(child: Text(tr('Nothing on this line yet.')));
          final code = line.costCode;
          return ListView(padding: const EdgeInsets.all(12), children: [
            _CostCard(line: line, title: code == null ? tr('Not on a budget line') : '${code.code} ${code.name}', onTap: null),
            if (code != null && me.canDecide)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(tr('Still to commit')),
                subtitle: Text(trf('{money}: material or work not yet ordered on this line', {'money': rupees(code.uncommittedEstimate)})),
                onTap: () async {
                  final v = await askText(context,
                      title: tr('Still to commit'), label: '₹', initial: code.uncommittedEstimate.toStringAsFixed(0));
                  final n = v == null ? null : parseNum(v);
                  if (n == null) return;
                  await ref.read(appDatabaseProvider).commercialDao.updateCostCode(code.id, uncommittedEstimate: n);
                  _refresh(ref, project.id);
                },
              ),
            if (code != null && me.canDecide)
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: Text(tr('Put orders and expenses on this line')),
                onTap: () => _assign(context, ref, d, code),
              ),
            SectionHeader(tr('Records behind these numbers')),
            for (final s in line.sources)
              Card(
                child: ListTile(
                  leading: Icon(switch (s.kind) {
                    CostSourceKind.workOrder => Icons.handshake_outlined,
                    CostSourceKind.purchaseOrder => Icons.local_shipping_outlined,
                    CostSourceKind.expense => Icons.receipt_long_outlined,
                    CostSourceKind.variation => Icons.call_split,
                  }),
                  title: Text(s.label),
                  subtitle: Text([
                    if (s.committed > 0) trf('committed {m}', {'m': rupees(s.committed)}),
                    if (s.actual > 0) trf('actual {m}', {'m': rupees(s.actual)}),
                    if (s.change != 0) trf('change {m}', {'m': rupees(s.change)}),
                  ].join(' · ')),
                  onTap: switch (s.kind) {
                    CostSourceKind.workOrder => () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => WorkOrderScreen(project: project, orderId: s.id))),
                    CostSourceKind.variation => () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => VariationScreen(project: project, variationId: s.id))),
                    _ => null,
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _assign(BuildContext context, WidgetRef ref, CommercialData d, CostCode code) async {
    final orders = d.purchaseOrders.where((o) => o.costCodeId == null).toList();
    final expenses = d.expenses.where((e) => e.costCodeId == null && !e.voided).toList();
    final pick = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(trf('Put on {code}', {'code': code.code})),
          content: SizedBox(
            width: double.maxFinite,
            child: orders.isEmpty && expenses.isEmpty
                ? Text(tr('Every order and expense of this site is already on a budget line.'))
                : ListView(shrinkWrap: true, children: [
                    for (final o in orders)
                      CheckboxListTile(
                        value: pick.contains('po:${o.id}'),
                        onChanged: (v) => set(() => v == true ? pick.add('po:${o.id}') : pick.remove('po:${o.id}')),
                        title: Text(o.poNumber ?? tr('Purchase order')),
                        subtitle: Text(rupees(o.totalAmount ?? 0)),
                      ),
                    for (final e in expenses)
                      CheckboxListTile(
                        value: pick.contains('ex:${e.id}'),
                        onChanged: (v) => set(() => v == true ? pick.add('ex:${e.id}') : pick.remove('ex:${e.id}')),
                        title: Text(e.paidTo ?? e.category),
                        subtitle: Text('${rupees(e.amount)} · ${e.incurredOn}'),
                      ),
                  ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final dao = ref.read(appDatabaseProvider).commercialDao;
    for (final k in pick) {
      final id = k.substring(3);
      if (k.startsWith('po:')) {
        await dao.setOrderCostCode(id, code.id);
      } else {
        await dao.setExpenseCostCode(id, code.id);
      }
    }
    _refresh(ref, project.id);
  }
}
