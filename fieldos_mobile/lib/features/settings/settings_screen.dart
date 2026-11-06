/// Settings for everyone: the account, the subscription, voice reports,
/// help and the legal pages. Only the Sarvam key (a paid fallback for voice
/// reports) is limited to company owners.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/legal/legal_screen.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/speech_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _voiceLanguage;
  bool _sarvamKeySet = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsServiceProvider);
    final language = await settings.getVoiceLanguage();
    final keySet = await settings.isVoiceConfigured();
    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      // Not available in tests; the row just stays blank.
    }
    if (!mounted) return;
    setState(() {
      _voiceLanguage = language;
      _sarvamKeySet = keySet;
      _version = version;
    });
  }

  static String _roleLabel(String? role) => switch (role) {
        Roles.owner => 'Owner',
        Roles.manager => 'Project manager',
        Roles.viewer => 'Viewer',
        _ => 'Site engineer',
      };

  Future<void> _pickLanguage() async {
    final current = speechLanguageFor(_voiceLanguage).code;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => ListView(
          controller: controller,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text('Voice report language', style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('The language you usually speak your daily reports in. You can still change it each time.',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            ),
            for (final l in speechLanguages)
              ListTile(
                title: Text(l.label),
                trailing: l.code == current ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(ctx).pop(l.code),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(settingsServiceProvider).setVoiceLanguage(picked);
    if (mounted) setState(() => _voiceLanguage = picked);
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _ChangePasswordDialog());
    if ((changed ?? false) && mounted) showSnack(context, 'Password changed');
  }

  Future<void> _sarvamKey() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SarvamKeyDialog(keySet: _sarvamKeySet),
    );
    if (saved == null || !mounted) return;
    final keySet = await ref.read(settingsServiceProvider).isVoiceConfigured();
    if (!mounted) return;
    setState(() => _sarvamKeySet = keySet);
    showSnack(context, keySet ? 'Sarvam key saved' : 'Sarvam key removed');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final company = session.activeCompany;
    final billing = ref.read(billingServiceProvider);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final initials = (user?.name ?? '?')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w.characters.first.toUpperCase())
        .join();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // Account
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Brand.navy,
                foregroundColor: Colors.white,
                child: Text(initials.isEmpty ? '?' : initials,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.name ?? '', style: theme.textTheme.titleLarge),
                  Text('@${user?.username ?? ''}', style: muted),
                  if (company != null) Text('${_roleLabel(session.role)} · ${company.name}', style: muted),
                ]),
              ),
            ]),
          ),
          const SectionHeader('Account', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Change password'),
            subtitle: const Text('For logging in on this phone'),
            onTap: _changePassword,
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Team & sync'),
            subtitle: const Text('Share projects with your team, back up to the cloud'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen())),
          ),
          if (billing.setUp)
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('My subscription'),
              subtitle: const Text('FieldOS Pro: manage, cancel or restore'),
              onTap: () => showMySubscription(context),
            ),

          const SectionHeader('Voice reports', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Language'),
            subtitle: Text(speechLanguageFor(_voiceLanguage).label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickLanguage,
          ),
          if (session.canManageSettings)
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Sarvam fallback key'),
              subtitle: Text(_sarvamKeySet
                  ? 'Set. Used only on phones that cannot recognise the chosen language.'
                  : 'Not set. Voice reports use the phone itself, free and offline.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _sarvamKey,
            ),

          const SectionHeader('Help', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a bug'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: const Text('Email support'),
            subtitle: const Text(Brand.supportEmail),
            onTap: () => emailSupport(subject: 'FieldOS: help'),
          ),

          const SectionHeader('About', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => openPrivacyPolicy(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of use'),
            onTap: () => openTerms(context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Open-source licences'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'FieldOS',
              applicationVersion: _version,
              applicationIcon: const Padding(padding: EdgeInsets.all(8), child: BrandTile(size: 56)),
              applicationLegalese: '© ${DateTime.now().year} ${Brand.companyName}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_version ?? ''),
          ),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Log out'),
              onPressed: () {
                ref.read(cloudSyncBootstrapProvider).stop();
                ref.read(sessionProvider.notifier).logout();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Made in Hyderabad by ${Brand.companyName}',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: muted.color)),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(sessionProvider).user;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).changePassword(userId: user.id, current: _current.text, next: _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, st) {
      if (mounted) setState(() => _error = friendlyError(e, st));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _current,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Current password'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _next,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _busy ? null : _save(),
          decoration: InputDecoration(
            labelText: 'New password',
            helperText: 'At least ${AuthService.minPasswordLength} characters',
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), FormMessage(_error!)],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Change')),
      ],
    );
  }
}

/// The Sarvam key: write-only (never shown back), owners only, and only a
/// fallback for phones whose speech recognition can't do the language.
class _SarvamKeyDialog extends ConsumerStatefulWidget {
  const _SarvamKeyDialog({required this.keySet});

  final bool keySet;

  @override
  ConsumerState<_SarvamKeyDialog> createState() => _SarvamKeyDialogState();
}

class _SarvamKeyDialogState extends ConsumerState<_SarvamKeyDialog> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsServiceProvider);
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return AlertDialog(
      title: const Text('Sarvam fallback key'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          'Voice reports use the phone\'s own speech recognition, free and offline when the language pack is on '
          'the phone. Only phones that cannot recognise the chosen language at all send a recording to Sarvam AI '
          '(sarvam.ai), which needs a key from your Sarvam account and is billed by Sarvam.',
          style: muted,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: widget.keySet ? 'New key (replaces the saved one)' : 'Sarvam API key',
            prefixIcon: const Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Text('The key stays on this phone and is never shown again.', style: muted),
      ]),
      actions: [
        if (widget.keySet)
          TextButton(
            onPressed: () async {
              await settings.clearSarvamApiKey();
              if (context.mounted) Navigator.of(context).pop(false);
            },
            child: const Text('Remove key'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final key = _key.text.trim();
            if (key.isEmpty) return;
            await settings.setSarvamApiKey(key);
            if (context.mounted) Navigator.of(context).pop(true);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
