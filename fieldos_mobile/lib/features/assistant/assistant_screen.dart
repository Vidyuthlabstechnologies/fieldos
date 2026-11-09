/// "Ask FieldOS": a chat where anyone can type or speak what they need, in
/// their own language, and the assistant does it in the app for them. It
/// reads the site data on the phone, makes changes after a tap on a confirm
/// card, and offers a button to the right screen for anything else.
///
/// The thinking happens on FieldOS's server (Claude, with the one shared key
/// held there); the data and every change stay on the phone and sync with
/// the team as usual.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:fieldos_mobile/agents/assistant_conversation.dart';
import 'package:fieldos_mobile/agents/assistant_tools.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/data/app_database.dart';
import 'package:fieldos_mobile/features/approvals/approvals_screen.dart';
import 'package:fieldos_mobile/features/dashboard/dashboard_screen.dart';
import 'package:fieldos_mobile/features/map/site_map_screen.dart';
import 'package:fieldos_mobile/features/mascot/mitra.dart';
import 'package:fieldos_mobile/features/project/project_detail_screen.dart';
import 'package:fieldos_mobile/features/project/voice_report_sheet.dart';
import 'package:fieldos_mobile/features/search/search_screen.dart';
import 'package:fieldos_mobile/features/settings/settings_screen.dart';
import 'package:fieldos_mobile/features/subcontractor/subcontractor_screen.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/features/tasks/my_tasks_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';

/// Opens the assistant; [listen] starts with the microphone.
Future<void> openAssistant(BuildContext context, {bool listen = false}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AssistantScreen(startListening: listen)));

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.startListening = false});

  final bool startListening;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  late final AssistantConversation _chat;
  late final Company _company;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  FlutterTts? _tts;
  bool _speakReplies = false;
  bool _speaking = false;

  @override
  void initState() {
    super.initState();
    final session = ref.read(sessionProvider);
    _company = session.activeCompany!;
    final db = ref.read(appDatabaseProvider);
    _chat = AssistantConversation(
      backend: ref.read(aiBackendProvider),
      tools: AssistantTools(db: db, companyId: _company.id, userId: session.user?.id ?? '', role: session.role),
      appState: _appState,
      onDataChanged: (projectId) {
        ref.invalidate(projectsProvider(_company.id));
        ref.invalidate(openTasksProvider(_company.id));
        ref.invalidate(pendingApprovalsProvider(_company.id));
      },
    )..addListener(_changed);
    if (widget.startListening) WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
  }

  @override
  void dispose() {
    _chat
      ..removeListener(_changed)
      ..dispose();
    _input.dispose();
    _scroll.dispose();
    _tts?.stop();
    super.dispose();
  }

  String? _spokenFor;

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
    final reply = _chat.lastReply;
    if (_speakReplies && !_chat.busy && reply != null && reply != _spokenFor) {
      _spokenFor = reply;
      _say(reply);
    }
  }

  Future<String> _appState() async {
    final session = ref.read(sessionProvider);
    final projects = await ref.read(appDatabaseProvider).projectDao.forCompany(_company.id);
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final state = {
      'today': isoDay(now),
      'weekday': days[now.weekday - 1],
      'time': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'app_language': currentLanguage.englishName,
      'company': _company.name,
      'user': session.user?.name,
      'role': session.role,
      'projects': [
        for (final p in projects.take(40)) {'id': p.id, 'name': p.name, 'status': p.status, 'client': p.clientName}
      ],
    };
    return '<app_state>${jsonEncode(state)}</app_state>';
  }

  Future<void> _send([String? text]) async {
    final words = (text ?? _input.text).trim();
    if (words.isEmpty || _chat.busy) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    await _chat.send(words);
  }

  Future<void> _listen() async {
    if (_chat.busy) return;
    final heard = await showVoiceReportSheet(context, forAssistant: true);
    if (heard == null || !mounted) return;
    if (heard.typeInstead) {
      _input.text = heard.text;
      return;
    }
    // Asked by voice: answer by voice too.
    setState(() => _speakReplies = true);
    await _send(heard.text);
  }

  Future<void> _say(String text) async {
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage(_ttsLanguage(text));
      await tts.setSpeechRate(0.5);
      tts.setCompletionHandler(() {
        if (mounted) setState(() => _speaking = false);
      });
      setState(() => _speaking = true);
      await tts.speak(text);
    } catch (_) {
      // No voice on this phone for that language: the words are on screen.
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts?.stop();
    if (mounted) setState(() => _speaking = false);
  }

  /// The voice to read [text] with, by its script.
  static String _ttsLanguage(String text) {
    if (RegExp(r'[ఀ-౿]').hasMatch(text)) return 'te-IN';
    if (RegExp(r'[ऀ-ॿ]').hasMatch(text)) return 'hi-IN';
    if (RegExp(r'[஀-௿]').hasMatch(text)) return 'ta-IN';
    if (RegExp(r'[ಀ-೿]').hasMatch(text)) return 'kn-IN';
    return 'en-IN';
  }

  Future<void> _open(ScreenLink link) async {
    final nav = Navigator.of(context);
    Project? project;
    if (link.projectId != null) project = await ref.read(appDatabaseProvider).projectDao.byId(link.projectId!);
    if (!mounted) return;
    const tabs = {
      'project': 0, 'tasks': 0, 'daily_reports': 1, 'issues': 2, 'team_chat': 3, 'purchasing': 4, 'labour': 5, //
      'money': 6, 'equipment': 7, 'inspections': 8, 'documents': 9, 'workers': 10, 'estimation': 11,
    };
    final Widget? page = switch (link.screen) {
      _ when tabs.containsKey(link.screen) && project != null =>
        ProjectDetailScreen(project: project, initialTab: tabs[link.screen]!),
      'dashboard' => DashboardScreen(companyId: _company.id, companyName: _company.name),
      'approvals' => ApprovalsScreen(companyId: _company.id),
      'my_tasks' => MyTasksScreen(companyId: _company.id),
      'site_map' => SiteMapScreen(companyId: _company.id),
      'subcontractors' => SubcontractorsScreen(companyId: _company.id),
      'search' => SearchScreen(companyId: _company.id),
      'team_and_sync' => const TeamSyncScreen(),
      'settings' => const SettingsScreen(),
      'report_bug' => const BugReportScreen(),
      _ => null,
    };
    if (link.screen == 'subscription') {
      await showMySubscription(context);
    } else if (link.screen == 'home') {
      nav.popUntil((r) => r.isFirst);
    } else if (page != null) {
      await nav.push(MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(aiBackendProvider).signedIn;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          const _Avatar(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Ask FieldOS'), overflow: TextOverflow.ellipsis),
              Text(
                _chat.busy ? tr('Working on it…') : tr('Type or speak. I will do it in the app.'),
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: _speakReplies ? tr('Stop reading answers aloud') : tr('Read answers aloud'),
            icon: Icon(_speakReplies ? Icons.volume_up : Icons.volume_off_outlined),
            onPressed: () {
              setState(() => _speakReplies = !_speakReplies);
              if (!_speakReplies) _stopSpeaking();
            },
          ),
          if (_chat.items.isNotEmpty)
            IconButton(
              tooltip: tr('New chat'),
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _chat.busy ? null : _chat.clear,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: !signedIn
                ? _SignInFirst(onDone: () => setState(() {}))
                : _chat.items.isEmpty
                    ? _Welcome(name: ref.read(sessionProvider).user?.name, onPick: _send)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: _chat.items.length + (_chat.busy && !_chat.waitingForConfirm ? 1 : 0),
                        itemBuilder: (context, n) {
                          if (n == _chat.items.length) return const _Typing();
                          return switch (_chat.items[n]) {
                            PersonSaid(:final text) => _Bubble(text: text, mine: true),
                            AssistantSaid(:final text) => _Bubble(
                                text: text,
                                onSpeak: () => _speaking ? _stopSpeaking() : _say(text),
                              ),
                            final ConfirmAction a => _ConfirmCard(action: a, onDecide: (yes) => _chat.decide(a, yes)),
                            ScreenButton(:final link) => _ScreenButton(link: link, onTap: () => _open(link)),
                            final ChatNotice n => _Notice(notice: n, onRetry: () => setState(() {})),
                          };
                        },
                      ),
          ),
          if (signedIn && (_chat.allowanceLeft ?? 100) <= 20)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                trf('{n}% of this month\'s assistant use is left', {'n': '${_chat.allowanceLeft}'}),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (signedIn)
            _Composer(
              controller: _input,
              enabled: !_chat.busy,
              onSend: _send,
              onMic: _listen,
              hint: _chat.waitingForConfirm ? tr('Tap Save or Cancel above first') : tr('Ask or tell FieldOS anything…'),
            ),
        ]),
      ),
    );
  }
}

/// The assistant's face: Mitra, the site buddy, in a soft amber circle.
/// Small avatars hold still so a long chat doesn't animate every bubble.
class _Avatar extends StatelessWidget {
  const _Avatar({this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: ColoredBox(
            color: Brand.amberSoft,
            child: OverflowBox(
              maxWidth: size * 1.5,
              maxHeight: size * 1.5,
              alignment: const Alignment(0, -0.35),
              child: Mitra(mood: size >= 60 ? MitraMood.wave : MitraMood.talk, size: size * 1.5, still: size < 60),
            ),
          ),
        ),
      );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.name, required this.onPick});
  final String? name;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
    final ideas = [
      tr('What happened on my sites today?'),
      tr('Add ₹5,000 spent on cement'),
      tr('Mark all workers present'),
      tr("Write today's daily report"),
      tr('How much did I spend this month?'),
      tr('Which tasks are late?'),
      tr('How do I make a bill for my client?'),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
      children: [
        const Center(child: _Avatar(size: 72)),
        const SizedBox(height: 16),
        Text(
          first.isEmpty ? tr('Namaste! What should I do?') : trf('Namaste, {name}! What should I do?', {'name': first}),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          tr('Tell me in your own words, by typing or with the mic. I can add expenses, attendance, tasks, reports and '
              'more, and answer questions about your sites. I always ask before saving anything.'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [for (final i in ideas) ActionChip(label: Text(i), onPressed: () => onPick(i))],
        ),
      ],
    );
  }
}

class _SignInFirst extends StatelessWidget {
  const _SignInFirst({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(24, 40, 24, 24), children: [
      const Center(child: _Avatar(size: 72)),
      const SizedBox(height: 16),
      Text(tr('Sign in once to use the assistant'), textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
      const SizedBox(height: 8),
      Text(
        tr('The assistant thinks on FieldOS\'s server, so it needs your FieldOS account and internet. Your site data '
            'stays on this phone; only what you ask, and what is needed to answer it, is sent.'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        icon: const Icon(Icons.login),
        label: Text(tr('Sign in to Team & sync')),
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen()));
          onDone();
        },
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, this.mine = false, this.onSpeak});
  final String text;
  final bool mine;
  final VoidCallback? onSpeak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? Brand.navy : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(mine ? 18 : 4),
          bottomRight: Radius.circular(mine ? 4 : 18),
        ),
      ),
      child: SelectableText(text,
          style: TextStyle(color: mine ? Colors.white : scheme.onSurface, fontSize: 16, height: 1.35)),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[const _Avatar(size: 28), const SizedBox(width: 6)],
          Flexible(child: bubble),
          if (onSpeak != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Read aloud'),
              icon: const Icon(Icons.volume_up_outlined, size: 20),
              onPressed: onSpeak,
            ),
        ],
      ),
    );
  }
}

class _Typing extends StatelessWidget {
  const _Typing();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          const _Avatar(size: 28),
          const SizedBox(width: 10),
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(tr('Working on it…')),
        ]),
      );
}

class _ConfirmCard extends StatelessWidget {
  const _ConfirmCard({required this.action, required this.onDecide});
  final ConfirmAction action;
  final void Function(bool yes) onDecide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (action.state) {
      ConfirmState.waiting => (Icons.help_outline, Brand.amberDark, tr('Save this?')),
      ConfirmState.saved => (Icons.check_circle, Brand.ok, tr('Saved')),
      ConfirmState.cancelled => (Icons.cancel_outlined, Brand.inkMuted, tr('Not saved')),
      ConfirmState.failed => (Icons.error_outline, Brand.danger, tr('Could not save')),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(34, 4, 0, 4),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.labelLarge?.copyWith(color: color)),
            ]),
            const SizedBox(height: 6),
            Text(action.summary, style: theme.textTheme.bodyLarge),
            if (action.state == ConfirmState.waiting)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => onDecide(false), child: Text(tr('Cancel'))),
                const SizedBox(width: 4),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(tr('Save')),
                  onPressed: () => onDecide(true),
                ),
              ])
            else
              const SizedBox(height: 6),
          ]),
        ),
      ),
    );
  }
}

class _ScreenButton extends StatelessWidget {
  const _ScreenButton({required this.link, required this.onTap});
  final ScreenLink link;
  final VoidCallback onTap;

  static String label(String screen) => switch (screen) {
        'home' => tr('Home'),
        'project' || 'tasks' => tr('Tasks'),
        'daily_reports' => tr('DPR'),
        'issues' => tr('Issues'),
        'team_chat' => tr('Chat'),
        'purchasing' => tr('Procure'),
        'labour' => tr('Labour'),
        'money' => tr('Money'),
        'equipment' => tr('Equipment'),
        'inspections' => tr('Inspections'),
        'documents' => tr('Documents'),
        'workers' => tr('Workers'),
        'estimation' => tr('Estimation'),
        'dashboard' => tr('Dashboard'),
        'approvals' => tr('Approvals'),
        'my_tasks' => tr('My tasks'),
        'site_map' => tr('Site map'),
        'subcontractors' => tr('Subcontractors'),
        'search' => tr('Search'),
        'team_and_sync' => tr('Team & sync'),
        'settings' => tr('Settings'),
        'subscription' => tr('My subscription'),
        'report_bug' => tr('Report a bug'),
        _ => screen,
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(34, 4, 0, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(trf('Open {screen}', {'screen': label(link.screen)})),
            onPressed: onTap,
          ),
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.notice, required this.onRetry});
  final ChatNotice notice;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = switch (notice.code) {
      'signed_out' => (
          tr('Sign in to Team & sync'),
          () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen()));
            onRetry();
          }
        ),
      'no_plan' => (tr('My subscription'), () => showMySubscription(context)),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Brand.warnSoft, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Brand.warn, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(notice.text), style: theme.textTheme.bodyMedium?.copyWith(color: Brand.ink))),
          ]),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: action.$2, child: Text(action.$1)),
            ),
        ]),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    required this.onMic,
    required this.hint,
  });

  final TextEditingController controller;
  final bool enabled;
  final void Function([String?]) onSend;
  final VoidCallback onMic;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.trim().isEmpty
                ? IconButton.filled(
                    tooltip: tr('Speak'),
                    style: IconButton.styleFrom(backgroundColor: Brand.amber, foregroundColor: Brand.navyDeep),
                    iconSize: 28,
                    onPressed: enabled ? onMic : null,
                    icon: const Icon(Icons.mic),
                  )
                : IconButton.filled(
                    tooltip: tr('Send'),
                    iconSize: 26,
                    onPressed: enabled ? () => onSend() : null,
                    icon: const Icon(Icons.send),
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Home's way in: one tap to type, one to speak.
class AssistantEntry extends StatelessWidget {
  const AssistantEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: Brand.navy,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openAssistant(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            const _Avatar(size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Ask FieldOS'), style: theme.textTheme.titleMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  tr('Just say it: "Add ₹5,000 for cement", "Who came today?"'),
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ]),
            ),
            IconButton.filled(
              tooltip: tr('Speak'),
              style: IconButton.styleFrom(backgroundColor: Brand.amber, foregroundColor: Brand.navyDeep),
              iconSize: 26,
              onPressed: () => openAssistant(context, listen: true),
              icon: const Icon(Icons.mic),
            ),
          ]),
        ),
      ),
    );
  }
}
