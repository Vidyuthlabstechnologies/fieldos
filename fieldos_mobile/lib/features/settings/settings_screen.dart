import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fieldos_mobile/providers.dart';
import 'package:fieldos_mobile/services/settings_service.dart';
import 'package:fieldos_mobile/sync/cloud_sync_providers.dart';
import 'package:fieldos_mobile/sync/cloud_sync_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final settings = ref.watch(settingsServiceProvider);

    if (!session.canManageSettings) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: Text('Only a company owner can change settings.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SarvamKeyField(settings: settings),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const _CloudSyncSection(),
          ],
        ),
      ),
    );
  }
}

class _SarvamKeyField extends ConsumerStatefulWidget {
  const _SarvamKeyField({required this.settings});
  final SettingsService settings;

  @override
  ConsumerState<_SarvamKeyField> createState() => _SarvamKeyFieldState();
}

class _SarvamKeyFieldState extends ConsumerState<_SarvamKeyField> {
  final _key = TextEditingController();
  bool _saving = false;
  bool _configured = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    widget.settings.isVoiceConfigured().then((v) => mounted ? setState(() => _configured = v) : null);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.settings.setSarvamApiKey(_key.text.trim());
    _key.clear();
    final configured = await widget.settings.isVoiceConfigured();
    if (mounted) {
      setState(() {
        _saving = false;
        _configured = configured;
        _status = 'Saved. The key is stored locally and never shown again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Voice-to-DPR (Sarvam)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_configured ? 'API key is configured.' : 'No API key configured — voice-to-DPR is disabled.'),
        const SizedBox(height: 12),
        TextField(
          controller: _key,
          decoration: const InputDecoration(
            labelText: 'Sarvam API key',
            border: OutlineInputBorder(),
            // Write-only: no value is ever echoed back here.
          ),
          obscureText: true,
          autocorrect: false,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save key'),
        ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!, style: const TextStyle(color: Colors.green)),
        ],
        const SizedBox(height: 24),
        const Text(
          'Voice-to-DPR is the only feature that always needs a connection. '
          'Everything else in FieldOS Mobile runs fully offline unless you '
          'turn on cloud sync below.',
          style: TextStyle(color: Colors.grey),
        ),
      ],
    );
  }
}

/// "Enable cloud sync" / "Sync now" -- the two actions a user actually
/// triggers for lib/sync/cloud_sync_service.dart. Everything else in this
/// app is fully offline-first (see lib/sync/sync_engine.dart's docstring);
/// this section is the one place that reaches the network to share data
/// across an employee's devices/colleagues.
class _CloudSyncSection extends ConsumerStatefulWidget {
  const _CloudSyncSection();

  @override
  ConsumerState<_CloudSyncSection> createState() => _CloudSyncSectionState();
}

class _CloudSyncSectionState extends ConsumerState<_CloudSyncSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _enableSync() async {
    final service = ref.read(cloudSyncServiceProvider);
    setState(() => _busy = true);
    final result = await service.enableSync(email: _email.text.trim(), password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result.outcome) {
        case CloudSyncOutcome.signedIn:
          _status = 'Signed in -- this device is now linked to the shared account.';
          _statusIsError = false;
        case CloudSyncOutcome.signedUp:
          _status = 'Account created and signed in -- share this email/password with '
              'colleagues so their devices join the same synced data.';
          _statusIsError = false;
        case CloudSyncOutcome.failed:
          _status = result.error ?? 'Could not enable sync.';
          _statusIsError = true;
      }
    });
  }

  Future<void> _syncNow() async {
    final service = ref.read(cloudSyncServiceProvider);
    setState(() => _busy = true);
    try {
      final result = await service.syncNow();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusIsError = result.failed > 0;
        _status = result.failed > 0
            ? '${result.succeeded} pushed, ${result.failed} failed -- will retry next sync.'
            : 'Synced -- ${result.succeeded} change${result.succeeded == 1 ? '' : 's'} pushed, latest data pulled.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusIsError = true;
        _status = 'Sync failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(cloudSyncServiceProvider);
    final signedIn = service.isSignedIn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cloud sync', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          signedIn
              ? 'Cloud sync is on for this device.'
              : 'Off. Turn this on to share projects, DPRs, issues and workers '
                  'with the rest of your team across devices.',
        ),
        const SizedBox(height: 12),
        if (!signedIn) ...[
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
            obscureText: true,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _enableSync,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enable cloud sync'),
          ),
        ] else
          FilledButton(
            onPressed: _busy ? null : _syncNow,
            child: _busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sync now'),
          ),
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text(_status!, style: TextStyle(color: _statusIsError ? Colors.red : Colors.green)),
        ],
      ],
    );
  }
}
