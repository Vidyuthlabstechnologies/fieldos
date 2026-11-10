/// The owner's evening brief across every running site, ready to read or
/// send on WhatsApp, and the one-line summary of it on Home.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:fieldos_mobile/core/format.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/brief/owner_brief.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/features/money/money_view.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';

/// Today's brief for a company. Refreshed whenever Home is.
final todayBriefProvider = FutureProvider.autoDispose.family<List<SiteBrief>, String>((ref, companyId) async {
  ref.watch(projectsProvider(companyId));
  return buildOwnerBrief(ref.watch(appDatabaseProvider), companyId, day: DateTime.now());
});

String flagLabel(BriefFlag f) => switch (f.kind) {
      FlagKind.overBudget => tr('Over budget'),
      FlagKind.nearBudget => tr('Close to budget'),
      FlagKind.seriousIssues => f.n == 1 ? tr('1 serious issue open') : trf('{n} serious issues open', {'n': f.n}),
      FlagKind.noReport => f.today ? tr('No report yet today') : tr('No report that day'),
      FlagKind.lateTasks => f.n == 1 ? tr('1 task late') : trf('{n} tasks late', {'n': f.n}),
      FlagKind.nobodyIn => f.today ? tr('Nobody punched in today') : tr('Nobody punched in'),
      FlagKind.newIssues => f.n == 1 ? tr('1 new issue') : trf('{n} new issues', {'n': f.n}),
    };

String levelLabel(BriefLevel l) => switch (l) {
      BriefLevel.needsYou => tr('Needs you'),
      BriefLevel.watch => tr('Watch'),
      BriefLevel.onTrack => tr('On track'),
    };

PillTone levelTone(BriefLevel l) => switch (l) {
      BriefLevel.needsYou => PillTone.danger,
      BriefLevel.watch => PillTone.warn,
      BriefLevel.onTrack => PillTone.ok,
    };

Future<void> openOwnerBrief(BuildContext context, {required String companyId, required String companyName}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OwnerBriefScreen(companyId: companyId, companyName: companyName),
    ));

class OwnerBriefScreen extends ConsumerStatefulWidget {
  const OwnerBriefScreen({super.key, required this.companyId, required this.companyName, this.now});
  final String companyId;
  final String companyName;

  /// For tests and the screen gallery.
  final DateTime? now;

  @override
  ConsumerState<OwnerBriefScreen> createState() => _OwnerBriefScreenState();
}

class _OwnerBriefScreenState extends ConsumerState<OwnerBriefScreen> {
  bool _yesterday = false;
  late Future<List<SiteBrief>> _briefs = _load();

  DateTime get _now => widget.now ?? DateTime.now();
  DateTime get _day {
    final t = DateTime(_now.year, _now.month, _now.day);
    return _yesterday ? t.subtract(const Duration(days: 1)) : t;
  }

  Future<List<SiteBrief>> _load() =>
      buildOwnerBrief(ref.read(appDatabaseProvider), widget.companyId, day: _day, now: _now);

  void _pick(bool yesterday) => setState(() {
        _yesterday = yesterday;
        _briefs = _load();
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showMoney = canSeeMoneyIn(ref.watch(sessionProvider).role);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Site brief'))),
      body: FutureBuilder<List<SiteBrief>>(
        future: _briefs,
        builder: (context, snap) {
          if (snap.hasError) {
            return ErrorState(error: snap.error!, stack: snap.stackTrace, onRetry: () => _pick(_yesterday));
          }
          final briefs = snap.data;
          return RefreshIndicator(
            onRefresh: () async {
              _pick(_yesterday);
              await _briefs;
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.paddingOf(context).bottom),
              children: [
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: Text(tr('Today')), selected: !_yesterday, onSelected: (_) => _pick(false)),
                  ChoiceChip(label: Text(tr('Yesterday')), selected: _yesterday, onSelected: (_) => _pick(true)),
                ]),
                const SizedBox(height: 12),
                if (briefs == null)
                  const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                else if (briefs.isEmpty)
                  MitraSays(
                    mood: MitraMood.sleep,
                    title: tr('No running sites'),
                    message: tr('Sites marked active show here every evening with their people, money, work and problems.'),
                  )
                else ...[
                  _Headline(briefs: briefs, showMoney: showMoney),
                  const SizedBox(height: 16),
                  for (final b in briefs) ...[
                    _SiteBriefCard(brief: b, showMoney: showMoney),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    tr('Built from what each site recorded. Pull down to refresh.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<List<SiteBrief>>(
        future: _briefs,
        builder: (context, snap) => (snap.data?.isNotEmpty ?? false)
            ? FloatingActionButton.extended(
                icon: const Icon(Icons.share_outlined),
                label: Text(tr('Send brief')),
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: ownerBriefText(snap.data!,
                      companyName: widget.companyName,
                      day: _day,
                      showMoney: canSeeMoneyIn(ref.read(sessionProvider).role)),
                )),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.briefs, required this.showMoney});
  final List<SiteBrief> briefs;
  final bool showMoney;

  @override
  Widget build(BuildContext context) {
    final t = briefTotals(briefs);
    final mood = t.needYou > 0
        ? MitraMood.worried
        : briefs.every((b) => b.level == BriefLevel.onTrack)
            ? MitraMood.thumbsUp
            : MitraMood.think;
    final title = t.needYou == 0
        ? (mood == MitraMood.thumbsUp ? tr('Every site is on track') : tr('Nothing urgent today'))
        : t.needYou == 1
            ? tr('1 site needs you')
            : trf('{n} sites need you', {'n': t.needYou});
    final facts = [
      trf('{n} people on site', {'n': t.people}),
      trf('{done} of {all} reported', {'done': t.reported, 'all': briefs.length}),
      if (showMoney) trf('{amount} spent', {'amount': rupees(t.spent)}),
    ].join(' · ');
    return MitraSays(mood: mood, size: 88, title: title, message: facts);
  }
}

class _SiteBriefCard extends ConsumerWidget {
  const _SiteBriefCard({required this.brief, required this.showMoney});
  final SiteBrief brief;
  final bool showMoney;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final b = brief;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: b.project))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(b.project.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 8),
              StatusPill(levelLabel(b.level), tone: levelTone(b.level)),
            ]),
            // What needs the owner, as one plain line in the status colour,
            // instead of a row of red and amber chips.
            if (b.flags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(b.flags.map(flagLabel).join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: toneColor(context, b.flags.first.weight >= 3 ? PillTone.danger : PillTone.warn))),
            ],
            const SizedBox(height: 12),
            Row(children: [
              _Fact(icon: Icons.groups_outlined, value: '${b.people}', label: tr('People')),
              if (showMoney) _Fact(icon: Icons.payments_outlined, value: rupees(b.spent), label: tr('Spent')),
              _Fact(icon: Icons.task_alt, value: '${b.tasksDone.length}', label: tr('Tasks done')),
              _Fact(icon: Icons.report_outlined, value: '${b.openIssues}', label: tr('Open issues')),
            ]),
            const SizedBox(height: 10),
            _Line(icon: Icons.description_outlined, text: b.reportLine ?? tr('No daily report yet'), faint: b.reportLine == null),
            if (b.materials.isNotEmpty) _Line(icon: Icons.local_shipping_outlined, text: b.materials.join(', ')),
            for (final i in b.newIssues.take(2)) _Line(icon: Icons.error_outline, text: i),
            if (b.dueTomorrow.isNotEmpty)
              _Line(icon: Icons.event_outlined, text: '${tr('Tomorrow')}: ${b.dueTomorrow.take(3).join(', ')}'),
            if (showMoney && b.costAlert != null) _Line(icon: Icons.warning_amber_rounded, text: b.costAlert!, warn: true),
            if (showMoney && b.received > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(trf('{amount} received from the client', {'amount': rupees(b.received)}), style: muted),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: theme.textTheme.titleMedium),
        ),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.faint = false, this.warn = false});
  final IconData icon;
  final String text;
  final bool faint;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = warn
        ? theme.colorScheme.error
        : faint
            ? theme.colorScheme.onSurfaceVariant
            : null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color ?? theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color))),
      ]),
    );
  }
}

/// The brief in one line on Home: how many sites need the owner today.
class TodayBriefCard extends ConsumerWidget {
  const TodayBriefCard({super.key, required this.companyId, required this.companyName});
  final String companyId;
  final String companyName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final briefs = ref.watch(todayBriefProvider(companyId)).value;
    if (briefs == null || briefs.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final t = briefTotals(briefs);
    final showMoney = canSeeMoneyIn(ref.watch(sessionProvider).role);
    final urgent = t.needYou > 0;
    final title = urgent
        ? (t.needYou == 1 ? tr('1 site needs you') : trf('{n} sites need you', {'n': t.needYou}))
        : tr('Nothing urgent today');
    final accent = urgent ? toneColor(context, PillTone.danger) : scheme.secondary;
    // A plain white card like the rest of Home. Urgency shows as a small
    // coloured dot and the headline, not as a pink block.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await openOwnerBrief(context, companyId: companyId, companyName: companyName);
            ref.invalidate(todayBriefProvider(companyId));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Row(children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(left: 2, right: 14),
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr("Today's brief"), style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    [
                      trf('{n} people on site', {'n': t.people}),
                      trf('{done} of {all} reported', {'done': t.reported, 'all': briefs.length}),
                      if (showMoney) trf('{amount} spent', {'amount': rupees(t.spent)}),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ]),
          ),
        ),
      ),
    );
  }
}
