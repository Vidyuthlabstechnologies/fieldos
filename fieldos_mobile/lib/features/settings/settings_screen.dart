/// Settings for everyone: the account, the subscription, voice reports,
/// help and the legal pages. There is no AI or speech key to set: FieldOS's
/// server holds the shared keys (see lib/services/ai_backend.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/features/money/money_view.dart' show canSeeMoneyIn;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:fieldos_mobile/auth/auth_service.dart';
import 'package:fieldos_mobile/core/brand.dart';
import 'package:fieldos_mobile/core/ui.dart';
import 'package:fieldos_mobile/features/company/branding.dart';
import 'package:fieldos_mobile/features/export/export_action.dart';
import 'package:fieldos_mobile/features/legal/legal_screen.dart';
import 'package:fieldos_mobile/features/subscription/my_subscription_sheet.dart';
import 'package:fieldos_mobile/features/support/bug_report_screen.dart';
import 'package:fieldos_mobile/features/team/team_sync_screen.dart';
import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/speech_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_bootstrap.dart';
import 'package:fieldos_mobile/core/text_size.dart';
import 'package:fieldos_mobile/features/reminders/reminders.dart';
import 'package:fieldos_mobile/features/security/app_lock.dart';
import 'package:fieldos_mobile/l10n/language.dart';
import 'package:fieldos_mobile/l10n/language_picker.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _voiceLanguage;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
    _loadReminders();
  }

  Future<void> _load() async {
    final settings = ref.read(settingsServiceProvider);
    final language = await settings.getVoiceLanguage();
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
      _version = version;
    });
  }

  static String _roleLabel(String? role) => switch (role) {
        Roles.owner => tr('Owner'),
        Roles.manager => tr('Project manager'),
        Roles.viewer => tr('Viewer'),
        _ => tr('Site engineer'),
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
              child: Text(tr('Voice report language'), style: Theme.of(ctx).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(tr('The language you usually speak your daily reports in. You can still change it each time.'),
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

  static String _textSizeLabel(String size) => switch (size) {
        'large' => 'Large',
        'larger' => 'Larger',
        _ => 'Normal',
      };

  Future<void> _pickTextSize() async {
    final current = ref.read(textSizeProvider);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final size in textSizes.keys)
            ListTile(
              title: Text(tr(_textSizeLabel(size)), textScaler: TextScaler.linear(textSizes[size]!)),
              trailing: size == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(size),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) await ref.read(textSizeProvider.notifier).choose(picked);
  }

  Future<void> _toggleLock(bool on) async {
    final lock = ref.read(appLockProvider);
    if (on) {
      final pin = await askNewPin(context);
      if (pin == null) return;
      await lock.setPin(pin);
    } else {
      await lock.turnOff();
    }
    ref.invalidate(appLockOnProvider);
    if (mounted) showSnack(context, on ? 'App lock is on' : 'App lock is off');
  }

  ReminderSettings _reminders = const ReminderSettings();

  static TimeOfDay _reportTime(ReminderSettings r) => TimeOfDay(hour: r.reportMinutes ~/ 60, minute: r.reportMinutes % 60);

  Future<void> _loadReminders() async {
    final r = await ref.read(reminderSchedulerProvider).settings();
    if (mounted) setState(() => _reminders = r);
  }

  Future<void> _saveReminders(ReminderSettings r) async {
    setState(() => _reminders = r);
    await ref.read(reminderSchedulerProvider).save(r);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(context: context, initialTime: _reportTime(_reminders));
    if (picked == null) return;
    await _saveReminders(_reminders.copyWith(reportMinutes: picked.hour * 60 + picked.minute));
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _ChangePasswordDialog());
    if ((changed ?? false) && mounted) showSnack(context, 'Password changed');
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
      appBar: AppBar(title: Text(tr('Settings'))),
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
            title: Text(tr('Change password')),
            subtitle: Text(tr('For logging in on this phone')),
            onTap: _changePassword,
          ),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(tr('Team & sync')),
            subtitle: Text(tr('Share projects with your team, back up to the cloud')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeamSyncScreen())),
          ),
          if (billing.setUp)
            ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(tr('My subscription')),
              subtitle: Text(tr('FieldOS Pro: manage, cancel or restore')),
              onTap: () => showMySubscription(context),
            ),

          const SectionHeader('App language', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(tr('App language')),
            subtitle: Text(ref.watch(languageProvider).nativeName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLanguagePicker(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: Text(tr('Text size')),
            subtitle: Text(tr(_textSizeLabel(ref.watch(textSizeProvider)))),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickTextSize,
          ),
          const SectionHeader('Reminders', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          SwitchListTile(
            secondary: const Icon(Icons.edit_notifications_outlined),
            title: Text(tr("Today's report reminder")),
            subtitle: Text(trf('Every evening at {time}, unless every running site already has one',
                {'time': MaterialLocalizations.of(context).formatTimeOfDay(_reportTime(_reminders))})),
            value: _reminders.reportOn,
            onChanged: (v) => _saveReminders(_reminders.copyWith(reportOn: v)),
          ),
          if (_reminders.reportOn)
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(tr('Change the time')),
              trailing: const Icon(Icons.schedule),
              onTap: _pickReminderTime,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.event_available_outlined),
            title: Text(tr('Tasks due today')),
            subtitle: Text(tr('At 8 am on the day a task is due')),
            value: _reminders.tasksOn,
            onChanged: (v) => _saveReminders(_reminders.copyWith(tasksOn: v)),
          ),
          if (canSeeMoneyIn(ref.watch(sessionProvider).role))
            SwitchListTile(
              secondary: const Icon(Icons.wb_twilight_outlined),
              title: Text(tr('Evening site brief')),
              subtitle: Text(tr('At 7:30 pm, which sites need you and why')),
              value: _reminders.briefOn,
              onChanged: (v) => _saveReminders(_reminders.copyWith(briefOn: v)),
            ),
          const SectionHeader('Security', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: Text(tr('App lock')),
            subtitle: Text(tr('Ask for a 4-digit PIN when FieldOS opens or comes back after a minute')),
            value: ref.watch(appLockOnProvider).value ?? false,
            onChanged: _toggleLock,
          ),
          const SectionHeader('Voice reports', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.record_voice_over_outlined),
            title: Text(tr('Language')),
            subtitle: Text(speechLanguageFor(_voiceLanguage).label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickLanguage,
          ),

          const SectionHeader('Your data', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            key: const Key('settings-export-excel'),
            leading: const Icon(Icons.table_view_outlined),
            title: Text(tr('Export all sites to Excel')),
            subtitle: Text(tr('Every record on this phone, in one file you keep. Free, always.')),
            onTap: () => exportCompanyToExcel(context, ref),
          ),
          if (canSeeMoneyIn(session.role))
            ListTile(
              key: const Key('settings-export-accounts'),
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(tr('Send to your accountant')),
              subtitle: Text(tr('Tally vouchers or a Zoho Books file, with GST split out')),
              onTap: () => showAccountsExport(context, ref),
            ),
          if (company != null && session.canManageSettings) ...[
            const SectionHeader('Bills and reports', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
            _BrandingTiles(companyId: company.id),
          ],
          const SectionHeader('Help', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(tr('Report a bug')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BugReportScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.mail_outline),
            title: Text(tr('Email support')),
            subtitle: const Text(Brand.supportEmail),
            onTap: () => emailSupport(subject: 'FieldOS: help'),
          ),

          const SectionHeader('About', padding: EdgeInsets.fromLTRB(20, 16, 20, 4)),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr('Privacy policy')),
            onTap: () => openPrivacyPolicy(context),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr('Terms of use')),
            onTap: () => openTerms(context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(tr('Open-source licences')),
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
            title: Text(tr('Version')),
            subtitle: Text(_version ?? ''),
          ),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: Text(tr('Log out')),
              onPressed: () {
                ref.read(cloudSyncBootstrapProvider).stop();
                ref.read(sessionProvider.notifier).logout();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(trf('Made in Hyderabad by {company}', {'company': Brand.companyName}),
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
      title: Text(tr('Change password')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _current,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: tr('Current password')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _next,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          onSubmitted: (_) => _busy ? null : _save(),
          decoration: InputDecoration(
            labelText: tr('New password'),
            helperText: trf('At least {n} characters', {'n': AuthService.minPasswordLength}),
          ),
        ),
        if (_error != null) ...[const SizedBox(height: 12), FormMessage(_error!)],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _busy ? null : _save, child: Text(tr('Change'))),
      ],
    );
  }
}

/// The company's logo on its PDFs, and whether they say "Made with FieldOS".
class _BrandingTiles extends ConsumerStatefulWidget {
  const _BrandingTiles({required this.companyId});
  final String companyId;

  @override
  ConsumerState<_BrandingTiles> createState() => _BrandingTilesState();
}

class _BrandingTilesState extends ConsumerState<_BrandingTiles> {
  PdfBranding? _branding;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final b = await loadBranding(ref.read(appDatabaseProvider), widget.companyId);
    if (mounted) setState(() => _branding = b);
  }

  Future<void> _pickLogo() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not open the photos.', error: true);
      return;
    }
    if (file == null) return;
    final ok = await saveLogo(ref.read(appDatabaseProvider), widget.companyId, await file.readAsBytes());
    if (!mounted) return;
    if (!ok) {
      showSnack(context, 'That file is not a picture. Pick a PNG or JPG.', error: true);
      return;
    }
    showSnack(context, 'Logo saved. It goes on your bills, vouchers and daily reports.');
    await _reload();
  }

  Future<void> _editFooter() async {
    final ctl = TextEditingController(text: _branding?.footerText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Your line at the foot of PDFs')),
        content: TextField(
          key: const Key('footer-text'),
          controller: ctl,
          maxLength: footerTextMax,
          decoration: InputDecoration(hintText: tr('e.g. 98480 12345 | www.saibuilders.in')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel'))),
          FilledButton(key: const Key('footer-save'), onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('Save'))),
        ],
      ),
    );
    ctl.dispose();
    if (text == null) return;
    await setFooterText(ref.read(appDatabaseProvider), widget.companyId, text);
    await _reload();
  }

  Future<void> _pickAccent() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(spacing: 12, runSpacing: 12, children: [
            for (final c in brandColours)
              InkWell(
                key: Key('accent-$c'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.pop(ctx, c),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Color(c),
                  child: (_branding?.accent ?? brandColours.first) == c ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              ),
          ]),
        ),
      ),
    );
    if (picked == null) return;
    await setAccent(ref.read(appDatabaseProvider), widget.companyId, picked == brandColours.first ? null : picked);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final b = _branding;
    return Column(children: [
      ListTile(
        key: const Key('settings-logo'),
        leading: b?.logo == null
            ? const Icon(Icons.image_outlined)
            : SizedBox(width: 40, height: 40, child: Image.memory(b!.logo!, fit: BoxFit.contain)),
        title: Text(tr('Company logo')),
        subtitle: Text(b?.logo == null
            ? tr('Put your logo on bills, vouchers and daily reports')
            : tr('On your bills, vouchers and daily reports. Tap to change.')),
        trailing: b?.logo == null
            ? null
            : IconButton(
                tooltip: tr('Remove logo'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  await removeLogo(ref.read(appDatabaseProvider), widget.companyId);
                  await _reload();
                },
              ),
        onTap: _pickLogo,
      ),
      SwitchListTile(
        key: const Key('settings-footer'),
        secondary: const Icon(Icons.short_text),
        title: Text(tr('Print "Made with FieldOS"')),
        subtitle: Text(tr('A small line at the foot of your PDFs')),
        value: b?.showFooter ?? true,
        onChanged: b == null
            ? null
            : (v) async {
                await setShowFooter(ref.read(appDatabaseProvider), widget.companyId, v);
                await _reload();
              },
      ),
      ListTile(
        key: const Key('settings-footer-text'),
        leading: const Icon(Icons.notes_outlined),
        title: Text(tr('Your line at the foot of PDFs')),
        subtitle: Text((b?.footerText ?? '').isEmpty ? tr('Phone, website, registration or a tagline') : b!.footerText),
        onTap: b == null ? null : _editFooter,
      ),
      ListTile(
        key: const Key('settings-accent'),
        leading: CircleAvatar(radius: 12, backgroundColor: Color(b?.accent ?? brandColours.first)),
        title: Text(tr('Your colour on PDFs')),
        subtitle: Text(tr('For the company name and headings')),
        onTap: b == null ? null : _pickAccent,
      ),
    ]);
  }
}
