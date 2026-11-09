/// The app tour: Mitra walks through one working day on the sample site
/// (Mr. Reddy's G+1 house), on the real screens filled with its data, from
/// the morning plan to the evening report, Saturday wages and the owner's
/// dashboard.
///
/// The screens are shown live but can't be tapped during the tour, so
/// nothing is changed by accident; the last step offers to open the sample
/// site for real, or to start a first project.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/home/home_screen.dart';
import 'package:fieldos_mobile/features/labour/wage_sheet_screen.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/features/onboarding/sample_project.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/read_aloud.dart';

/// Set once the tour has been started, so Home stops inviting to it.
const tourSeenKey = 'app_tour_seen';

final tourSeenProvider = FutureProvider.autoDispose<bool>((ref) async {
  return (await ref.watch(appDatabaseProvider).settingsDao.get(tourSeenKey)) == '1';
});

/// What the person chose at the end of the tour.
enum TourExit { explore, newProject }

/// Where a step's screen comes from.
enum TourStage { home, project, wageSheet, dashboard }

class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    required this.mood,
    this.stage = TourStage.project,
    this.tab = 0,
    this.time,
  });

  final String title;
  final String body;
  final MitraMood mood;
  final TourStage stage;

  /// The project tab for [TourStage.project] (see [ProjectDetailScreen]).
  final int tab;

  /// The time of day in the story, shown as a chip ("8:00 AM").
  final String? time;
}

/// The story, in order. English keys; shown through tr().
List<TourStep> appTourSteps() => [
      TourStep(
        stage: TourStage.home,
        mood: MitraMood.wave,
        title: tr('Namaste! I am Mitra, your site buddy'),
        body: tr('Let me show you one day on a real site: Mr. Reddy\'s G+1 house. It takes two minutes '
            'and does not touch your own data.'),
      ),
      TourStep(
        stage: TourStage.home,
        mood: MitraMood.point,
        title: tr('All your sites in one list'),
        body: tr('Each site shows its stage and anything running late. Tap a site to open its tasks, '
            'labour, money and reports.'),
      ),
      TourStep(
        stage: TourStage.home,
        mood: MitraMood.talk,
        title: tr('Just ask FieldOS'),
        body: tr('Not sure where something is? Tap Ask FieldOS at the top and type or speak, like '
            '"add 5000 for cement". It does the work and asks you to tap Save first.'),
      ),
      TourStep(
        tab: 0,
        time: tr('8:00 AM'),
        mood: MitraMood.checklist,
        title: tr('Plan the day'),
        body: tr('Tasks show how far each job has got and what is slipping. The plinth beam is late, '
            'so it is marked in red before anyone has to ask.'),
      ),
      TourStep(
        tab: 5,
        time: tr('9:00 AM'),
        mood: MitraMood.thumbsUp,
        title: tr('Attendance in two taps'),
        body: tr('Punch workers in as they arrive, or mark the whole gang at once. Hours, half days '
            'and overtime are worked out for you.'),
      ),
      TourStep(
        tab: 4,
        time: tr('11:00 AM'),
        mood: MitraMood.measure,
        title: tr('Cement arrives'),
        body: tr('Raise a purchase order, then receive what actually came. A part delivery keeps the '
            'order open, and stock updates itself.'),
      ),
      TourStep(
        tab: 6,
        time: tr('1:00 PM'),
        mood: MitraMood.money,
        title: tr('Every rupee on site'),
        body: tr('Money received, money spent and the balance, by category. Client bills and GST '
            'invoices are made here too.'),
      ),
      TourStep(
        tab: 2,
        time: tr('3:00 PM'),
        mood: MitraMood.worried,
        title: tr('Problems do not get lost'),
        body: tr('Cement ran short for the column casting. Raise it once and it stays open, with photos, '
            'until someone marks it fixed.'),
      ),
      TourStep(
        tab: 1,
        time: tr('6:00 PM'),
        mood: MitraMood.listen,
        title: tr('Speak the daily report'),
        body: tr('Tap Speak report and just talk, in Telugu, Hindi or English. FieldOS writes the '
            'report, adds the day\'s numbers and shares a PDF on WhatsApp.'),
      ),
      TourStep(
        stage: TourStage.wageSheet,
        time: tr('Saturday'),
        mood: MitraMood.chai,
        title: tr('Wages without a calculator'),
        body: tr('The wage sheet adds up each worker\'s days, advances and what is still due, ready to '
            'pay or send to the contractor.'),
      ),
      TourStep(
        stage: TourStage.dashboard,
        mood: MitraMood.think,
        title: tr('Every site at a glance'),
        body: tr('Owners see spending against budget, progress and open problems across all sites, '
            'without a single phone call.'),
      ),
      TourStep(
        stage: TourStage.home,
        mood: MitraMood.celebrate,
        title: tr('You are ready!'),
        body: tr('Look around the sample site yourself, or start your first real project. You can '
            'play this tour again from the menu any time.'),
      ),
    ];

/// Opens the tour, creating the sample site if needed. Returns what the
/// person picked at the end, or null if they closed it.
Future<TourExit?> openAppTour(BuildContext context, WidgetRef ref, {required String companyId}) async {
  final db = ref.read(appDatabaseProvider);
  final userId = ref.read(sessionProvider).user?.id ?? '';
  await db.settingsDao.set(tourSeenKey, '1');
  ref.invalidate(tourSeenProvider);
  final project = await createSampleProject(db, companyId: companyId, userId: userId);
  ref.invalidate(projectsProvider(companyId));
  ref.invalidate(sampleProjectIdProvider(companyId));
  if (!context.mounted) return null;
  return Navigator.of(context).push<TourExit>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => AppTourScreen(companyId: companyId, project: project),
  ));
}

class AppTourScreen extends ConsumerStatefulWidget {
  const AppTourScreen({super.key, required this.companyId, required this.project, this.initialStep = 0});

  final String companyId;
  final Project project;
  final int initialStep;

  @override
  ConsumerState<AppTourScreen> createState() => _AppTourScreenState();
}

class _AppTourScreenState extends ConsumerState<AppTourScreen> {
  late int _index = widget.initialStep;

  /// Mitra reads each step aloud, for people who would rather listen than
  /// read. Once switched on it carries on through the tour.
  bool _voice = false;

  void _go(int to, int count) {
    if (to < 0 || to >= count) return;
    setState(() => _index = to);
    if (_voice) _read(appTourSteps()[to]);
  }

  void _read(TourStep step) => ReadAloud.say('${step.title}. ${step.body}');

  void _toggleVoice(TourStep step) {
    setState(() => _voice = !_voice);
    _voice ? _read(step) : ReadAloud.stop();
  }

  @override
  void dispose() {
    if (_voice) ReadAloud.stop();
    super.dispose();
  }

  Widget _stage(TourStep step) {
    final session = ref.read(sessionProvider);
    final company = session.activeCompany;
    return switch (step.stage) {
      TourStage.home => const HomeScreen(),
      TourStage.project => ProjectDetailScreen(
          key: ValueKey('tab${step.tab}'), project: widget.project, initialTab: step.tab),
      TourStage.wageSheet => WageSheetScreen(
          projectId: widget.project.id, projectName: widget.project.name, userId: session.user?.id ?? ''),
      TourStage.dashboard =>
        DashboardScreen(companyId: widget.companyId, companyName: company?.name ?? widget.project.name),
    };
  }

  @override
  Widget build(BuildContext context) {
    final steps = appTourSteps();
    final step = steps[_index.clamp(0, steps.length - 1)];
    final last = _index == steps.length - 1;
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_index - 1, steps.length);
      },
      child: Scaffold(
        body: Column(
          children: [
            // The real screen, live but not tappable, above the guide.
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        child: KeyedSubtree(key: ValueKey(_index), child: _stage(step)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _GuideCard(
              step: step,
              index: _index,
              count: steps.length,
              bottomInset: media.viewPadding.bottom,
              voice: _voice,
              onVoice: () => _toggleVoice(step),
              onSkip: () => Navigator.of(context).pop(),
              onBack: _index == 0 ? null : () => _go(_index - 1, steps.length),
              onNext: last ? null : () => _go(_index + 1, steps.length),
              onExplore: last ? () => Navigator.of(context).pop(TourExit.explore) : null,
              onNewProject: last ? () => Navigator.of(context).pop(TourExit.newProject) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.step,
    required this.index,
    required this.count,
    required this.bottomInset,
    required this.onSkip,
    this.voice = false,
    this.onVoice,
    this.onBack,
    this.onNext,
    this.onExplore,
    this.onNewProject,
  });

  final TourStep step;
  final int index;
  final int count;
  final double bottomInset;
  final VoidCallback onSkip;
  final bool voice;
  final VoidCallback? onVoice;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onExplore;
  final VoidCallback? onNewProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 12,
      shadowColor: Colors.black54,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Padding(
        // Clear of the phone's own back/home/recent buttons or gesture bar.
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i <= index ? scheme.secondary : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                if (onVoice != null)
                  IconButton(
                    onPressed: onVoice,
                    tooltip: voice ? tr('Stop') : tr('Read aloud'),
                    isSelected: voice,
                    icon: const Icon(Icons.volume_up_outlined),
                    selectedIcon: const Icon(Icons.volume_up),
                  ),
                TextButton.icon(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(tr('Skip tour')),
                ),
              ],
            ),
            Semantics(
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Tapping Mitra reads the step aloud too.
                  GestureDetector(
                    onTap: () => ReadAloud.toggle('${step.title}. ${step.body}'),
                    child: Mitra(mood: step.mood, size: 104),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Column(
                        key: ValueKey(index),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (step.time != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(step.time!,
                                  style: theme.textTheme.labelMedium
                                      ?.copyWith(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w700)),
                            ),
                          Text(step.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(step.body,
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.35)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (onExplore != null)
              Row(children: [
                Expanded(
                  child: OutlinedButton(onPressed: onExplore, child: Text(tr('Explore the sample'))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: onNewProject, child: Text(tr('Start my project'))),
                ),
              ])
            else
              Row(children: [
                Text(trf('{n} of {total}', {'n': index + 1, 'total': count}),
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (onBack != null) TextButton(onPressed: onBack, child: Text(tr('Back'))),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(index == 0 ? tr('Show me') : tr('Next')),
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

/// On Home: Mitra's invitation to the tour, until it has been taken.
class TourInviteCard extends ConsumerWidget {
  const TourInviteCard({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.watch(tourSeenProvider).valueOrNull ?? true;
    if (seen) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onStart,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            children: [
              const Mitra(mood: MitraMood.wave, size: 88),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('New here? Take the 2-minute tour'),
                        style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSecondaryContainer)),
                    const SizedBox(height: 2),
                    Text(tr('See one full day on a sample site, from attendance to the evening report.'),
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer)),
                    const SizedBox(height: 8),
                    FilledButton.tonalIcon(
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(tr('Start the tour')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
