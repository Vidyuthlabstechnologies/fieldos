/// Leads and quotes: the work before a site exists. Owners and project
/// managers keep every enquiry with its next follow-up, log calls and
/// visits in a line, send a quotation PDF, and turn a won lead into a site
/// whose budget lines come from the accepted quote.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/close/week_close_screen.dart' show closeNamesProvider;
import 'package:fieldos_mobile/features/crm/crm_rules.dart';
import 'package:fieldos_mobile/features/crm/quote_editor_screen.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

typedef CrmData = ({List<CrmLead> leads, List<CrmQuote> quotes});

final crmDataProvider = FutureProvider.autoDispose.family<CrmData, String>((ref, companyId) async {
  final dao = ref.watch(appDatabaseProvider).crmDao;
  return (leads: await dao.leadsFor(companyId), quotes: await dao.quotesFor(companyId));
});

final leadActivitiesProvider = FutureProvider.autoDispose.family<List<CrmActivity>, String>(
    (ref, leadId) => ref.watch(appDatabaseProvider).crmDao.activitiesFor(leadId));

/// Open leads whose follow-up is today or earlier, for the Home menu.
final crmDueProvider = FutureProvider.autoDispose.family<int, String>((ref, companyId) async {
  final leads = await ref.watch(appDatabaseProvider).crmDao.leadsFor(companyId);
  final now = DateTime.now();
  return leads.where((l) => isFollowUpDue(l, now)).length;
});

void refreshCrm(WidgetRef ref, String companyId, [String? leadId]) {
  ref.invalidate(crmDataProvider(companyId));
  ref.invalidate(crmDueProvider(companyId));
  if (leadId != null) ref.invalidate(leadActivitiesProvider(leadId));
}

PillTone stageTone(String stage) => switch (stage) {
      'won' => PillTone.ok,
      'lost' => PillTone.danger,
      'negotiation' || 'quoted' => PillTone.warn,
      _ => PillTone.neutral,
    };

String _followUpText(CrmLead l, DateTime now) {
  if (!isOpenStage(l.stage)) return '';
  final f = l.nextFollowUp;
  if (f == null) return tr('No next step set');
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(f.year, f.month, f.day)).inDays;
  if (days > 0) return days == 1 ? tr('Follow-up 1 day late') : trf('Follow-up {n} days late', {'n': days});
  if (days == 0) return tr('Follow up today');
  return trf('Follow up {date}', {'date': fmtDate(f, short: true, now: now)});
}

class LeadsScreen extends ConsumerStatefulWidget {
  const LeadsScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<LeadsScreen> createState() => _LeadsScreenState();
}

enum _LeadFilter { followUp, open, won, lost }

class _LeadsScreenState extends ConsumerState<LeadsScreen> {
  _LeadFilter _filter = _LeadFilter.followUp;

  Future<void> _add() async {
    final lead = await showLeadForm(context, ref, companyId: widget.companyId);
    if (lead != null && mounted) {
      refreshCrm(ref, widget.companyId);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => LeadDetailScreen(companyId: widget.companyId, leadId: lead.id)));
      if (mounted) refreshCrm(ref, widget.companyId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(crmDataProvider(widget.companyId));
    return Scaffold(
      appBar: AppBar(title: Text(tr('Leads and quotes'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: Text(tr('New lead')),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => ErrorState(error: e, stack: st),
        data: (d) {
          final now = DateTime.now();
          if (d.leads.isEmpty) {
            return EmptyState(
              icon: Icons.handshake_outlined,
              title: tr('No leads yet'),
              message: tr('Add each enquiry the day it comes in: who asked, for what work, and when to call back. '
                  'Quotes, follow-ups and the reason a job was lost stay with it.'),
              actionLabel: tr('New lead'),
              onAction: _add,
            );
          }
          final monthStart = DateTime(now.year, now.month);
          final p = pipeline(d.leads, d.quotes, now: now, since: monthStart);
          final shown = switch (_filter) {
            _LeadFilter.followUp => workingOrder(d.leads.where((l) => isOpenStage(l.stage)).toList(), now)
                .where((l) => isFollowUpDue(l, now) || hasNoNextStep(l))
                .toList(),
            _LeadFilter.open => workingOrder(d.leads.where((l) => isOpenStage(l.stage)).toList(), now),
            _LeadFilter.won => d.leads.where((l) => l.stage == 'won').toList(),
            _LeadFilter.lost => d.leads.where((l) => l.stage == 'lost').toList(),
          };
          final byLead = <String, List<CrmQuote>>{};
          for (final q in d.quotes) {
            (byLead[q.leadId] ??= []).add(q);
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(crmDataProvider(widget.companyId).future),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
              _PipelineCard(p: p),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChoiceChip(
                  label: Text(trf('To follow up ({n})', {'n': p.dueToday + p.noNextStep})),
                  selected: _filter == _LeadFilter.followUp,
                  onSelected: (_) => setState(() => _filter = _LeadFilter.followUp),
                ),
                ChoiceChip(
                  label: Text(tr('All open')),
                  selected: _filter == _LeadFilter.open,
                  onSelected: (_) => setState(() => _filter = _LeadFilter.open),
                ),
                ChoiceChip(
                  label: Text(tr('Won')),
                  selected: _filter == _LeadFilter.won,
                  onSelected: (_) => setState(() => _filter = _LeadFilter.won),
                ),
                ChoiceChip(
                  label: Text(tr('Lost')),
                  selected: _filter == _LeadFilter.lost,
                  onSelected: (_) => setState(() => _filter = _LeadFilter.lost),
                ),
              ]),
              const SizedBox(height: 6),
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_filter == _LeadFilter.followUp
                      ? tr('Nothing to follow up today. Every open lead has a next step on a later day.')
                      : tr('Nothing here yet.')),
                ),
              for (final l in shown)
                Card(
                  child: ListTile(
                    title: Text(l.name),
                    subtitle: Text([
                      if ((l.workType ?? '').isNotEmpty) l.workType!,
                      if ((l.location ?? '').isNotEmpty) l.location!,
                      if (isOpenStage(l.stage)) _followUpText(l, now),
                      if (l.stage == 'lost' && (l.lostReason ?? '').isNotEmpty) l.lostReason!,
                    ].join(' · ')),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        StatusPill(leadStageLabels[l.stage]!, tone: stageTone(l.stage)),
                        const SizedBox(height: 4),
                        Text(rupees(leadValue(l, byLead[l.id] ?? const [])),
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LeadDetailScreen(companyId: widget.companyId, leadId: l.id)));
                      if (mounted) refreshCrm(ref, widget.companyId);
                    },
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _PipelineCard extends StatelessWidget {
  const _PipelineCard({required this.p});
  final Pipeline p;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = p.stages.where((s) => isOpenStage(s.stage)).fold<int>(0, (n, s) => n + s.count);
    Widget fig(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: theme.textTheme.titleMedium),
            Text(label, style: theme.textTheme.bodySmall),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            fig(trf('{n} open leads', {'n': open}), rupees(p.openValue)),
            fig(tr('Won this month'), rupees(p.wonValue)),
            fig(tr('Win rate'), p.winRate == null ? '-' : '${(p.winRate! * 100).round()}%'),
          ]),
          if (p.overdue > 0) ...[
            const SizedBox(height: 8),
            Text(trf('{n} follow-ups are late', {'n': p.overdue}),
                style: theme.textTheme.bodyMedium?.copyWith(color: toneColor(context, PillTone.danger))),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in p.stages.where((s) => isOpenStage(s.stage)))
              StatusPill('${tr(leadStageLabels[s.stage]!)} ${s.count}', tone: stageTone(s.stage)),
          ]),
          if (p.lostReasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              trf('Lost this month mostly to: {reason}', {'reason': p.lostReasons.first.$1}),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One lead
// ---------------------------------------------------------------------------

class LeadDetailScreen extends ConsumerWidget {
  const LeadDetailScreen({super.key, required this.companyId, required this.leadId});
  final String companyId;
  final String leadId;

  String _me(WidgetRef ref) => ref.read(sessionProvider).user!.id;

  Future<void> _call(BuildContext context, String phone, {bool whatsapp = false}) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final wa = digits.startsWith('+') ? digits.substring(1) : (digits.length == 10 ? '91$digits' : digits);
    final uri = whatsapp ? Uri.parse('https://wa.me/$wa') : Uri(scheme: 'tel', path: digits);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) showSnack(context, tr('Could not open the phone app.'), error: true);
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      refreshCrm(ref, companyId, leadId);
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  Future<void> _pickFollowUp(BuildContext context, WidgetRef ref, CrmLead lead) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: lead.nextFollowUp ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      helpText: tr('Next follow-up'),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(appDatabaseProvider).crmDao.setFollowUp(lead.id, picked));
  }

  Future<void> _lost(BuildContext context, WidgetRef ref, CrmLead lead) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mark as lost')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Why was it lost? This shows which reasons cost you the most jobs.')),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in lostReasonChoices)
              ActionChip(label: Text(tr(r)), onPressed: () => reason.text = tr(r)),
          ]),
          TextField(controller: reason, decoration: InputDecoration(labelText: tr('Reason')), maxLength: 300),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Mark as lost'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, ref,
        () => ref.read(appDatabaseProvider).crmDao.setStage(lead.id, 'lost', by: _me(ref), lostReason: reason.text));
  }

  Future<void> _won(BuildContext context, WidgetRef ref, CrmLead lead, List<CrmQuote> quotes) async {
    final live = quotes.where((q) => q.status != 'rejected').toList();
    final name = TextEditingController(text: (lead.location ?? '').isNotEmpty ? lead.location : lead.name);
    String? quoteId = (live.where((q) => q.status == 'accepted').firstOrNull ?? live.firstOrNull)?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('Won: make it a site')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('FieldOS makes the site with this client, and the quote\'s items become its budget lines.')),
              const SizedBox(height: 8),
              TextField(controller: name, decoration: InputDecoration(labelText: tr('Site name')), maxLength: 200),
              if (live.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(tr('Budget from quote'), style: Theme.of(ctx).textTheme.labelLarge),
                RadioGroup<String?>(
                  groupValue: quoteId,
                  onChanged: (v) => setState(() => quoteId = v),
                  child: Column(children: [
                    for (final q in live)
                      RadioListTile<String?>(
                        value: q.id,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${q.quoteNumber} · ${rupees(q.total)}'),
                      ),
                    RadioListTile<String?>(
                      value: null,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('No budget lines for now')),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Make the site'))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final project = await ref
          .read(appDatabaseProvider)
          .crmDao
          .convertToSite(leadId: lead.id, siteName: name.text, by: _me(ref), quoteId: quoteId);
      refreshCrm(ref, companyId, leadId);
      ref.invalidate(projectsProvider(companyId));
      if (!context.mounted) return;
      showSnack(context, trf('{site} is ready on Home', {'site': project.name}));
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
    } catch (e, st) {
      if (context.mounted) showSnack(context, friendlyError(e, st), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(crmDataProvider(companyId));
    final history = ref.watch(leadActivitiesProvider(leadId));
    final names = ref.watch(closeNamesProvider(companyId)).value ?? const <String, String>{};
    final theme = Theme.of(context);
    final now = DateTime.now();
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(appBar: AppBar(), body: ErrorState(error: e, stack: st)),
      data: (d) {
        final lead = d.leads.where((l) => l.id == leadId).firstOrNull;
        if (lead == null) {
          return Scaffold(appBar: AppBar(), body: Center(child: Text(tr('This lead is no longer on the phone.'))));
        }
        final quotes = d.quotes.where((q) => q.leadId == leadId).toList();
        final open = isOpenStage(lead.stage);
        Widget row(IconData icon, String label, String value, {VoidCallback? onTap}) => ListTile(
              dense: true,
              leading: Icon(icon),
              title: Text(label, style: theme.textTheme.bodySmall),
              subtitle: Text(value, style: theme.textTheme.bodyLarge),
              onTap: onTap,
            );
        return Scaffold(
          appBar: AppBar(
            title: Text(lead.name),
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'edit':
                      await showLeadForm(context, ref, companyId: companyId, lead: lead);
                      refreshCrm(ref, companyId, leadId);
                    case 'delete':
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(tr('Delete this lead?')),
                          content: Text(tr('Its history and quotes go with it.')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await _run(context, ref, () => ref.read(appDatabaseProvider).crmDao.deleteLead(lead.id));
                        if (context.mounted) Navigator.of(context).pop();
                      }
                    default:
                      if (leadStages.contains(v)) {
                        await _run(context, ref,
                            () => ref.read(appDatabaseProvider).crmDao.setStage(lead.id, v, by: _me(ref)));
                      }
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text(tr('Edit details'))),
                  if (open)
                    for (final s in openLeadStages.where((s) => s != lead.stage))
                      PopupMenuItem(value: s, child: Text(trf('Move to {stage}', {'stage': tr(leadStageLabels[s]!)}))),
                  if (lead.projectId == null) PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                ],
              ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
            Row(children: [
              StatusPill(leadStageLabels[lead.stage]!, tone: stageTone(lead.stage)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(rupees(leadValue(lead, quotes)),
                    style: theme.textTheme.titleMedium, textAlign: TextAlign.end),
              ),
            ]),
            if ((lead.phone ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _call(context, lead.phone!),
                    icon: const Icon(Icons.call_outlined),
                    label: Text(tr('Call')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _call(context, lead.phone!, whatsapp: true),
                    icon: const Icon(Icons.chat_outlined),
                    label: Text(tr('WhatsApp')),
                  ),
                ),
              ]),
            ],
            if (open) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  await showLogActivity(context, ref, lead: lead);
                  refreshCrm(ref, companyId, leadId);
                },
                icon: const Icon(Icons.edit_note),
                label: Text(tr('Log a call or visit')),
              ),
            ],
            Card(
              child: Column(children: [
                if (open)
                  row(Icons.event_outlined, tr('Next follow-up'),
                      lead.nextFollowUp == null ? tr('Not set. Tap to pick a day.') : fmtDate(lead.nextFollowUp!, now: now),
                      onTap: () => _pickFollowUp(context, ref, lead)),
                if ((lead.workType ?? '').isNotEmpty) row(Icons.home_work_outlined, tr('Work'), lead.workType!),
                if ((lead.location ?? '').isNotEmpty) row(Icons.place_outlined, tr('Location'), lead.location!),
                row(Icons.campaign_outlined, tr('Came from'), tr(leadSourceLabels[lead.source] ?? 'Other')),
                if (lead.estimatedValue != null)
                  row(Icons.currency_rupee, tr('Their budget'), rupees(lead.estimatedValue!)),
                if (lead.ownerId != null)
                  row(Icons.person_outline, tr('Followed up by'), names[lead.ownerId] ?? tr('Someone on the team')),
                if (lead.stage == 'lost') row(Icons.block, tr('Lost because'), lead.lostReason ?? ''),
                if ((lead.notes ?? '').isNotEmpty) row(Icons.notes, tr('Notes'), lead.notes!),
              ]),
            ),
            SectionHeader('Quotes'),
            for (final q in quotes)
              Card(
                child: ListTile(
                  title: Text('${q.quoteNumber} · ${rupees(q.total)}'),
                  subtitle: Text(fmtDate(q.quoteDate, now: now)),
                  trailing: StatusPill(quoteStatusLabels[q.status]!,
                      tone: q.status == 'accepted'
                          ? PillTone.ok
                          : q.status == 'rejected'
                              ? PillTone.danger
                              : PillTone.neutral),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => QuoteEditorScreen(companyId: companyId, lead: lead, quote: q)));
                    refreshCrm(ref, companyId, leadId);
                  },
                ),
              ),
            if (lead.stage != 'lost')
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => QuoteEditorScreen(
                          companyId: companyId, lead: lead, copyFrom: quotes.isEmpty ? null : quotes.first)));
                  refreshCrm(ref, companyId, leadId);
                },
                icon: const Icon(Icons.request_quote_outlined),
                label: Text(quotes.isEmpty ? tr('Make a quote') : tr('New version of the quote')),
              ),
            if (open) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _won(context, ref, lead, quotes),
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: Text(tr('Won')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _lost(context, ref, lead),
                    icon: const Icon(Icons.block),
                    label: Text(tr('Lost')),
                  ),
                ),
              ]),
            ],
            if (lead.stage == 'lost') ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _run(context, ref,
                    () => ref.read(appDatabaseProvider).crmDao.setStage(lead.id, 'contacted', by: _me(ref))),
                child: Text(tr('They came back: reopen')),
              ),
            ],
            if (lead.projectId != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  final p = await ref.read(appDatabaseProvider).projectDao.byId(lead.projectId!);
                  if (p != null && context.mounted) {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
                  }
                },
                icon: const Icon(Icons.apartment_outlined),
                label: Text(tr('Open the site')),
              ),
            ],
            SectionHeader('History'),
            ...history.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, st) => [ErrorState(error: e, stack: st)],
              data: (items) => items.isEmpty
                  ? [Padding(padding: const EdgeInsets.all(8), child: Text(tr('Nothing logged yet.')))]
                  : [
                      for (final a in items)
                        ListTile(
                          dense: true,
                          leading: Icon(switch (a.kind) {
                            'call' => Icons.call_outlined,
                            'visit' => Icons.place_outlined,
                            'meeting' => Icons.groups_outlined,
                            'whatsapp' => Icons.chat_outlined,
                            'stage' => Icons.swap_horiz,
                            _ => Icons.notes,
                          }),
                          title: Text(a.note),
                          subtitle: Text('${tr(activityKindLabels[a.kind] ?? 'Note')} · '
                              '${names[a.byUser] ?? tr('Someone on the team')} · ${fmtDateTime(a.createdAt, now: now)}'),
                        ),
                    ],
            ),
          ]),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

/// New lead, or edit one ([lead]). Returns the saved lead.
Future<CrmLead?> showLeadForm(BuildContext context, WidgetRef ref, {required String companyId, CrmLead? lead}) =>
    showModalBottomSheet<CrmLead>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LeadForm(companyId: companyId, lead: lead),
    );

class _LeadForm extends ConsumerStatefulWidget {
  const _LeadForm({required this.companyId, this.lead});
  final String companyId;
  final CrmLead? lead;

  @override
  ConsumerState<_LeadForm> createState() => _LeadFormState();
}

class _LeadFormState extends ConsumerState<_LeadForm> {
  late final _name = TextEditingController(text: widget.lead?.name);
  late final _phone = TextEditingController(text: widget.lead?.phone);
  late final _email = TextEditingController(text: widget.lead?.email);
  late final _location = TextEditingController(text: widget.lead?.location);
  late final _work = TextEditingController(text: widget.lead?.workType);
  late final _value = TextEditingController(
      text: widget.lead?.estimatedValue == null ? '' : fmtQty(widget.lead!.estimatedValue!));
  late final _notes = TextEditingController(text: widget.lead?.notes);
  late String _source = widget.lead?.source ?? 'referral';
  DateTime? _followUp = DateTime.now().add(const Duration(days: 1));
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _location, _work, _value, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = tr('Enter who the enquiry is from.'));
      return;
    }
    final value = _value.text.trim().isEmpty ? null : double.tryParse(_value.text.replaceAll(',', '').trim());
    if (_value.text.trim().isNotEmpty && (value == null || value < 0)) {
      setState(() => _error = tr('Enter the budget as a number, such as 2500000.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final dao = ref.read(appDatabaseProvider).crmDao;
      final me = ref.read(sessionProvider).user!.id;
      final CrmLead saved;
      if (widget.lead == null) {
        saved = await dao.addLead(
          companyId: widget.companyId,
          name: _name.text,
          by: me,
          phone: _phone.text,
          email: _email.text,
          location: _location.text,
          source: _source,
          workType: _work.text,
          estimatedValue: value,
          nextFollowUp: _followUp,
          notes: _notes.text,
        );
      } else {
        saved = await dao.updateLead(
          widget.lead!.id,
          name: _name.text,
          phone: Value(_phone.text),
          email: Value(_email.text),
          location: Value(_location.text),
          source: _source,
          workType: Value(_work.text),
          estimatedValue: Value(value),
          notes: Value(_notes.text),
        );
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e, st) {
      if (mounted) setState(() => _error = friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.lead == null ? tr('New lead') : tr('Edit details'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Name'), hintText: tr('Who asked: a person or a firm')),
          ),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: tr('Phone'))),
          TextField(
              controller: _work,
              decoration: InputDecoration(labelText: tr('Work'), hintText: tr('G+2 house, interiors, compound wall'))),
          TextField(controller: _location, decoration: InputDecoration(labelText: tr('Location'))),
          TextField(
            controller: _value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Their budget (optional)'), prefixText: '₹ '),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _source,
            decoration: InputDecoration(labelText: tr('Came from')),
            items: [
              for (final s in leadSources) DropdownMenuItem(value: s, child: Text(tr(leadSourceLabels[s]!))),
            ],
            onChanged: (v) => setState(() => _source = v ?? 'other'),
          ),
          TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: tr('Email (optional)'))),
          TextField(controller: _notes, maxLines: 3, decoration: InputDecoration(labelText: tr('Notes'))),
          if (widget.lead == null) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(tr('First follow-up')),
              subtitle: Text(_followUp == null ? tr('Not set') : fmtDate(_followUp!)),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                    context: context,
                    initialDate: _followUp ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 2));
                if (d != null) setState(() => _followUp = d);
              },
            ),
          ],
          if (_error != null) FormMessage(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Save'))),
        ]),
      ),
    );
  }
}

/// A call, visit or note, with the next follow-up, in one sheet.
Future<void> showLogActivity(BuildContext context, WidgetRef ref, {required CrmLead lead}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LogActivity(lead: lead),
    );

class _LogActivity extends ConsumerStatefulWidget {
  const _LogActivity({required this.lead});
  final CrmLead lead;

  @override
  ConsumerState<_LogActivity> createState() => _LogActivityState();
}

class _LogActivityState extends ConsumerState<_LogActivity> {
  final _note = TextEditingController();
  String _kind = 'call';
  int? _inDays = 3;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final now = DateTime.now();
      await ref.read(appDatabaseProvider).crmDao.logActivity(
            leadId: widget.lead.id,
            kind: _kind,
            note: _note.text,
            by: ref.read(sessionProvider).user!.id,
            nextFollowUp: _inDays == null ? null : DateTime(now.year, now.month, now.day + _inDays!),
            clearFollowUp: _inDays == null,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e, st) {
      setState(() => _error = friendlyError(e, st));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.lead.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in activityKinds)
              ChoiceChip(
                  label: Text(tr(activityKindLabels[k]!)),
                  selected: _kind == k,
                  onSelected: (_) => setState(() => _kind = k)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            autofocus: true,
            maxLines: 3,
            maxLength: 1000,
            decoration: InputDecoration(labelText: tr('What was said or agreed')),
          ),
          Text(tr('Next follow-up'), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (days, label) in followUpChoices)
              ChoiceChip(
                  label: Text(tr(label)), selected: _inDays == days, onSelected: (_) => setState(() => _inDays = days)),
            ChoiceChip(label: Text(tr('None')), selected: _inDays == null, onSelected: (_) => setState(() => _inDays = null)),
          ]),
          if (_error != null) FormMessage(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: Text(tr('Save'))),
        ]),
      ),
    );
  }
}
